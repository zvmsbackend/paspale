///|
test "optimize pass removes redundant mov" {
  let input = AsmData::new("demo")
  input.emit(Tai::new(Instruction, "mov", ["x", "x"]))
  input.emit(Tai::new(Instruction, "mov", ["x", "y"]))

  let (optimized, report) = optimize_aasm(input)

  assert_eq(report.removed_redundant_mov, 1)
  assert_eq(optimized.procedures.length(), 1)
  assert_true(optimized.render().contains("mov x, y"))
}

///|
test "optimize pass allocates simple virtual registers" {
  let input = AsmData::new("demo")
  input.emit(Tai::new(Instruction, "mov", ["v0", "1"]))
  input.emit(Tai::new(Instruction, "mov", ["v1", "2"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v1"]))

  let (optimized, report) = optimize_aasm(input)
  let text = optimized.render()

  assert_true(report.allocated_virtual_regs >= 2)
  assert_true(!text.contains("v0"))
  assert_true(!text.contains("v1"))
}

///|
test "optimize pass rewrites virtual regs with spill fallback" {
  let input = AsmData::new("demo")
  input.emit(Tai::new(Instruction, "mov", ["v0", "1"]))
  input.emit(Tai::new(Instruction, "mov", ["v1", "2"]))
  input.emit(Tai::new(Instruction, "mov", ["v2", "3"]))
  input.emit(Tai::new(Instruction, "mov", ["v3", "4"]))
  input.emit(Tai::new(Instruction, "mov", ["v4", "5"]))
  input.emit(Tai::new(Instruction, "mov", ["v5", "6"]))
  input.emit(Tai::new(Instruction, "mov", ["v6", "7"]))
  input.emit(Tai::new(Instruction, "mov", ["v7", "8"]))
  input.emit(Tai::new(Instruction, "mov", ["v8", "9"]))
  input.emit(Tai::new(Instruction, "mov", ["v9", "10"]))
  input.emit(Tai::new(Instruction, "mov", ["v10", "11"]))
  input.emit(Tai::new(Instruction, "mov", ["v11", "12"]))
  input.emit(Tai::new(Instruction, "mov", ["v12", "13"]))
  input.emit(Tai::new(Instruction, "mov", ["v13", "14"]))
  input.emit(Tai::new(Instruction, "mov", ["v14", "15"]))
  input.emit(Tai::new(Instruction, "mov", ["v15", "16"]))
  input.emit(Tai::new(Instruction, "mov", ["v16", "17"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v1"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v2"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v3"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v4"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v5"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v6"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v7"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v8"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v9"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v10"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v11"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v12"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v13"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v14"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v15"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "v16"]))

  let (optimized, report) = optimize_aasm(input)
  let text = optimized.render()

  assert_true(report.skipped_virtual_spills >= 1)
  assert_true(!text.contains("v0"))
  assert_true(text.contains("[__spill_v"))
  assert_true(text.contains("[globals]"))
  assert_true(text.contains("__spill_v"))
}

///|
test "optimize pass prefers callee-saved register across call" {
  let input = AsmData::new("demo")
  input.emit(Tai::new(Instruction, "mov", ["v0", "1"]))
  input.emit(Tai::new(Instruction, "call", ["Foo"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "2"]))

  let (optimized, report) = optimize_aasm(input)
  let text = optimized.render()

  assert_true(report.skipped_virtual_spills == 0)
  assert_true(report.call_constraint_rehomes >= 1)
  assert_true(report.call_constraint_spills == 0)
  assert_true(text.contains("add ebx, 2"))
}

///|
test "optimize pass spills when cross-call vregs exceed callee-saved budget" {
  let input = AsmData::new("demo")
  input.emit(Tai::new(Instruction, "mov", ["v0", "1"]))
  input.emit(Tai::new(Instruction, "mov", ["v1", "2"]))
  input.emit(Tai::new(Instruction, "mov", ["v2", "3"]))
  input.emit(Tai::new(Instruction, "mov", ["v3", "4"]))
  input.emit(Tai::new(Instruction, "mov", ["v4", "5"]))
  input.emit(Tai::new(Instruction, "mov", ["v5", "6"]))
  input.emit(Tai::new(Instruction, "mov", ["v6", "7"]))
  input.emit(Tai::new(Instruction, "call", ["Foo"]))
  input.emit(Tai::new(Instruction, "add", ["v0", "3"]))
  input.emit(Tai::new(Instruction, "add", ["v1", "4"]))
  input.emit(Tai::new(Instruction, "add", ["v2", "5"]))
  input.emit(Tai::new(Instruction, "add", ["v3", "6"]))
  input.emit(Tai::new(Instruction, "add", ["v4", "7"]))
  input.emit(Tai::new(Instruction, "add", ["v5", "8"]))
  input.emit(Tai::new(Instruction, "add", ["v6", "9"]))

  let (optimized, report) = optimize_aasm(input)
  let text = optimized.render()

  assert_true(report.skipped_virtual_spills >= 1)
  assert_true(report.call_constraint_spills >= 1)
  assert_true(text.contains("[__spill_v"))
}
