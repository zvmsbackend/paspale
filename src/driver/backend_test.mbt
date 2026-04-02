///|
fn contains_stage(stages : Array[CompileStage], stage : CompileStage) -> Bool {
  stages.iter().any(s => s == stage)
}

///|
async test "backend emit_and_link writes artifacts and stages" {
  let sink = @diag.DiagSink::new()
  let compiled = compile_text(
    0,
    "program P; var x: integer; begin x := 1; end.",
    sink,
    CompileOptions::default(),
  )
  assert_eq(sink.length(), 0)

  let out_dir = "_build/driver_backend_test"
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir) catch {
      _ => ()
    }
  }

  let output = emit_and_link(compiled, out_dir, "demo_prog") catch {
    BackendError(msg, _) => fail(msg)
  }
  assert_true(output.asm_path is Some(_))
  assert_true(output.object_path is Some(_))
  assert_true(output.executable_path is Some(_))
  assert_true(contains_stage(output.stages, EmitAsm))
  assert_true(contains_stage(output.stages, Assemble))
  assert_true(contains_stage(output.stages, Link))

  guard output.asm_path is Some(asm_path) else { fail("missing asm") }
  guard output.object_path is Some(obj_path) else { fail("missing object") }
  guard output.executable_path is Some(exe_path) else {
    fail("missing executable")
  }
  assert_true(@fs.path_exists(asm_path))
  assert_true(@fs.path_exists(obj_path))
  assert_true(@fs.path_exists(exe_path))

  guard toolchain_plan(output) is Some(plan) else {
    fail("missing toolchain plan")
  }
  assert_true(plan.assemble_cmd.contains("-fno-pie"))
  assert_true(plan.link_cmd.contains("-no-pie"))
}

///|
async test "backend emit_and_link fails without aasm output" {
  let empty_output : CompileOutput = {
    tokens: [],
    unit: None,
    resolver: None,
    ir: @ir.ModuleIr::new(),
    aasm_output: None,
    optimize_report: None,
    asm_path: None,
    object_path: None,
    executable_path: None,
    stages: [],
  }

  let mut got_error = false
  ignore(
    emit_and_link(empty_output, "_build", "missing_aasm") catch {
      BackendError(msg, out) => {
        assert_true(msg.contains("missing AASM output"))
        got_error = true
        out
      }
    },
  )
  assert_true(got_error)
}

///|
async test "backend emit_and_link reports assembler spawn failure" {
  let sink = @diag.DiagSink::new()
  let compiled = compile_text(
    0,
    "program P; begin end.",
    sink,
    CompileOptions::default(),
  )
  assert_eq(sink.length(), 0)

  let bad_toolchain = BackendToolchain::new(
    "definitely-not-a-real-assembler-binary",
    "cc",
    ["-c", "-fno-pie"],
    ["-no-pie"],
  )

  let mut got_error = false
  ignore(
    emit_and_link_with(
      compiled, "_build/driver_backend_test", "bad_toolchain", bad_toolchain,
    ) catch {
      BackendError(msg, out) => {
        assert_true(msg.contains("failed to spawn assembler process"))
        got_error = true
        out
      }
    },
  )
  assert_true(got_error)
}
