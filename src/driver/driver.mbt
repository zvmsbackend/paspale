///|
pub struct CompileOptions {
  stop_on_error : Bool
}

///|
pub(all) enum CompileStage {
  Lex
  Parse
  Analyze
  FirstPass
  SecondPass
  Optimize
  EmitAsm
  Assemble
  Link
} derive(Show, Eq)

///|
pub fn CompileOptions::new(stop_on_error : Bool) -> CompileOptions {
  { stop_on_error, }
}

///|
pub impl Default for CompileOptions with default() {
  { stop_on_error: true }
}

///|
pub(all) struct CompileOutput {
  tokens : Array[@lexer.SpannedToken]
  unit : @ast.Spanned[@ast.CompilationUnit]?
  resolver : @semantic.Resolver?
  ir : @ir.ModuleIr
  aasm_output : @x64.AsmData?
  optimize_report : @x64.OptimizeReport?
  asm_path : String?
  object_path : String?
  executable_path : String?
  stages : Array[CompileStage]
}

///|
pub struct ToolchainPlan {
  asm_path : String
  object_path : String
  executable_path : String
  assemble_cmd : String
  link_cmd : String
}

///|
pub struct BackendToolchain {
  assembler : String
  linker : String
  assemble_flags : Array[String]
  link_flags : Array[String]
}

///|
pub fn BackendToolchain::new(
  assembler : String,
  linker : String,
  assemble_flags : Array[String],
  link_flags : Array[String],
) -> BackendToolchain {
  { assembler, linker, assemble_flags, link_flags }
}

///|
pub impl Default for BackendToolchain with default() {
  {
    assembler: "cc",
    linker: "cc",
    assemble_flags: ["-c", "-fno-pie"],
    link_flags: ["-no-pie"],
  }
}

///|
fn shell_quote(value : String) -> String {
  let escaped = value.replace_all(old="\"", new="\\\"")
  "\"\{escaped}\""
}

///|
fn render_cmd(program : String, args : Array[String]) -> String {
  let out = StringBuilder::new()
  out.write_string(program)
  for arg in args {
    out.write_string(" ")
    out.write_string(shell_quote(arg))
  }
  out.to_string()
}

///|
fn assemble_args(
  toolchain : BackendToolchain,
  asm_path : String,
  object_path : String,
) -> Array[String] {
  [..toolchain.assemble_flags, asm_path, "-o", object_path]
}

///|
fn link_args(
  toolchain : BackendToolchain,
  object_path : String,
  executable_path : String,
) -> Array[String] {
  [..toolchain.link_flags, object_path, "-o", executable_path]
}

