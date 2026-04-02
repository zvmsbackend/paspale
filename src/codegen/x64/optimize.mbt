///|
pub struct OptimizeReport {
  mut removed_redundant_mov : Int
  mut removed_empty_comment : Int
  mut allocated_virtual_regs : Int
  mut skipped_virtual_spills : Int
}

///|
pub fn OptimizeReport::new() -> OptimizeReport {
  {
    removed_redundant_mov: 0,
    removed_empty_comment: 0,
    allocated_virtual_regs: 0,
    skipped_virtual_spills: 0,
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
  if item.kind != Instruction {
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
fn replace_vreg_operand(op : String, alloc : PhysicalAllocation) -> String {
  match parse_vreg(op) {
    Some(v) =>
      match alloc.reg_of_vreg.get(v) {
        Some(r) => r
        None =>
          match alloc.spill_offset_of_vreg.get(v) {
            Some(ofs) => "[rbp-\{ofs}]"
            None => op
          }
      }
    None => op
  }
}

///|
fn rewrite_virtual_regs(
  list : Array[Tai],
  report : OptimizeReport,
) -> Array[Tai] {
  let insts = []
  for item in list {
    if classify_live(item) is Some(inst) {
      insts.push(inst)
    }
  }
  if insts.length() == 0 {
    return list
  }

  let alloc = allocate_physical(insts, ["eax", "ebx", "ecx", "edx"])
  if alloc.spill_offset_of_vreg.length() > 0 {
    report.skipped_virtual_spills += alloc.spill_offset_of_vreg.length()
    return list
  }

  report.allocated_virtual_regs += alloc.reg_of_vreg.length()
  let out = []
  for item in list {
    if item.kind == Instruction {
      let rewritten = []
      for op in item.operands {
        rewritten.push(replace_vreg_operand(op, alloc))
      }
      out.push({ ..item, operands: rewritten })
    } else {
      out.push(item)
    }
  }
  out
}

///|
fn is_redundant_mov(item : Tai) -> Bool {
  item.kind == Instruction &&
  item.opcode == "mov" &&
  item.operands.length() == 2 &&
  item.operands[0] == item.operands[1]
}

///|
fn is_empty_comment(item : Tai) -> Bool {
  item.kind == Comment && item.opcode.trim() == ""
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
  let lowered_procedures = rewrite_virtual_regs(input.procedures, report)
  out.procedures = optimize_list(lowered_procedures, report)
  out.globals = optimize_list(input.globals, report)
  out.const_data = optimize_list(input.const_data, report)
  out.imports = optimize_list(input.imports, report)
  out.exports = optimize_list(input.exports, report)
  out.rtti = optimize_list(input.rtti, report)
  out.dwarf_info = optimize_list(input.dwarf_info, report)
  (out, report)
}
