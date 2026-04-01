///|
fn first_value(matches : @argparse.Matches, key : String) -> String? {
  match matches.values.get(key) {
    Some(vals) if vals.length() > 0 => Some(vals[0])
    _ => None
  }
}

///|
fn input_path(matches : @argparse.Matches) -> String? {
  match first_value(matches, "file") {
    Some(path) => Some(path)
    None => first_value(matches, "input")
  }
}

///|
fn main {
  let cmd = @argparse.Command::new(
    "paspale",
    about="Pascal front-end driver",
    options=[
      @argparse.OptionArg::new("file", short='f', about="input Pascal file"),
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
  let options = @driver.CompileOptions::new(!continue_on_error)
  let output = @driver.compile_text(file_id, source, sink, options)

  if sink.length() == 0 {
    let linked = @driver.emit_and_link(
      output,
      "_build",
      @path.Path(path).basename().to_string(),
    )
    match linked {
      Ok(done) => {
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
        if @driver.toolchain_plan(done) is Some(plan) {
          println("assemble cmd: ")
          println(plan.assemble_cmd)
          println("link cmd: ")
          println(plan.link_cmd)
        }
      }
      Err(msg, _) => {
        println("error: backend failed")
        println(msg)
      }
    }
  } else {
    println(@diag.render_all(source_map, sink))
  }
}
