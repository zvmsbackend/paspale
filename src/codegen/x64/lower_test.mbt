///|
test "lower compilation unit emits call and mov" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(0, "program P; begin x := 1; Foo; end.", sink)
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("[procedures]"))
  assert_true(text.contains("main"))
  assert_true(text.contains("mov [x], 1"))
  assert_true(text.contains("; call Foo"))
}

///|
test "lower arithmetic literal expression to add/sub" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; begin x := 1 + 2; y := 5 - 3; end.", sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("add eax, 2"))
  assert_true(text.contains("sub eax, 3"))
}

///|
test "lower conditional flow to cmp and jumps" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; begin if 1 < 2 then x := 1 else x := 2; while 1 < 2 do x := 3; end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("cmp eax, 2"))
  assert_true(text.contains("jl .L_if_then"))
  assert_true(text.contains("jmp .L_if_else"))
}
