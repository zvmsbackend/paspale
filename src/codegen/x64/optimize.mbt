///|
pub struct OptimizeReport {
  mut removed_redundant_mov : Int
  mut removed_empty_comment : Int
  mut allocated_virtual_regs : Int
  mut skipped_virtual_spills : Int
  mut call_constraint_rehomes : Int
  mut call_constraint_spills : Int
}

///|
pub fn OptimizeReport::new() -> OptimizeReport {
  {
    removed_redundant_mov: 0,
    removed_empty_comment: 0,
    allocated_virtual_regs: 0,
    skipped_virtual_spills: 0,
    call_constraint_rehomes: 0,
    call_constraint_spills: 0,
  }
}

///|
fn parse_vreg(op : String) -> Int? {
  if !op.has_prefix("v") {
    return None
  }
  (try? @string.parse_int(op[1:])).to_option()
}

///|
fn operand_vregs(op : String, out : Array[Int]) -> Unit {
  if parse_vreg(op) is Some(v) {
    out.push(v)
  }
}

///|
fn classify_live(item : Tai) -> LiveInst? {
  if !(item.kind is Instruction) {
    return None
  }
  let uses = []
  let defs = []
  match (item.opcode, item.operands) {
    ("mov", [dst, src]) => {
      operand_vregs(dst, defs)
      operand_vregs(src, uses)
    }
    ("add", [dst, src]) | ("sub", [dst, src]) => {
      operand_vregs(dst, uses)
      operand_vregs(dst, defs)
      operand_vregs(src, uses)
    }
    ("cmp", [lhs, rhs]) => {
      operand_vregs(lhs, uses)
      operand_vregs(rhs, uses)
    }
    ("push", [src]) => operand_vregs(src, uses)
    ("pop", [dst]) => operand_vregs(dst, defs)
    _ => ()
  }
  if uses.length() == 0 && defs.length() == 0 {
    None
  } else {
    Some(LiveInst::new(uses, defs))
  }
}

///|
fn collect_cross_call_vregs(list : Array[Tai]) -> Map[Int, Bool] {
  let first = {}
  let last = {}
  let call_positions = []
  for i, item in list {
    if item.kind is Instruction && item.opcode == "call" {
      call_positions.push(i)
    }
    for op in item.operands {
      if parse_vreg(op) is Some(v) {
        if !first.contains(v) {
          first[v] = i
        }
        last[v] = i
      }
    }
  }

  let out = {}
  for v, start in first {
    let end_ = last.get_or_default(v, start)
    for cp in call_positions {
      if start < cp && cp < end_ {
        out[v] = true
        break
      }
    }
  }
  out
}

///|
fn is_callee_saved_reg(reg : String) -> Bool {
  reg == "ebx" ||
  reg == "r12d" ||
  reg == "r13d" ||
  reg == "r14d" ||
  reg == "r15d"
}

///|
let allocatable_int_regs : Array[String] = [
  "eax", "ecx", "edx", "esi", "edi", "r8d", "r9d", "r10d", "r11d", "ebx", "r12d",
  "r13d", "r14d", "r15d",
]

///|
fn allocate_with_call_constraints(
  plan : AllocationPlan,
  regs : Array[String],
  forced : Map[Int, Bool],
) -> (PhysicalAllocation, Int, Int) {
  let colors = plan.colors.copy()
  let mut rehomes = 0
  let mut forced_spills = 0

  for v, _ in forced {
    if v < 0 || v >= colors.length() {
      continue
    }
    let mut keep = false
    if colors[v] is Some(c) {
      if c >= 0 && c < regs.length() && is_callee_saved_reg(regs[c]) {
        keep = true
      }
    }
    if keep {
      continue
    }

    let mut reassigned : Int? = None
    for c in 0..<regs.length() {
      if !is_callee_saved_reg(regs[c]) {
        continue
      }
      let conflict = plan.adjacency[v]
        .iter()
        .any(n => colors[n] is Some(nc) && nc == c)
      if !conflict {
        reassigned = Some(c)
        break
      }
    }

    match reassigned {
      Some(c) => {
        colors[v] = Some(c)
        rehomes = rehomes + 1
      }
      None => {
        if colors[v] is Some(_) {
          forced_spills = forced_spills + 1
        }
        colors[v] = None
      }
    }
  }

  let reg_of_vreg = {}
  let spill_offset_of_vreg = {}
  let mut next_spill = 8

  for v, color in colors {
    match color {
      Some(c) if c >= 0 && c < regs.length() => reg_of_vreg[v] = regs[c]
      _ => {
        spill_offset_of_vreg[v] = next_spill
        next_spill = next_spill + 8
      }
    }
  }

  (
    { reg_of_vreg, spill_offset_of_vreg, stack_size: next_spill - 8 },
    rehomes,
    forced_spills,
  )
}

///|
fn replace_vreg_operand(op : String, alloc : PhysicalAllocation) -> String {
  guard parse_vreg(op) is Some(v) else { return op }
  if alloc.reg_of_vreg.get(v) is Some(r) {
    return r
  }
  match alloc.spill_offset_of_vreg.get(v) {
    Some(_) => "[__spill_v\{v}]"
    None => op
  }
}

///|
fn spill_symbols(alloc : PhysicalAllocation) -> Array[Tai] {
  alloc.spill_offset_of_vreg
  .keys()
  .map(v => Tai::new(Symbol, "__spill_v\{v}", []))
  .collect()
}

