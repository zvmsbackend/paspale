///|
fn @argparse.Matches::first_value(
  self : @argparse.Matches,
  key : String,
) -> String? {
  self.values.get(key).bind(vals => vals.get(0))
}

///|
fn input_path(matches : @argparse.Matches) -> String? {
  match matches.first_value("file") {
    Some(path) => Some(path)
    None => matches.first_value("input")
  }
}

///|
fn toolchain_from_matches(
  matches : @argparse.Matches,
) -> @driver.BackendToolchain {
  let assembler = matches.first_value("assembler").unwrap_or("cc")
  let linker = matches.first_value("linker").unwrap_or("cc")
  @driver.BackendToolchain::new(assembler, linker, ["-c", "-fno-pie"], [
    "-no-pie",
  ])
}

///|
async fn main {
  let cmd = @argparse.Command::new(
    "paspale",
    about="Pascal front-end driver",
    options=[
      @argparse.OptionArg::new("file", short='f', about="input Pascal file"),
      @argparse.OptionArg::new(
        "assembler",
        about="assembler executable (default: cc)",
      ),
      @argparse.OptionArg::new(
        "linker",
        about="linker executable (default: cc)",
      ),
    ],
    flags=[
      @argparse.FlagArg::new(
        "continue-on-error",
        about="continue pipeline even if diagnostics appear",
      ),
    ],
    positionals=[@argparse.PositionArg::new("input", about="input Pascal file")],
  )

  let matches = cmd.parse() catch {
    err => {
      println(err.to_string())
      return
    }
  }

  let path = match input_path(matches) {
    Some(path) => path
    None => {
      println("error: missing input file; use -f/--file or positional input")
      return
    }
  }

  let source = @fs.read_file_to_string(path) catch {
    err => {
      println("error: failed to read '")
      println(path)
      println("':")
      println(err.to_string())
      return
    }
  }

  let source_map = @diag.SourceMap::new()
  let file_id = source_map.add_file(path, source)
  let sink = @diag.DiagSink::new()
  let continue_on_error = matches.flags.get_or_default(
    "continue-on-error", false,
  )
  let toolchain = toolchain_from_matches(matches)
  let options = @driver.CompileOptions::new(!continue_on_error)
  let output = @driver.compile_text(file_id, source, sink, options)

  if sink.length() == 0 {
    let done = @driver.emit_and_link_with(
      output,
      "_build",
      @path.Path(path).basename().to_string(),
      toolchain,
    ) catch {
      BackendError(msg, _) => {
        println("error: backend failed")
        println(msg)
        return
      }
    }
    println("ok: compile/link succeeded")
    println("stages:")
    println(done.stages.length().to_string())
    if done.asm_path is Some(p) {
      println("asm: ")
      println(p)
    }
    if done.object_path is Some(p) {
      println("obj: ")
      println(p)
    }
    if done.executable_path is Some(p) {
      println("exe: ")
      println(p)
    }
    if @driver.toolchain_plan_with(done, toolchain) is Some(plan) {
      println("assemble cmd: ")
      println(plan.assemble_cmd)
      println("link cmd: ")
      println(plan.link_cmd)
    }
  } else {
    println(@diag.render_all(source_map, sink))
  }
}
