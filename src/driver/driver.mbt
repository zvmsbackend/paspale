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
