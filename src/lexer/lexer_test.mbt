///|
fn dump_kinds(tokens : Array[@lexer.SpannedToken]) -> String {
  tokens.iter().map(t => t.kind().to_string()).join(" ")
}

///|
fn token_at(tokens : Array[@lexer.SpannedToken], i : Int) -> @lexer.Token {
  tokens[i].token
}

///|
test "lexer handles keywords identifiers and punctuation" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "Program Test; begin end.", sink)
  inspect(
    dump_kinds(tokens),
    content="KwProgram Identifier Semicolon KwBegin KwEnd Dot Eof",
  )
  assert_eq(sink.length(), 0)
}

///|
test "lexer keeps int range and comments" {
  let sink = @diag.DiagSink::new()
  let src = "x:=1..10; // range\n(* c *) y := $FF;"
  let tokens = @lexer.tokenize(0, src, sink)
  inspect(
    dump_kinds(tokens),
    content="Identifier Assign IntConst DotDot IntConst Semicolon Identifier Assign IntConst Semicolon Eof",
  )
  assert_eq(sink.length(), 0)
}

///|
test "lexer reports unterminated string" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "x := 'abc", sink)
  inspect(dump_kinds(tokens), content="Identifier Assign Eof")
  assert_eq(sink.length(), 1)
  assert_true(sink.has_error())
}

///|
test "lexer string literal and escaped quote" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "x := 'a''b';", sink)
  inspect(
    dump_kinds(tokens),
    content="Identifier Assign StringConst Semicolon Eof",
  )
  assert_eq(token_at(tokens, 2), StringConst("a'b"))
  assert_eq(sink.length(), 0)
}

///|
test "lexer string then identifier" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "'abc'x", sink)
  inspect(dump_kinds(tokens), content="StringConst Identifier Eof")
  assert_eq(token_at(tokens, 0), StringConst("abc"))
  assert_eq(token_at(tokens, 1), Identifier("x"))
  assert_eq(sink.length(), 0)
}

///|
test "lexer numbers real and range" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "1..10 1.23 1e10", sink)
  inspect(
    dump_kinds(tokens),
    content="IntConst DotDot IntConst RealConst RealConst Eof",
  )
  assert_eq(token_at(tokens, 0), IntConst("1"))
  assert_eq(token_at(tokens, 2), IntConst("10"))
  assert_eq(token_at(tokens, 3), RealConst("1.23"))
  assert_eq(token_at(tokens, 4), RealConst("1e10"))
  assert_eq(sink.length(), 0)
}

///|
test "lexer base-prefixed integers" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "$FF %1010 &77", sink)
  inspect(dump_kinds(tokens), content="IntConst IntConst IntConst Eof")
  assert_eq(token_at(tokens, 0), IntConst("$FF"))
  assert_eq(token_at(tokens, 1), IntConst("%1010"))
  assert_eq(token_at(tokens, 2), IntConst("&77"))
  assert_eq(sink.length(), 0)
}

///|
test "lexer keyword case-insensitive" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "program PROGRAM Program", sink)
  inspect(dump_kinds(tokens), content="KwProgram KwProgram KwProgram Eof")
  assert_eq(sink.length(), 0)
}

///|
test "lexer reports unterminated comments" {
  let sink = @diag.DiagSink::new()
  let _ = @lexer.tokenize(0, "{ abc (* def", sink)
  assert_true(sink.has_error())
  assert_eq(sink.length(), 1)
  assert_eq(sink.all()[0].code, "L0002")
}

///|
test "lexer span monotonic" {
  let sink = @diag.DiagSink::new()
  let tokens = @lexer.tokenize(0, "ab\nx:=1", sink)
  for i in 1..<tokens.length() {
    assert_true(tokens[i - 1].span.end <= tokens[i].span.start)
  }
  assert_eq(sink.length(), 0)
}
