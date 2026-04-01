///|
fn has_stage(
  stages : Array[@driver.CompileStage],
  stage : @driver.CompileStage,
) -> Bool {
  stages.iter().any(s => s == stage)
}

///|
fn compile_has_error(source : String, stop_on_error : Bool) -> Bool {
  let sink = @diag.DiagSink::new()
  let _ = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::new(stop_on_error),
  )
  sink.has_error()
}

///|
fn has_diag_code(sink : @diag.DiagSink, code : String) -> Bool {
  sink.all().iter().any(d => d.code == code)
}

///|
test "e2e valid program reaches optimize stage" {
  let source = "program P; var x: integer; begin x := 1; end."
  let sink = @diag.DiagSink::new()
  let out = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::default(),
  )

  assert_eq(sink.length(), 0)
  assert_true(out.unit is Some(_))
  assert_true(out.resolver is Some(_))
  assert_true(out.aasm_output is Some(_))
  assert_true(out.optimize_report is Some(_))
  assert_true(has_stage(out.stages, Optimize))
}

///|
test "e2e stop_on_error halts after semantic" {
  let source = "program P; begin x := 1; end."
  let sink = @diag.DiagSink::new()
  let out = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::default(),
  )

  assert_true(sink.has_error())
  assert_true(out.unit is Some(_))
  assert_true(out.resolver is Some(_))
  assert_true(out.aasm_output is None)
  assert_true(out.optimize_report is None)
  assert_false(has_stage(out.stages, Optimize))
}

///|
test "e2e continue_on_error reaches optimize" {
  let source = "program P; begin x := 1; end."
  let sink = @diag.DiagSink::new()
  let out = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::new(false),
  )

  assert_true(sink.has_error())
  assert_true(out.aasm_output is Some(_))
  assert_true(out.optimize_report is Some(_))
  assert_true(has_stage(out.stages, Optimize))
}

///|
test "e2e optimize removes redundant mov" {
  let source = "program P; var x: integer; begin x := x; end."
  let sink = @diag.DiagSink::new()
  let out = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::default(),
  )

  guard out.optimize_report is Some(report) else {
    fail("expected optimize report")
  }
  assert_true(report.removed_redundant_mov >= 1)
}

///|
test "freepascal regression tw4737-like for-loop type mismatch" {
  let source = "program P; var a: int64; i: integer; begin a:=0; for i:=a to 10 do begin end; end."
  assert_true(compile_has_error(source, true))
}

///|
test "freepascal regression tw4781a-like unresolved call" {
  let source = "program tw4781a; var U: integer; begin if U = 1 then writeln('UNdetected'); end."
  assert_true(compile_has_error(source, true))
}

///|
test "e2e control flow loop with break continue is accepted" {
  let source = "program P; var i: integer; begin for i := 1 to 3 do begin if i = 2 then continue; if i = 3 then break; end; end."
  let sink = @diag.DiagSink::new()
  let out = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::default(),
  )

  let codes = sink.all().map(d => d.code).join(",")
  assert_eq(codes, "")
  assert_true(out.optimize_report is Some(_))
}

///|
test "e2e control flow break outside loop is rejected" {
  let source = "program P; begin break; end."
  assert_true(compile_has_error(source, true))
}

///|
test "e2e control flow duplicate case labels is rejected" {
  let source = "program P; var i: integer; begin case i of 1: ; 1: ; end; end."
  assert_true(compile_has_error(source, true))
}

///|
test "e2e type boundary valid record array set" {
  let source = "program P; type R = record x: integer; end; A = array[1..3] of R; S = set of char; var arr: A; setv: S; begin arr[1].x := 1; end."
  let sink = @diag.DiagSink::new()
  let out = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::default(),
  )

  assert_eq(sink.length(), 0)
  assert_true(out.optimize_report is Some(_))
}

///|
test "e2e type boundary type/var same name is rejected" {
  let source = "program P; type S = set of char; var s: S; begin end."
  let sink = @diag.DiagSink::new()
  let _ = @driver.compile_text(
    0,
    source,
    sink,
    @driver.CompileOptions::default(),
  )

  assert_true(sink.has_error())
  assert_true(has_diag_code(sink, "S0001"))
}

///|
test "e2e type boundary invalid subrange is rejected" {
  let source = "program P; type R = 10..1; begin end."
  assert_true(compile_has_error(source, true))
}

///|
test "e2e type boundary invalid set element is rejected" {
  let source = "program P; type S = set of real; begin end."
  assert_true(compile_has_error(source, true))
}
