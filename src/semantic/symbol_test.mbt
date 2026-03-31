///|
fn has_diag_code(sink : @diag.DiagSink, code : String) -> Bool {
  sink.all().iter().any(d => d.code == code)
}

///|
test "semantic reports duplicate symbol in same scope" {
  let sink = @diag.new_sink()
  let src = "program P; var x: integer; x: integer; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0001"))
}

///|
test "semantic reports undefined symbol usage" {
  let sink = @diag.new_sink()
  let src = "program P; begin x := 1; end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0002"))
}

///|
test "semantic handles nested scope shadowing" {
  let sink = @diag.new_sink()
  let src = "program P; var x: integer; procedure Foo(x: integer); begin x := 1; end; begin x := 2; Foo(x); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_false(has_diag_code(sink, "S0001"))
  assert_false(has_diag_code(sink, "S0002"))
}

///|
test "semantic reports unknown named type" {
  let sink = @diag.new_sink()
  let src = "program P; var x: UnknownType; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0003"))
}

///|
test "semantic reports assignment type mismatch" {
  let sink = @diag.new_sink()
  let src = "program P; var i: integer; s: string; begin i := s; end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0010"))
}

///|
test "semantic reports call argument count mismatch" {
  let sink = @diag.new_sink()
  let src = "program P; procedure Foo(a: integer); begin end; begin Foo(); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0016"))
}

///|
test "semantic reports call argument type mismatch" {
  let sink = @diag.new_sink()
  let src = "program P; procedure Foo(a: integer); begin end; begin Foo(1.5); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0017"))
}
