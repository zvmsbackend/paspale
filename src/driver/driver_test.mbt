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
  assert_eq(output.stages.length(), 6)
  assert_true(output.ir.reached(Parsed))
  assert_true(output.ir.reached(Resolved))
  assert_true(output.ir.reached(FirstPassed))
  assert_true(output.ir.reached(SecondPassed))
  assert_true(output.ir.first_pass is Some(_))
  assert_true(output.aasm_output is Some(_))
  assert_true(output.optimize_report is Some(_))
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
  assert_true(output.aasm_output is None)
  assert_true(output.optimize_report is None)
  assert_eq(output.stages.length(), 0)
  assert_false(output.ir.reached(Parsed))
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
  assert_true(output.aasm_output is Some(_))
  assert_true(output.optimize_report is Some(_))
  assert_eq(output.stages.length(), 6)
  assert_true(output.ir.reached(SecondPassed))
}

///|
test "toolchain plan supports custom assembler and linker" {
  let out : @driver.CompileOutput = {
    tokens: [],
    unit: None,
    resolver: None,
    ir: @ir.ModuleIr::new(),
    aasm_output: None,
    optimize_report: None,
    asm_path: Some("/tmp/demo.s"),
    object_path: Some("/tmp/demo.o"),
    executable_path: Some("/tmp/demo"),
    stages: [],
  }
  let toolchain = @driver.BackendToolchain::new("clang", "ld", ["-c", "-m64"], [
    "-m", "elf_x86_64",
  ])
  guard @driver.toolchain_plan_with(out, toolchain) is Some(plan) else {
    fail("expected toolchain plan")
  }
  assert_true(plan.assemble_cmd.contains("clang"))
  assert_true(plan.assemble_cmd.contains("-m64"))
  assert_true(plan.link_cmd.contains("ld"))
  assert_true(plan.link_cmd.contains("elf_x86_64"))
}

///|
test "driver optimize pass allocates virtual call argument registers" {
  let sink = @diag.DiagSink::new()
  let output = @driver.compile_text(
    0,
    "program P; procedure Foo(a, b: integer); begin end; begin Foo(1, 2); end.",
    sink,
    @driver.CompileOptions::default(),
  )

  assert_false(sink.has_error())
  guard output.optimize_report is Some(report) else {
    fail("expected optimize report")
  }
  assert_true(report.allocated_virtual_regs >= 1)
}
