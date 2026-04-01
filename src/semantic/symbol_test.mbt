///|
fn has_diag_code(sink : @diag.DiagSink, code : String) -> Bool {
  sink.all().iter().any(d => d.code == code)
}

///|
test "semantic reports duplicate symbol in same scope" {
  let sink = @diag.DiagSink::new()
  let src = "program P; var x: integer; x: integer; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0001"))
}

///|
test "semantic reports undefined symbol usage" {
  let sink = @diag.DiagSink::new()
  let src = "program P; begin x := 1; end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0002"))
}

///|
test "semantic handles nested scope shadowing" {
  let sink = @diag.DiagSink::new()
  let src = "program P; var x: integer; procedure Foo(x: integer); begin x := 1; end; begin x := 2; Foo(x); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_false(has_diag_code(sink, "S0001"))
  assert_false(has_diag_code(sink, "S0002"))
}

///|
test "semantic reports unknown named type" {
  let sink = @diag.DiagSink::new()
  let src = "program P; var x: UnknownType; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0003"))
}

///|
test "semantic reports assignment type mismatch" {
  let sink = @diag.DiagSink::new()
  let src = "program P; var i: integer; s: string; begin i := s; end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0010"))
}

///|
test "semantic reports call argument count mismatch" {
  let sink = @diag.DiagSink::new()
  let src = "program P; procedure Foo(a: integer); begin end; begin Foo(); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0016"))
}

///|
test "semantic reports call argument type mismatch" {
  let sink = @diag.DiagSink::new()
  let src = "program P; procedure Foo(a: integer); begin end; begin Foo(1.5); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0017"))
}

///|
test "semantic checks record field access" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type R = record x: integer; end; var r: R; begin r.x := 1; end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_false(has_diag_code(sink, "S0021"))
  assert_false(has_diag_code(sink, "S0022"))
}

///|
test "semantic reports unknown record field" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type R = record x: integer; end; var r: R; begin r.y := 1; end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0021"))
}

///|
test "semantic reports non-ordinal array index" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type A = array[1..10] of integer; var a: A; begin a[1.5] := 1; end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0020"))
}

///|
test "semantic checks exit expression type in function" {
  let sink = @diag.DiagSink::new()
  let src = "program P; function F: integer; begin exit('x'); end; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0023"))
}

///|
test "semantic rejects exit expression in procedure" {
  let sink = @diag.DiagSink::new()
  let src = "program P; procedure Q; begin exit(1); end; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0024"))
}

///|
test "semantic reports array index type declaration without subrange" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type A = array[1.5] of integer; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0025"))
}

///|
test "semantic reports invalid subrange bound order" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type R = 10..1; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0027"))
}

///|
test "semantic reports non-ordinal set element type" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type S = set of real; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0028"))
}

///|
test "semantic reports duplicate record field declaration" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type R = record x: integer; x: real; end; begin end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0029"))
}

///|
test "semantic reports VAR argument that is not assignable" {
  let sink = @diag.DiagSink::new()
  let src = "program P; procedure Bump(var x: integer); begin x := x + 1; end; begin Bump(1); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0030"))
}

///|
test "semantic reports OUT argument that is not assignable" {
  let sink = @diag.DiagSink::new()
  let src = "program P; procedure Fill(out x: integer); begin x := 1; end; begin Fill(1 + 2); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_true(has_diag_code(sink, "S0030"))
}

///|
test "semantic flattens grouped parameter names for arity" {
  let sink = @diag.DiagSink::new()
  let src = "program P; procedure Swap(var a, b: integer); begin end; var x, y: integer; begin Swap(x, y); end."
  let cu = @parser.parse_text(0, src, sink)
  let _ = @semantic.analyze(cu, sink)

  assert_false(has_diag_code(sink, "S0016"))
}
