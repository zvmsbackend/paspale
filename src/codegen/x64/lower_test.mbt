///|
test "lower compilation unit emits call and mov" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(0, "program P; begin x := 1; Foo; end.", sink)
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("[procedures]"))
  assert_true(text.contains("main"))
  assert_true(text.contains("mov [x], v"))
  assert_true(text.contains("call Foo"))
}

///|
test "lower arithmetic literal expression to add/sub" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; begin x := 1 + 2; y := 5 - 3; end.", sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("add v"))
  assert_true(text.contains("sub v"))
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

  assert_true(text.contains("cmp eax, v"))
  assert_true(text.contains("jl .L_if_then"))
  assert_true(text.contains("jmp .L_if_else"))
}

///|
test "lower repeat and for statements to loop labels" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; var i: integer; begin repeat i := i + 1; until i > 2; for i := 1 to 3 do i := i + 1; end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains(".L_repeat_loop"))
  assert_true(text.contains(".L_repeat_end"))
  assert_true(text.contains(".L_for_check"))
  assert_true(text.contains(".L_for_continue"))
  assert_true(text.contains(".L_for_end"))
}

///|
test "lower break and continue to jmp" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; var i: integer; begin while i < 10 do begin continue; break; end; end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("jmp .L_while_loop"))
  assert_true(text.contains("jmp .L_while_end"))
}

///|
test "lower case statement to cmp and branch labels" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; var i: integer; begin case i of 1: i := 10; 2..3: i := 20; else i := 30; end; end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("cmp v"))
  assert_true(text.contains("je .L_case_branch"))
  assert_true(text.contains(", 2"))
  assert_true(text.contains(", 3"))
  assert_true(text.contains("jle .L_case_branch"))
  assert_true(text.contains(".L_case_else"))
  assert_true(text.contains(".L_case_end"))
}

///|
test "lower procedure declaration and call" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; var x: integer; procedure Foo; begin x := 1; end; begin Foo; end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("jmp .L_main_body"))
  assert_true(text.contains("Foo"))
  assert_true(text.contains("call Foo"))
}

///|
test "lower callable uses stack locals and unified exit label" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; function Foo: integer; var x: integer; begin x := 7; exit(x); end; begin end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("push rbp"))
  assert_true(text.contains("sub rsp, 16"))
  assert_true(text.contains("mov [rbp-8], v"))
  assert_true(text.contains("jmp .L_func_exit"))
  assert_true(text.contains("mov eax, [rbp-16]"))
  assert_true(text.contains("mov rsp, rbp"))
  assert_true(text.contains("pop rbp"))
}

///|
test "lower call passes args via stack and cleans caller stack" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; procedure Foo(a, b: integer); begin end; begin Foo(1, 2); end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("push v"))
  assert_true(text.contains("call Foo"))
  assert_true(text.contains("add rsp, 16"))
}

///|
test "lower callable reads parameter from rbp positive offset" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program P; procedure Foo(a: integer); var x: integer; begin x := a; end; begin Foo(1); end.",
    sink,
  )
  let out = @x64.lower_compilation_unit(cu)
  let text = out.render()

  assert_true(text.contains("[rbp+16]"))
}
