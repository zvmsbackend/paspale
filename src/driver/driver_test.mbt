///|
test "driver pipeline succeeds for valid input" {
  let sink = @diag.DiagSink::new()
  let output = @driver.compile_text(
    0,
    "program P; var x: integer; begin x := 1; end.",
    sink,
    @driver.CompileOptions::default(),
  )

  assert_true(output.unit is Some(_))
  assert_true(output.resolver is Some(_))
  assert_eq(output.tokens.length() > 0, true)
  assert_false(sink.has_error())
}

///|
test "driver stop_on_error halts after lexing" {
  let sink = @diag.DiagSink::new()
  let output = @driver.compile_text(
    0,
    "program P; begin x := 'abc end.",
    sink,
    @driver.CompileOptions::default(),
  )

  assert_true(sink.has_error())
  assert_true(output.unit is None)
  assert_true(output.resolver is None)
}

///|
test "driver can continue after diagnostics" {
  let sink = @diag.DiagSink::new()
  let options = @driver.CompileOptions::new(false)
  let output = @driver.compile_text(
    0, "program P; begin x := 1; end.", sink, options,
  )

  assert_true(sink.has_error())
  assert_true(output.unit is Some(_))
  assert_true(output.resolver is Some(_))
}