///|
fn render_linkable_asm(unit_name : String, aasm : @x64.AsmData) -> String {
  fn is_reg(op : String) {
    op == "eax" ||
    op == "ebx" ||
    op == "ecx" ||
    op == "edx" ||
    op == "edi" ||
    op == "esi" ||
    op == "r8d" ||
    op == "r9d" ||
    op == "r12d" ||
    op == "r13d" ||
    op == "r14d" ||
    op == "r15d" ||
    op == "r10d" ||
    op == "r11d" ||
    op == "rsp" ||
    op == "rbp" ||
    op == "rax" ||
    op == "rbx" ||
    op == "rcx" ||
    op == "rdx" ||
    op == "rdi" ||
    op == "rsi" ||
    op == "r8" ||
    op == "r9" ||
    op == "r12" ||
    op == "r13" ||
    op == "r14" ||
    op == "r15" ||
    op == "r10" ||
    op == "r11"
  }
  fn is_int(op : String) {
    (try? @string.parse_int(op)) is Ok(_)
  }
  fn is_jcc(op : String) {
    op == "je" ||
    op == "jne" ||
    op == "jl" ||
    op == "jle" ||
    op == "jg" ||
    op == "jge"
  }
  fn is_mem(op : String) {
    op.has_prefix("[") && op.has_suffix("]")
  }

  let out = StringBuilder::new()
  out.write_string(".intel_syntax noprefix\n")
  if aasm.globals.length() > 0 {
    out.write_string(".data\n")
    for g in aasm.globals {
      if g.kind is Symbol {
        out.write_string(g.opcode)
        out.write_string(": .long 0\n")
      }
    }
  }
  out.write_string(".text\n")
  out.write_string(".globl main\n")
  out.write_string("main:\n")
  let mut wrote_ret = false
  for item in aasm.procedures {
    match item {
      { kind: Instruction, opcode: "mov", operands: [dst, src], .. } =>
        if (is_reg(dst) || is_mem(dst)) &&
          (is_reg(src) || is_mem(src) || is_int(src)) {
          let asm_dst = if is_mem(dst) && is_int(src) {
            "DWORD PTR \{dst}"
          } else {
            dst
          }
          out.write_string("  mov ")
          out.write_string(asm_dst)
          out.write_string(", ")
          out.write_string(src)
          out.write_string("\n")
        }
      { kind: Instruction, opcode: "add", operands: [dst, src], .. } =>
        if is_reg(dst) && (is_reg(src) || is_int(src)) {
          out.write_string("  add ")
          out.write_string(dst)
          out.write_string(", ")
          out.write_string(src)
          out.write_string("\n")
        }
      { kind: Instruction, opcode: "sub", operands: [dst, src], .. } =>
        if is_reg(dst) && (is_reg(src) || is_int(src)) {
          out.write_string("  sub ")
          out.write_string(dst)
          out.write_string(", ")
          out.write_string(src)
          out.write_string("\n")
        }
      { kind: Instruction, opcode: "cmp", operands: [dst, src], .. } =>
        if is_reg(dst) && (is_reg(src) || is_int(src)) {
          out.write_string("  cmp ")
          out.write_string(dst)
          out.write_string(", ")
          out.write_string(src)
          out.write_string("\n")
        }
      { kind: Instruction, opcode: "jmp", operands: [label], .. } => {
        out.write_string("  jmp ")
        out.write_string(label)
        out.write_string("\n")
      }
      {
        kind: Instruction,
        opcode: "push"
        | "pop" as opcode,
        operands: [op0],
        ..,
      } if is_reg(op0) => {
        out.write_string("  ")
        out.write_string(opcode)
        out.write_string(" ")
        out.write_string(op0)
        out.write_string("\n")
      }
      { kind: Instruction, opcode: "call", operands: [callee], .. } => {
        out.write_string("  call ")
        out.write_string(callee)
        out.write_string("\n")
      }
      { kind: Instruction, opcode, operands: [label], .. } if is_jcc(opcode) => {
        out.write_string("  ")
        out.write_string(opcode)
        out.write_string(" ")
        out.write_string(label)
        out.write_string("\n")
      }
      { kind: Label, opcode: label, .. } =>
        if label != "main" {
          out.write_string(label)
          out.write_string(":\n")
        }
      { kind: Instruction, opcode: "ret", .. } => {
        out.write_string("  ret\n")
        wrote_ret = true
      }
      _ => ()
    }
  }
  if !wrote_ret {
    out.write_string("  xor eax, eax\n")
    out.write_string("  ret\n")
  }
  out.write_string("\n# lowered from unit ")
  out.write_string(unit_name)
  out.write_string("\n")
  for line in aasm.render().split("\n") {
    if line.trim() != "" {
      out.write_string("# ")
      out.write_string(line.to_string())
      out.write_string("\n")
    }
  }
  out.to_string()
}

///|
pub fn toolchain_plan(output : CompileOutput) -> ToolchainPlan? {
  toolchain_plan_with(output, BackendToolchain::default())
}