///|
fn push_with_span(
  out : Array[Tai],
  base : Tai,
  opcode : String,
  operands : Array[String],
) -> Unit {
  let next = Tai::new(Instruction, opcode, operands)
  match base.pos {
    Some(pos) => out.push(next.with_span(pos))
    None => out.push(next)
  }
}

///|
fn rewrite_with_possible_spill(
  item : Tai,
  alloc : PhysicalAllocation,
  out : Array[Tai],
) -> Unit {
  if item.kind != Instruction {
    out.push(item)
    return
  }
  match (item.opcode, item.operands) {
    ("mov", [dst, src]) => {
      let d = replace_vreg_operand(dst, alloc)
      let s = replace_vreg_operand(src, alloc)
      if d.has_prefix("[") && s.has_prefix("[") {
        push_with_span(out, item, "mov", ["r10d", s])
        push_with_span(out, item, "mov", [d, "r10d"])
      } else {
        push_with_span(out, item, "mov", [d, s])
      }
    }
    ("add", [dst, src]) | ("sub", [dst, src]) => {
      let d = replace_vreg_operand(dst, alloc)
      let s = replace_vreg_operand(src, alloc)
      if d.has_prefix("[") {
        push_with_span(out, item, "mov", ["r10d", d])
        if s.has_prefix("[") {
          push_with_span(out, item, "mov", ["r11d", s])
          push_with_span(out, item, item.opcode, ["r10d", "r11d"])
        } else {
          push_with_span(out, item, item.opcode, ["r10d", s])
        }
        push_with_span(out, item, "mov", [d, "r10d"])
      } else if s.has_prefix("[") {
        push_with_span(out, item, "mov", ["r11d", s])
        push_with_span(out, item, item.opcode, [d, "r11d"])
      } else {
        push_with_span(out, item, item.opcode, [d, s])
      }
    }
    ("cmp", [lhs, rhs]) => {
      let l = replace_vreg_operand(lhs, alloc)
      let r = replace_vreg_operand(rhs, alloc)
      let ll = if l.has_prefix("[") {
        push_with_span(out, item, "mov", ["r10d", l])
        "r10d"
      } else {
        l
      }
      let rr = if r.has_prefix("[") {
        push_with_span(out, item, "mov", ["r11d", r])
        "r11d"
      } else {
        r
      }
      push_with_span(out, item, "cmp", [ll, rr])
    }
    ("push", [src]) => {
      let s = replace_vreg_operand(src, alloc)
      if s.has_prefix("[") {
        push_with_span(out, item, "mov", ["r10d", s])
        push_with_span(out, item, "push", ["r10"])
      } else {
        push_with_span(out, item, "push", [s])
      }
    }
    ("pop", [dst]) => {
      let d = replace_vreg_operand(dst, alloc)
      if d.has_prefix("[") {
        push_with_span(out, item, "pop", ["r10"])
        push_with_span(out, item, "mov", [d, "r10d"])
      } else {
        push_with_span(out, item, "pop", [d])
      }
    }
    _ => {
      let rewritten = item.operands.map(op => replace_vreg_operand(op, alloc))
      out.push({ ..item, operands: rewritten })
    }
  }
}

///|
fn rewrite_virtual_regs(
  list : Array[Tai],
  report : OptimizeReport,
) -> (Array[Tai], Array[Tai]) {
  let insts = list.filter_map(classify_live)
  if insts.length() == 0 {
    return (list, [])
  }

  let plan = allocate_plan(insts, allocatable_int_regs.length())
  let cross_call = collect_cross_call_vregs(list)
  let (alloc, rehomes, forced_spills) = allocate_with_call_constraints(
    plan, allocatable_int_regs, cross_call,
  )
  report.skipped_virtual_spills += alloc.spill_offset_of_vreg.length()
  report.allocated_virtual_regs += alloc.reg_of_vreg.length()
  report.call_constraint_rehomes += rehomes
  report.call_constraint_spills += forced_spills
  let out = []
  for item in list {
    rewrite_with_possible_spill(item, alloc, out)
  }
  (out, spill_symbols(alloc))
}

///|
fn is_redundant_mov(item : Tai) -> Bool {
  item.kind is Instruction &&
  item.opcode == "mov" &&
  item.operands is [dst, src] &&
  dst == src
}

///|
fn is_empty_comment(item : Tai) -> Bool {
  item.kind is Comment && item.opcode.trim() == ""
}

///|
fn optimize_list(list : Array[Tai], report : OptimizeReport) -> Array[Tai] {
  let out = []
  for item in list {
    if is_redundant_mov(item) {
      report.removed_redundant_mov += 1
      continue
    }
    if is_empty_comment(item) {
      report.removed_empty_comment += 1
      continue
    }
    out.push(item)
  }
  out
}

///|
pub fn optimize_aasm(input : AsmData) -> (AsmData, OptimizeReport) {
  let report = OptimizeReport::new()
  let out = AsmData::new(input.name)
  let (lowered_procedures, spill_globals) = rewrite_virtual_regs(
    input.procedures,
    report,
  )
  out.procedures = optimize_list(lowered_procedures, report)
  out.globals = optimize_list([..input.globals, ..spill_globals], report)
  out.const_data = optimize_list(input.const_data, report)
  out.imports = optimize_list(input.imports, report)
  out.exports = optimize_list(input.exports, report)
  out.rtti = optimize_list(input.rtti, report)
  out.dwarf_info = optimize_list(input.dwarf_info, report)
  (out, report)
}
