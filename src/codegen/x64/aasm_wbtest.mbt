///|
test "aasm emits into selected list" {
  let bundle = AsmData::new("demo")
  bundle.emit(Tai::new(Label, "L0", []))
  bundle.switch(Globals)
  bundle.emit(Tai::new(Symbol, "_g", []))

  assert_eq(bundle.procedures.length(), 1)
  assert_eq(bundle.globals.length(), 1)
  assert_eq(bundle.const_data.length(), 0)
}

///|
test "aasm render prints non-empty sections" {
  let bundle = AsmData::new("demo")
  bundle.emit(Tai::new(Instruction, "mov", ["rax", "rbx"]))
  let text = bundle.render()

  assert_true(text.contains("[procedures]"))
  assert_true(text.contains("mov rax, rbx"))
}