///|
pub fn toolchain_plan_with(
  output : CompileOutput,
  toolchain : BackendToolchain,
) -> ToolchainPlan? {
  match (output.asm_path, output.object_path, output.executable_path) {
    (Some(asm_path), Some(object_path), Some(executable_path)) => {
      let assemble = assemble_args(toolchain, asm_path, object_path)
      let link = link_args(toolchain, object_path, executable_path)
      Some({
        asm_path,
        object_path,
        executable_path,
        assemble_cmd: render_cmd(toolchain.assembler, assemble),
        link_cmd: render_cmd(toolchain.linker, link),
      })
    }
    _ => None
  }
}

///|
fn push_stage(output : CompileOutput, stage : CompileStage) -> CompileOutput {
  { ..output, stages: output.stages + [stage] }
}

///|
fn mark_stage(
  stages : Array[CompileStage],
  module_ir : @ir.ModuleIr,
  stage : CompileStage,
) -> Unit {
  stages.push(stage)
  match stage {
    Parse => module_ir.mark_stage(Parsed)
    Analyze => module_ir.mark_stage(Resolved)
    FirstPass => module_ir.mark_stage(FirstPassed)
    SecondPass => module_ir.mark_stage(SecondPassed)
    _ => ()
  }
}

///|

///|
fn run_first_pass(
  module_ir : @ir.ModuleIr,
  unit : @ast.Spanned[@ast.CompilationUnit],
  resolver : @semantic.Resolver,
) -> @ast.Spanned[@ast.CompilationUnit] {
  let _ = resolver
  let result = @ir.run_first_pass_pipeline(unit)
  module_ir.set_first_pass_report(result.report)
  module_ir.mark_stage(FirstPassed)
  result.unit
}

///|
fn run_second_pass(
  module_ir : @ir.ModuleIr,
  unit : @ast.Spanned[@ast.CompilationUnit],
  resolver : @semantic.Resolver,
) -> @x64.AsmData {
  let _ = resolver
  module_ir.mark_stage(SecondPassed)
  @x64.lower_compilation_unit(unit)
}

///|
fn run_optimize_pass(
  module_ir : @ir.ModuleIr,
  lowered : @x64.AsmData,
) -> (@x64.AsmData, @x64.OptimizeReport) {
  let _ = module_ir
  @x64.optimize_aasm(lowered)
}

///|
fn should_continue(sink : @diag.DiagSink, options : CompileOptions) -> Bool {
  !options.stop_on_error || !sink.has_error()
}

///|
pub fn compile_tokens(
  file_id : Int,
  tokens : Array[@lexer.SpannedToken],
  sink : @diag.DiagSink,
  options : CompileOptions,
) -> CompileOutput {
  let module_ir = @ir.ModuleIr::new()
  let stages = []
  if !should_continue(sink, options) {
    return {
      tokens,
      unit: None,
      resolver: None,
      ir: module_ir,
      aasm_output: None,
      optimize_report: None,
      asm_path: None,
      object_path: None,
      executable_path: None,
      stages,
    }
  }

  mark_stage(stages, module_ir, Lex)
  let unit = @parser.parse_tokens(file_id, tokens, sink)
  mark_stage(stages, module_ir, Parse)
  if !should_continue(sink, options) {
    return {
      tokens,
      unit: Some(unit),
      resolver: None,
      ir: module_ir,
      aasm_output: None,
      optimize_report: None,
      asm_path: None,
      object_path: None,
      executable_path: None,
      stages,
    }
  }

  let resolver = @semantic.analyze(unit, sink)
  mark_stage(stages, module_ir, Analyze)
  if !should_continue(sink, options) {
    return {
      tokens,
      unit: Some(unit),
      resolver: Some(resolver),
      ir: module_ir,
      aasm_output: None,
      optimize_report: None,
      asm_path: None,
      object_path: None,
      executable_path: None,
      stages,
    }
  }

  let first_pass_unit = run_first_pass(module_ir, unit, resolver)
  mark_stage(stages, module_ir, FirstPass)

  let lowered = run_second_pass(module_ir, first_pass_unit, resolver)
  mark_stage(stages, module_ir, SecondPass)

  let (optimized, optimize_report) = run_optimize_pass(module_ir, lowered)
  mark_stage(stages, module_ir, Optimize)

  {
    tokens,
    unit: Some(unit),
    resolver: Some(resolver),
    ir: module_ir,
    aasm_output: Some(optimized),
    optimize_report: Some(optimize_report),
    asm_path: None,
    object_path: None,
    executable_path: None,
    stages,
  }
}

