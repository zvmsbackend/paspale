///|
pub struct CompileOptions {
  stop_on_error : Bool
}

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
  if !should_continue(sink, options) {
    return { tokens, unit: None, resolver: None }
  }

  let unit = @parser.parse_tokens(file_id, tokens, sink)
  if !should_continue(sink, options) {
    return { tokens, unit: Some(unit), resolver: None }
  }

  let resolver = @semantic.analyze(unit, sink)
  { tokens, unit: Some(unit), resolver: Some(resolver) }
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
