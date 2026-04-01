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
  stages : Array[CompileStage]
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
  resolver : @semantic.Resolver,
) -> Unit {
  let _ = resolver
  module_ir.mark_stage(SecondPassed)
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
    return { tokens, unit: None, resolver: None, ir: module_ir, stages }
  }

  mark_stage(stages, module_ir, Lex)
  let unit = @parser.parse_tokens(file_id, tokens, sink)
  mark_stage(stages, module_ir, Parse)
  if !should_continue(sink, options) {
    return { tokens, unit: Some(unit), resolver: None, ir: module_ir, stages }
  }

  let resolver = @semantic.analyze(unit, sink)
  mark_stage(stages, module_ir, Analyze)
  if !should_continue(sink, options) {
    return {
      tokens,
      unit: Some(unit),
      resolver: Some(resolver),
      ir: module_ir,
      stages,
    }
  }

  run_first_pass(module_ir, unit, resolver)
  mark_stage(stages, module_ir, FirstPass)

  run_second_pass(module_ir, resolver)
  mark_stage(stages, module_ir, SecondPass)

  { tokens, unit: Some(unit), resolver: Some(resolver), ir: module_ir, stages }
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
