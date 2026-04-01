///|
pub struct OptimizeReport {
  mut removed_redundant_mov : Int
  mut removed_empty_comment : Int
}

///|
pub fn OptimizeReport::new() -> OptimizeReport {
  { removed_redundant_mov: 0, removed_empty_comment: 0 }
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
  out.procedures = optimize_list(input.procedures, report)
  out.globals = optimize_list(input.globals, report)
  out.const_data = optimize_list(input.const_data, report)
  out.imports = optimize_list(input.imports, report)
  out.exports = optimize_list(input.exports, report)
  out.rtti = optimize_list(input.rtti, report)
  out.dwarf_info = optimize_list(input.dwarf_info, report)
  (out, report)
}
