///|
test "optimize pass removes redundant mov" {
  let input = @x64.AsmData::new("demo")
  input.emit(@x64.Tai::new(Instruction, "mov", ["x", "x"]))
  input.emit(@x64.Tai::new(Instruction, "mov", ["x", "y"]))

  let (optimized, report) = @x64.optimize_aasm(input)

  assert_eq(report.removed_redundant_mov, 1)
  assert_eq(optimized.procedures.length(), 1)
  assert_true(optimized.render().contains("mov x, y"))
}

///|
test "optimize pass allocates simple virtual registers" {
  let input = @x64.AsmData::new("demo")
  input.emit(@x64.Tai::new(Instruction, "mov", ["v0", "1"]))
  input.emit(@x64.Tai::new(Instruction, "mov", ["v1", "2"]))
  input.emit(@x64.Tai::new(Instruction, "add", ["v0", "v1"]))

  let (optimized, report) = @x64.optimize_aasm(input)
  let text = optimized.render()

  assert_true(report.allocated_virtual_regs >= 2)
  assert_true(!text.contains("v0"))
  assert_true(!text.contains("v1"))
}

///|
test "optimize pass rewrites virtual regs with spill fallback" {
  let input = @x64.AsmData::new("demo")
  input.emit(@x64.Tai::new(Instruction, "mov", ["v0", "1"]))
  input.emit(@x64.Tai::new(Instruction, "mov", ["v1", "2"]))
  input.emit(@x64.Tai::new(Instruction, "mov", ["v2", "3"]))
  input.emit(@x64.Tai::new(Instruction, "mov", ["v3", "4"]))
  input.emit(@x64.Tai::new(Instruction, "mov", ["v4", "5"]))
  input.emit(@x64.Tai::new(Instruction, "add", ["v0", "v1"]))
  input.emit(@x64.Tai::new(Instruction, "add", ["v0", "v2"]))
  input.emit(@x64.Tai::new(Instruction, "add", ["v0", "v3"]))
  input.emit(@x64.Tai::new(Instruction, "add", ["v0", "v4"]))

  let (optimized, report) = @x64.optimize_aasm(input)
  let text = optimized.render()

  assert_true(report.skipped_virtual_spills >= 1)
  assert_true(!text.contains("v0"))
  assert_true(text.contains("[__spill_v"))
  assert_true(text.contains("[globals]"))
  assert_true(text.contains("__spill_v"))
}
