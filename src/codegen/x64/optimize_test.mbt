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
