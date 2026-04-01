///|
fn contains_stage(
  stages : Array[@driver.CompileStage],
  stage : @driver.CompileStage,
) -> Bool {
  stages.iter().any(s => s == stage)
}

///|
async test "backend emit_and_link writes artifacts and stages" {
  let sink = @diag.DiagSink::new()
  let compiled = @driver.compile_text(
    0,
    "program P; var x: integer; begin x := 1; end.",
    sink,
    @driver.CompileOptions::default(),
  )
  assert_eq(sink.length(), 0)

  let out_dir = "_build/driver_backend_test"
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir) catch {
      _ => ()
    }
  }

  let linked = @driver.emit_and_link(compiled, out_dir, "demo_prog")
  match linked {
    Ok(output) => {
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

      guard @driver.toolchain_plan(output) is Some(plan) else {
        fail("missing toolchain plan")
      }
      assert_true(plan.assemble_cmd.contains("-fno-pie"))
      assert_true(plan.link_cmd.contains("-no-pie"))
    }
    Err(msg, _) => fail(msg)
  }
}
