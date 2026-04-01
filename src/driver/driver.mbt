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
pub fn CompileOptions::default() -> CompileOptions {
  { stop_on_error: true }
}

///|
pub struct CompileOutput {
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
pub(all) enum BackendResult {
  Ok(CompileOutput)
  Err(String, CompileOutput)
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
fn render_linkable_asm(unit_name : String, aasm : @x64.AsmData) -> String {
  fn is_reg(op : String) {
    op == "eax" ||
    op == "ebx" ||
    op == "ecx" ||
    op == "edx" ||
    op == "rax" ||
    op == "rbx" ||
    op == "rcx" ||
    op == "rdx"
  }
  fn is_int(op : String) {
    (try? @string.parse_int(op)) is Ok(_)
  }

  let out = StringBuilder::new()
  out.write_string(".intel_syntax noprefix\n")
  out.write_string(".text\n")
  out.write_string(".globl main\n")
  out.write_string("main:\n")
  let mut wrote_ret = false
  for item in aasm.procedures {
    match item {
      { kind: Instruction, opcode: "mov", operands: [dst, src], .. } =>
        if is_reg(dst) && (is_reg(src) || is_int(src)) {
          out.write_string("  mov ")
          out.write_string(dst)
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
  match (output.asm_path, output.object_path, output.executable_path) {
    (Some(asm_path), Some(object_path), Some(executable_path)) =>
      Some({
        asm_path,
        object_path,
        executable_path,
        assemble_cmd: "cc -c \"\{asm_path}\" -o \"\{object_path}\"",
        link_cmd: "cc \"\{object_path}\" -o \"\{executable_path}\"",
      })
    _ => None
  }
}

///|
fn push_stage(output : CompileOutput, stage : CompileStage) -> CompileOutput {
  let stages = output.stages.copy()
  stages.push(stage)
  { ..output, stages, }
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
) -> Unit {
  let _ = resolver
  let report = @ir.run_first_pass(unit)
  module_ir.set_first_pass_report(report)
  module_ir.mark_stage(FirstPassed)
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

  run_first_pass(module_ir, unit, resolver)
  mark_stage(stages, module_ir, FirstPass)

  let lowered = run_second_pass(module_ir, unit, resolver)
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
pub fn emit_and_link(
  output : CompileOutput,
  out_dir : String,
  base_name : String,
) -> BackendResult {
  guard output.aasm_output is Some(aasm) else {
    return Err("missing AASM output; run compile pipeline first", output)
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
    err => return Err("failed to write asm file: \{err}", output)
  }
  let after_emit = push_stage({ ..output, asm_path: Some(asm_path.0) }, EmitAsm)

  // Stub assemble stage: persisted as text artifact for now.
  @fs.write_string_to_file(object_path.0, "object(stub) from \{asm_path.0}\n") catch {
    err => return Err("failed to assemble object: \{err}", after_emit)
  }
  let after_assemble = push_stage(
    { ..after_emit, object_path: Some(object_path.0) },
    Assemble,
  )

  // Stub link stage: persisted as text artifact for now.
  @fs.write_string_to_file(
    executable_path.0,
    "executable(stub) linked from \{object_path}\n",
  ) catch {
    err => return Err("failed to link executable: \{err}", after_assemble)
  }
  let after_link = push_stage(
    { ..after_assemble, executable_path: Some(executable_path.0) },
    Link,
  )

  Ok(after_link)
}