///|
pub fn compile_text(
  file_id : Int,
  source : String,
  sink : @diag.DiagSink,
  options : CompileOptions,
) -> CompileOutput {
  let tokens = @lexer.tokenize(file_id, source, sink)
  compile_tokens(file_id, tokens, sink, options)
}

///|
pub suberror BackendError {
  BackendError(String, CompileOutput)
}

///|
pub async fn emit_and_link(
  output : CompileOutput,
  out_dir : String,
  base_name : String,
) -> CompileOutput raise BackendError {
  emit_and_link_with(output, out_dir, base_name, BackendToolchain::default())
}

///|
pub async fn emit_and_link_with(
  output : CompileOutput,
  out_dir : String,
  base_name : String,
  toolchain : BackendToolchain,
) -> CompileOutput raise BackendError {
  guard output.aasm_output is Some(aasm) else {
    raise BackendError(
      "missing AASM output; run compile pipeline first", output,
    )
  }

  let asm_path = @path.Path(out_dir).join("\{base_name}.s")
  let object_path = @path.Path(out_dir).join("\{base_name}.o")
  let executable_path = @path.Path(out_dir).join(base_name)

  let unit_name = match output.unit {
    Some(cu) =>
      match cu.node {
        ProgramUnit(p) => p.name
        UnitModule(u) => u.name
        LibraryUnit(l) => l.name
      }
    None => "anonymous"
  }
  let rendered = render_linkable_asm(unit_name, aasm)
  @fs.write_string_to_file(asm_path.0, rendered) catch {
    err => raise BackendError("failed to write asm file: \{err}", output)
  }
  let after_emit = push_stage({ ..output, asm_path: Some(asm_path.0) }, EmitAsm)

  let assemble_argv = assemble_args(toolchain, asm_path.0, object_path.0)
  let (assemble_code, assemble_stdout, assemble_stderr) = @process.collect_output(
    toolchain.assembler,
    assemble_argv,
  ) catch {
    err =>
      raise BackendError(
        "failed to spawn assembler process: \{err}",
        after_emit,
      )
  }
  if assemble_code != 0 {
    let stdout_text = assemble_stdout.text() catch {
      _ => "<non-textual output>"
    }
    let stderr_text = assemble_stderr.text() catch {
      _ => "<non-textual output>"
    }
    raise BackendError(
      "assembler failed (exit=\{assemble_code})\ncmd: \{render_cmd(toolchain.assembler, assemble_argv)}\nstdout:\n\{stdout_text}\nstderr:\n\{stderr_text}",
      after_emit,
    )
  }
  let after_assemble = push_stage(
    { ..after_emit, object_path: Some(object_path.0) },
    Assemble,
  )

  let link_argv = link_args(toolchain, object_path.0, executable_path.0)
  let (link_code, link_stdout, link_stderr) = @process.collect_output(
    toolchain.linker,
    link_argv,
  ) catch {
    err =>
      raise BackendError(
        "failed to spawn linker process: \{err}",
        after_assemble,
      )
  }
  if link_code != 0 {
    let stdout_text = link_stdout.text() catch { _ => "<non-textual output>" }
    let stderr_text = link_stderr.text() catch { _ => "<non-textual output>" }
    raise BackendError(
      "linker failed (exit=\{link_code})\ncmd: \{render_cmd(toolchain.linker, link_argv)}\nstdout:\n\{stdout_text}\nstderr:\n\{stderr_text}",
      after_assemble,
    )
  }
  let after_link = push_stage(
    { ..after_assemble, executable_path: Some(executable_path.0) },
    Link,
  )

  after_link
}
