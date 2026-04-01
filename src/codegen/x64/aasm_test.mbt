///|
test "aasm emits into selected list" {
  let bundle = @x64.AsmData::new("demo")
  bundle.emit(@x64.Tai::new(Label, "L0", []))
  bundle.switch(Globals)
  bundle.emit(@x64.Tai::new(Symbol, "_g", []))

  assert_eq(bundle.procedures.length(), 1)
  assert_eq(bundle.globals.length(), 1)
  assert_eq(bundle.const_data.length(), 0)
}

///|
test "aasm render prints non-empty sections" {
  let bundle = @x64.AsmData::new("demo")
  bundle.emit(@x64.Tai::new(Instruction, "mov", ["rax", "rbx"]))
  let text = bundle.render()

  assert_true(text.contains("[procedures]"))
  assert_true(text.contains("mov rax, rbx"))
}
