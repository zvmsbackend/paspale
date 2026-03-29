///|
test "line/column uses character offsets" {
  let sm = @diag.new_source_map()
  let file = sm.add_file("sample.pas", "ab中\nxy")

  assert_eq(sm.line_col(file, 0), (1, 1))
  assert_eq(sm.line_col(file, 2), (1, 3))
  assert_eq(sm.line_col(file, 3), (1, 4))
  assert_eq(sm.line_col(file, 4), (2, 1))
}

///|
test "render one diagnostic" {
  let sm = @diag.new_source_map()
  let file = sm.add_file("main.pas", "begin\n  x := 1\nend")
  let span = @diag.Span::new(file, 8, 9)
  let d = @diag.Diagnostic::new(@diag.Error, "E0001", "unknown identifier")
    .with_label(@diag.Label::primary(span, "cannot resolve symbol"))
    .with_note("did you mean 'y'?")

  inspect(
    d.render(sm),
    content="main.pas:2:3: error[E0001]: unknown identifier\n  x := 1\n  ^ cannot resolve symbol\nnote: did you mean 'y'?",
  )
}
