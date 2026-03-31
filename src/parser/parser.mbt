///|
fn ascii_upper(s : String) -> String {
  String::from_iter(s.iter().map(Char::to_ascii_uppercase))
}

///|
fn @diag.Span::join(a : @diag.Span, b : @diag.Span) -> @diag.Span {
  @diag.Span::new(a.file_id, a.start, b.end)
}

///|
struct Parser {
  tokens : Array[@lexer.SpannedToken]
  sink : @diag.DiagSink
  mut pos : Int
}

///|
fn Parser::at_eof(self : Parser) -> Bool {
  self.current().kind() is Eof
}

///|
fn Parser::current(self : Parser) -> @lexer.SpannedToken {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    self.tokens[self.tokens.length() - 1]
  }
}

///|
fn Parser::current_span(self : Parser) -> @diag.Span {
  self.current().span
}

///|
fn Parser::peek_kind(self : Parser, lookahead : Int) -> @lexer.TokenKind {
  let idx = self.pos + lookahead
  if idx < self.tokens.length() {
    self.tokens[idx].kind()
  } else {
    Eof
  }
}

///|
fn Parser::bump(self : Parser) -> @lexer.SpannedToken {
  let t = self.current()
  if self.pos + 1 < self.tokens.length() {
    self.pos = self.pos + 1
  }
  t
}

///|
fn token_is_word(tok : @lexer.Token, word : String) -> Bool {
  match tok {
    Identifier(s) => ascii_upper(s) == word
    _ => false
  }
}

///|
fn token_text(tok : @lexer.Token) -> String {
  match tok {
    Identifier(s) => s
    IntConst(s) => s
    RealConst(s) => s
    StringConst(s) => "'\{s}'"
    Plus => "+"
    Minus => "-"
    Star => "*"
    Slash => "/"
    Equal => "="
    Lt => "<"
    Gt => ">"
    Lte => "<="
    Gte => ">="
    NotEqual => "<>"
    Assign => ":="
    Colon => ":"
    Semicolon => ";"
    Comma => ","
    Dot => "."
    DotDot => ".."
    DotDotDot => "..."
    LParen => "("
    RParen => ")"
    LBracket => "["
    RBracket => "]"
    Caret => "^"
    At => "@"
    Eof => ""
    KwProgram => "program"
    KwUnit => "unit"
    KwUses => "uses"
    KwVar => "var"
    KwConst => "const"
    KwType => "type"
    KwBegin => "begin"
    KwEnd => "end"
    KwProcedure => "procedure"
    KwFunction => "function"
    KwIf => "if"
    KwThen => "then"
    KwElse => "else"
    KwWhile => "while"
    KwDo => "do"
    KwFor => "for"
    KwTo => "to"
    KwDownto => "downto"
    KwRepeat => "repeat"
    KwUntil => "until"
    KwCase => "case"
    KwOf => "of"
  }
}

///|
fn Parser::is_word(self : Parser, word : String) -> Bool {
  token_is_word(self.current().token, word)
}

///|
fn Parser::is_kind_or_word(
  self : Parser,
  kind : @lexer.TokenKind,
  word : String,
) -> Bool {
  self.current().kind() == kind || self.is_word(word)
}

///|
fn Parser::consume_word(self : Parser, word : String) -> Bool {
  if self.is_word(word) {
    ignore(self.bump())
    true
  } else {
    false
  }
}

///|
fn Parser::consume_kind(self : Parser, kind : @lexer.TokenKind) -> Bool {
  if self.current().kind() == kind {
    ignore(self.bump())
    true
  } else {
    false
  }
}

///|
fn Parser::consume_kw(
  self : Parser,
  kind : @lexer.TokenKind,
  word : String,
) -> Bool {
  self.consume_kind(kind) || self.consume_word(word)
}

///|
fn Parser::error_here(self : Parser, code : String, message : String) -> Unit {
  let span = self.current_span()
  self.sink.push(
    @diag.Diagnostic::new(@diag.Error, code, message).with_label(
      @diag.Label::primary(span, "here"),
    ),
  )
}

///|
fn Parser::error_trailing(self : Parser, context : String) -> Unit {
  if !self.at_eof() {
    self.error_here("P0021", "unexpected trailing tokens after \{context}")
  }
}

///|
fn Parser::expect_kind(
  self : Parser,
  kind : @lexer.TokenKind,
  expected : String,
) -> Unit {
  if !self.consume_kind(kind) {
    self.error_here("P0001", "expected \{expected}")
    if !self.at_eof() {
      ignore(self.bump())
    }
  }
}

///|
fn Parser::expect_word(self : Parser, word : String) -> Unit {
  if !self.consume_word(word) {
    self.error_here("P0001", "expected \{word}")
    if !self.at_eof() {
      ignore(self.bump())
    }
  }
}

///|
fn Parser::expect_kw(
  self : Parser,
  kind : @lexer.TokenKind,
  word : String,
) -> Unit {
  if !self.consume_kw(kind, word) {
    self.error_here("P0001", "expected \{word}")
    if !self.at_eof() {
      ignore(self.bump())
    }
  }
}

///|
fn Parser::take_identifier(self : Parser) -> String {
  match self.current().token {
    Identifier(s) => {
      ignore(self.bump())
      s
    }
    _ => {
      self.error_here("P0002", "expected identifier")
      if !self.at_eof() {
        ignore(self.bump())
      }
      "<error>"
    }
  }
}

///|
fn Parser::take_qualified_name(self : Parser) -> String {
  let name = StringBuilder::new()
  name.write_string(self.take_identifier())
  while self.consume_kind(Dot) {
    name.write_string(".")
    name.write_string(self.take_identifier())
  }
  name.to_string()
}

///|
fn make_expr(node : @ast.Expr, span : @diag.Span) -> @ast.Spanned[@ast.Expr] {
  @ast.Spanned::new(node, span)
}

///|
fn make_stmt(node : @ast.Stmt, span : @diag.Span) -> @ast.Spanned[@ast.Stmt] {
  @ast.Spanned::new(node, span)
}

///|
fn make_block(
  decls : Array[@ast.Spanned[@ast.Decl]],
  stmts : Array[@ast.Spanned[@ast.Stmt]],
  span : @diag.Span,
) -> @ast.Spanned[@ast.Block] {
  @ast.Spanned::new({ decls, stmts }, span)
}

///|
fn Parser::parse_primary(self : Parser) -> @ast.Spanned[@ast.Expr] {
  match self.current().token {
    IntConst(v) => {
      let t = self.bump()
      make_expr(@ast.Literal(@ast.Int(v)), t.span)
    }
    RealConst(v) => {
      let t = self.bump()
      make_expr(@ast.Literal(@ast.Real(v)), t.span)
    }
    StringConst(v) => {
      let t = self.bump()
      make_expr(@ast.Literal(@ast.String(v)), t.span)
    }
    Identifier(name) => {
      let t = self.bump()
      make_expr(@ast.Name(name), t.span)
    }
    LBracket => {
      let l = self.bump()
      let items = []
      if !self.consume_kind(RBracket) {
        items.push(self.parse_range_expr())
        while self.consume_kind(Comma) {
          items.push(self.parse_range_expr())
        }
        self.expect_kind(RBracket, "]")
      }
      let r = self.tokens[self.pos - 1].span
      make_expr(@ast.SetLiteral(items), l.span.join(r))
    }
    LParen => {
      let l = self.bump()
      let e = self.parse_expr()
      let r_span = if self.consume_kind(RParen) {
        self.tokens[self.pos - 1].span
      } else {
        self.error_here("P0003", "expected )")
        e.span
      }
      make_expr(@ast.Paren(e), l.span.join(r_span))
    }
    _ => {
      self.error_here("P0004", "expected expression")
      let t = self.bump()
      make_expr(@ast.Expr::Error, t.span)
    }
  }
}

///|
fn Parser::parse_postfix(
  self : Parser,
  base : @ast.Spanned[@ast.Expr],
) -> @ast.Spanned[@ast.Expr] {
  let mut left = base
  while true {
    if self.consume_kind(LParen) {
      let args : Array[@ast.Spanned[@ast.Expr]] = []
      if !self.consume_kind(RParen) {
        args.push(self.parse_expr())
        while self.consume_kind(Comma) {
          args.push(self.parse_expr())
        }
        self.expect_kind(RParen, ")")
      }
      let end_span = self.tokens[self.pos - 1].span
      left = make_expr(@ast.Call(left, args), left.span.join(end_span))
      continue
    }
    if self.consume_kind(LBracket) {
      let idx = self.parse_expr()
      self.expect_kind(RBracket, "]")
      let end_span = self.tokens[self.pos - 1].span
      left = make_expr(@ast.Index(left, idx), left.span.join(end_span))
      continue
    }
    if self.consume_kind(Dot) {
      let name = self.take_identifier()
      let end_span = self.tokens[self.pos - 1].span
      left = make_expr(@ast.Field(left, name), left.span.join(end_span))
      continue
    }
    break
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> @ast.Spanned[@ast.Expr] {
  let unary = match self.current().token {
    Plus => Some(@ast.Plus)
    Minus => Some(@ast.Minus)
    Caret => Some(@ast.Deref)
    At => Some(@ast.Addr)
    _ => if self.is_word("NOT") { Some(@ast.Not) } else { None }
  }
  match unary {
    Some(op) => {
      let t = self.bump()
      let rhs = self.parse_unary()
      make_expr(@ast.Unary(op, rhs), t.span.join(rhs.span))
    }
    None => self.parse_postfix(self.parse_primary())
  }
}

///|
fn Parser::current_binary_op(self : Parser) -> (@ast.BinaryOp, Int)? {
  match self.current().token {
    Star => Some((@ast.Mul, 70))
    Slash => Some((@ast.RealDiv, 70))
    Plus => Some((@ast.Add, 60))
    Minus => Some((@ast.Sub, 60))
    Equal => Some((@ast.Eq, 40))
    NotEqual => Some((@ast.Ne, 40))
    Lt => Some((@ast.Lt, 40))
    Lte => Some((@ast.Le, 40))
    Gt => Some((@ast.Gt, 40))
    Gte => Some((@ast.Ge, 40))
    Identifier(name) =>
      match ascii_upper(name) {
        "DIV" => Some((@ast.IntDiv, 70))
        "MOD" => Some((@ast.Mod, 70))
        "AND" => Some((@ast.And, 70))
        "SHL" => Some((@ast.Shl, 70))
        "SHR" => Some((@ast.Shr, 70))
        "OR" => Some((@ast.Or, 60))
        "XOR" => Some((@ast.Xor, 60))
        "IN" => Some((@ast.In, 40))
        "IS" => Some((@ast.Is, 40))
        "AS" => Some((@ast.As, 40))
        _ => None
      }
    _ => None
  }
}

///|
fn Parser::parse_binary(
  self : Parser,
  min_prec : Int,
) -> @ast.Spanned[@ast.Expr] {
  let mut left = self.parse_unary()
  while true {
    let op = self.current_binary_op()
    match op {
      Some((binary_op, prec)) if prec >= min_prec => {
        self.bump() |> ignore
        let right = self.parse_binary(prec + 1)
        left = make_expr(
          @ast.Binary(binary_op, left, right),
          left.span.join(right.span),
        )
      }
      _ => break
    }
  }
  left
}

///|
pub fn parse_expr_tokens(
  tokens : Array[@lexer.SpannedToken],
  sink : @diag.DiagSink,
) -> @ast.Spanned[@ast.Expr] {
  let stable_tokens = if tokens.length() == 0 {
    [@lexer.SpannedToken::new(Eof, @diag.Span::new(0, 0, 0))]
  } else {
    let last = tokens[tokens.length() - 1]
    if last.kind() is Eof {
      tokens
    } else {
      let with_eof = tokens
      with_eof.push(@lexer.SpannedToken::new(Eof, last.span))
      with_eof
    }
  }
  let p = { tokens: stable_tokens, sink, pos: 0 }
  let expr = p.parse_expr()
  p.error_trailing("expression")
  expr
}

///|
pub fn parse_expr_text(
  file_id : Int,
  source : String,
  sink : @diag.DiagSink,
) -> @ast.Spanned[@ast.Expr] {
  let tokens = @lexer.tokenize(file_id, source, sink)
  parse_expr_tokens(tokens, sink)
}

///|
pub fn Parser::parse_expr(self : Parser) -> @ast.Spanned[@ast.Expr] {
  self.parse_binary(0)
}

///|
fn Parser::parse_range_expr(self : Parser) -> @ast.Spanned[@ast.Expr] {
  let left = self.parse_expr()
  if self.consume_kind(DotDot) {
    let right = self.parse_expr()
    make_expr(@ast.Range(left, right), left.span.join(right.span))
  } else {
    left
  }
}

///|
fn make_type_expr(
  node : @ast.TypeExpr,
  span : @diag.Span,
) -> @ast.Spanned[@ast.TypeExpr] {
  @ast.Spanned::new(node, span)
}

///|
fn make_decl(node : @ast.Decl, span : @diag.Span) -> @ast.Spanned[@ast.Decl] {
  @ast.Spanned::new(node, span)
}

///|
fn make_param(
  node : @ast.ParamDecl,
  span : @diag.Span,
) -> @ast.Spanned[@ast.ParamDecl] {
  @ast.Spanned::new(node, span)
}

///|
fn make_directive(
  node : @ast.ProcDirective,
  span : @diag.Span,
) -> @ast.Spanned[@ast.ProcDirective] {
  @ast.Spanned::new(node, span)
}

///|
fn Parser::parse_type_expr(self : Parser) -> @ast.Spanned[@ast.TypeExpr] {
  if self.consume_kind(Caret) {
    let s = self.tokens[self.pos - 1].span
    let inner = self.parse_type_expr()
    return make_type_expr(@ast.Pointer(inner), s.join(inner.span))
  }

  if self.consume_word("SET") {
    let s = self.tokens[self.pos - 1].span
    self.expect_kw(KwOf, "OF")
    let inner = self.parse_type_expr()
    return make_type_expr(@ast.Set(inner), s.join(inner.span))
  }

  if self.consume_word("ARRAY") {
    let s = self.tokens[self.pos - 1].span
    self.expect_kind(LBracket, "[")
    let idx = self.parse_range_expr()
    self.expect_kind(RBracket, "]")
    self.expect_kw(KwOf, "OF")
    let elem = self.parse_type_expr()
    return make_type_expr(@ast.Array(idx, elem), s.join(elem.span))
  }

  if self.consume_word("RECORD") {
    let s = self.tokens[self.pos - 1].span
    let fields = []
    while !self.at_eof() && !self.is_kind_or_word(KwEnd, "END") {
      let names = [self.take_identifier()]
      while self.consume_kind(Comma) {
        names.push(self.take_identifier())
      }
      self.expect_kind(Colon, ":")
      let ty = self.parse_type_expr()
      fields.push(@ast.Spanned::new(@ast.FieldDecl::{ names, ty }, ty.span))
      ignore(self.consume_kind(Semicolon))
    }
    self.expect_kw(@lexer.KwEnd, "END")
    let end_span = self.tokens[self.pos - 1].span
    return make_type_expr(@ast.Record(fields), s.join(end_span))
  }

  if self.consume_kind(LParen) {
    let s = self.tokens[self.pos - 1].span
    let names = [self.take_identifier()]
    while self.consume_kind(Comma) {
      names.push(self.take_identifier())
    }
    self.expect_kind(RParen, ")")
    let end_span = self.tokens[self.pos - 1].span
    return make_type_expr(@ast.Enum(names), s.join(end_span))
  }

  let left = self.parse_expr()
  if self.consume_kind(DotDot) {
    let right = self.parse_expr()
    return make_type_expr(
      @ast.Subrange(left, right),
      left.span.join(right.span),
    )
  }

  match left.node {
    @ast.Name(name) => make_type_expr(@ast.Named(name), left.span)
    _ => {
      self.error_here("P0030", "expected type expression")
      make_type_expr(@ast.Error, left.span)
    }
  }
}

///|
fn Parser::parse_param_list(
  self : Parser,
) -> Array[@ast.Spanned[@ast.ParamDecl]] {
  let out = []
  if !self.consume_kind(LParen) {
    return out
  }
  if self.consume_kind(RParen) {
    return out
  }
  while !self.at_eof() {
    let mode = if self.consume_word("VAR") {
      @ast.Var
    } else if self.consume_word("CONST") {
      @ast.Const
    } else if self.consume_word("OUT") {
      @ast.Out
    } else {
      @ast.Value
    }
    let start = self.current_span()
    let names = [self.take_identifier()]
    while self.consume_kind(Comma) {
      names.push(self.take_identifier())
    }
    self.expect_kind(Colon, ":")
    let ty = self.parse_type_expr()
    out.push(make_param({ names, ty, mode }, start.join(ty.span)))
    if self.consume_kind(Semicolon) {
      continue
    }
    self.expect_kind(RParen, ")")
    break
  }
  out
}

///|
fn Parser::parse_proc_directives(
  self : Parser,
) -> Array[@ast.Spanned[@ast.ProcDirective]] {
  let out = []
  while true {
    let s = self.current_span()
    if self.consume_word("FORWARD") {
      out.push(make_directive(@ast.Forward, s))
    } else if self.consume_word("EXTERNAL") {
      let ext_name = match self.current().token {
        StringConst(v) => {
          ignore(self.bump())
          Some(v)
        }
        Identifier(v) => {
          ignore(self.bump())
          Some(v)
        }
        _ => None
      }
      out.push(make_directive(@ast.External(ext_name), s))
    } else if self.consume_word("INLINE") {
      out.push(make_directive(@ast.Inline, s))
    } else if self.consume_word("ASSEMBLER") {
      out.push(make_directive(@ast.Assembler, s))
    } else if self.consume_word("OVERLOAD") {
      out.push(make_directive(@ast.Overload, s))
    } else if self.consume_word("VIRTUAL") {
      out.push(make_directive(@ast.Virtual, s))
    } else if self.consume_word("ABSTRACT") {
      out.push(make_directive(@ast.Abstract, s))
    } else if self.consume_word("OVERRIDE") {
      out.push(make_directive(@ast.Override, s))
    } else if self.consume_word("CDECL") {
      out.push(make_directive(@ast.CallingConv(@ast.Cdecl), s))
    } else if self.consume_word("STDCALL") {
      out.push(make_directive(@ast.CallingConv(@ast.Stdcall), s))
    } else if self.consume_word("PASCAL") {
      out.push(make_directive(@ast.CallingConv(@ast.Pascal), s))
    } else if self.consume_word("REGISTER") {
      out.push(make_directive(@ast.CallingConv(@ast.Register), s))
    } else if self.consume_word("MESSAGE") {
      let msg = match self.current().token {
        StringConst(v) => {
          ignore(self.bump())
          v
        }
        Identifier(v) => {
          ignore(self.bump())
          v
        }
        IntConst(v) => {
          ignore(self.bump())
          v
        }
        _ => ""
      }
      out.push(make_directive(@ast.Message(msg), s))
    } else {
      break
    }
    ignore(self.consume_kind(Semicolon))
  }
  out
}

///|
fn Parser::parse_declarations(self : Parser) -> Array[@ast.Spanned[@ast.Decl]] {
  let decls = []
  while !self.at_eof() {
    if self.consume_word("LABEL") {
      let start = self.tokens[self.pos - 1].span
      let labels = []
      match self.current().token {
        Identifier(v) => {
          labels.push(v)
          ignore(self.bump())
        }
        IntConst(v) => {
          labels.push(v)
          ignore(self.bump())
        }
        _ => self.error_here("P0031", "expected label identifier")
      }
      while self.consume_kind(Comma) {
        match self.current().token {
          Identifier(v) => {
            labels.push(v)
            ignore(self.bump())
          }
          IntConst(v) => {
            labels.push(v)
            ignore(self.bump())
          }
          _ => self.error_here("P0031", "expected label identifier")
        }
      }
      self.expect_kind(Semicolon, ";")
      decls.push(make_decl(@ast.LabelDecl(labels), start))
      continue
    }

    if self.is_kind_or_word(KwConst, "CONST") {
      ignore(self.consume_kw(KwConst, "CONST"))
      while !self.at_eof() && self.current().kind() is Identifier {
        let start = self.current_span()
        let name = self.take_identifier()
        self.expect_kind(Equal, "=")
        let value = self.parse_expr()
        decls.push(
          make_decl(@ast.ConstDecl(name, value), start.join(value.span)),
        )
        self.expect_kind(Semicolon, ";")
      }
      continue
    }

    if self.is_kind_or_word(KwType, "TYPE") {
      ignore(self.consume_kw(KwType, "TYPE"))
      while !self.at_eof() && self.current().kind() is Identifier {
        let start = self.current_span()
        let name = self.take_identifier()
        self.expect_kind(Equal, "=")
        let ty = self.parse_type_expr()
        decls.push(make_decl(@ast.TypeDecl(name, ty), start.join(ty.span)))
        self.expect_kind(Semicolon, ";")
      }
      continue
    }

    if self.is_kind_or_word(KwVar, "VAR") {
      ignore(self.consume_kw(KwVar, "VAR"))
      while !self.at_eof() && self.current().kind() is Identifier {
        let start = self.current_span()
        let names = [self.take_identifier()]
        while self.consume_kind(Comma) {
          names.push(self.take_identifier())
        }
        self.expect_kind(Colon, ":")
        let ty = self.parse_type_expr()
        let init = if self.consume_kind(Equal) {
          Some(self.parse_expr())
        } else {
          None
        }
        let end_span = match init {
          Some(v) => v.span
          None => ty.span
        }
        decls.push(
          make_decl(@ast.VarDecl(names, ty, init), start.join(end_span)),
        )
        self.expect_kind(Semicolon, ";")
      }
      continue
    }

    if self.is_kind_or_word(KwProcedure, "PROCEDURE") {
      let start = self.current_span()
      ignore(self.consume_kw(KwProcedure, "PROCEDURE"))
      let name = self.take_identifier()
      let params = self.parse_param_list()
      self.expect_kind(Semicolon, ";")
      let directives = self.parse_proc_directives()
      let has_no_body = directives
        .iter()
        .any(d => d.node is (Forward | External(_)))
      let body = if has_no_body { None } else { Some(self.parse_block()) }
      ignore(self.consume_kind(Semicolon))
      let end_span = match body {
        Some(b) => b.span
        None =>
          if self.pos > 0 {
            self.tokens[self.pos - 1].span
          } else {
            start
          }
      }
      decls.push(
        make_decl(
          @ast.ProcDecl({ name, params, directives, body }),
          start.join(end_span),
        ),
      )
      continue
    }

    if self.is_kind_or_word(KwFunction, "FUNCTION") {
      let start = self.current_span()
      ignore(self.consume_kw(KwFunction, "FUNCTION"))
      let name = self.take_identifier()
      let params = self.parse_param_list()
      self.expect_kind(Colon, ":")
      let result_ty = self.parse_type_expr()
      self.expect_kind(Semicolon, ";")
      let directives = self.parse_proc_directives()
      let has_no_body = directives
        .iter()
        .any(d => d.node is (Forward | External(_)))
      let body = if has_no_body { None } else { Some(self.parse_block()) }
      ignore(self.consume_kind(Semicolon))
      let end_span = match body {
        Some(b) => b.span
        None =>
          if self.pos > 0 {
            self.tokens[self.pos - 1].span
          } else {
            start
          }
      }
      decls.push(
        make_decl(
          @ast.FuncDecl({ name, params, result_ty, directives, body }),
          start.join(end_span),
        ),
      )
      continue
    }

    break
  }
  decls
}

///|
fn Parser::is_stmt_end(self : Parser) -> Bool {
  self.current().kind() is (KwEnd | KwElse | KwUntil) ||
  self.is_word("END") ||
  self.is_word("ELSE") ||
  self.is_word("UNTIL") ||
  self.is_word("EXCEPT") ||
  self.is_word("FINALLY") ||
  self.at_eof()
}

///|
fn Parser::parse_statement(self : Parser) -> @ast.Spanned[@ast.Stmt] {
  if self.consume_kw(KwBegin, "BEGIN") {
    let begin_span = self.tokens[self.pos - 1].span
    let stmts = []
    while !self.at_eof() && self.current().kind() != KwEnd {
      stmts.push(self.parse_statement())
      if !self.consume_kind(Semicolon) {
        break
      }
    }
    self.expect_kind(KwEnd, "end")
    let end_span = self.tokens[self.pos - 1].span
    return make_stmt(@ast.Compound(stmts), begin_span.join(end_span))
  }

  if self.consume_kw(KwIf, "IF") {
    let if_span = self.tokens[self.pos - 1].span
    let cond = self.parse_expr()
    self.expect_kw(KwThen, "THEN")
    let then_stmt = self.parse_statement()
    let else_stmt = if self.consume_kw(KwElse, "ELSE") {
      Some(self.parse_statement())
    } else {
      None
    }
    let end_span = match else_stmt {
      Some(s) => s.span
      None => then_stmt.span
    }
    return make_stmt(
      @ast.If(cond, then_stmt, else_stmt),
      if_span.join(end_span),
    )
  }

  if self.consume_kw(KwWhile, "WHILE") {
    let w_span = self.tokens[self.pos - 1].span
    let cond = self.parse_expr()
    self.expect_kw(KwDo, "DO")
    let body = self.parse_statement()
    return make_stmt(@ast.While(cond, body), w_span.join(body.span))
  }

  if self.consume_kw(KwRepeat, "REPEAT") {
    let r_span = self.tokens[self.pos - 1].span
    let stmts = []
    while !self.at_eof() &&
          self.current().kind() != KwUntil &&
          !self.is_word("UNTIL") {
      stmts.push(self.parse_statement())
      self.consume_kind(Semicolon) |> ignore
    }
    self.expect_kw(KwUntil, "UNTIL")
    let cond = self.parse_expr()
    return make_stmt(@ast.RepeatUntil(stmts, cond), r_span.join(cond.span))
  }

  if self.consume_kw(KwFor, "FOR") {
    let f_span = self.tokens[self.pos - 1].span
    let loop_var = self.parse_expr()
    self.expect_kind(Assign, ":=")
    let from_ = self.parse_expr()
    let dir = if self.consume_kind(KwDownto) || self.consume_word("DOWNTO") {
      @ast.Downto
    } else {
      self.expect_kw(KwTo, "TO")
      @ast.To
    }
    let to_ = self.parse_expr()
    self.expect_kw(KwDo, "DO")
    let body = self.parse_statement()
    return make_stmt(
      @ast.For(loop_var, from_, dir, to_, body),
      f_span.join(body.span),
    )
  }

  if self.consume_kw(KwCase, "CASE") {
    let start = self.tokens[self.pos - 1].span
    let cond = self.parse_expr()
    self.expect_kw(KwOf, "OF")
    let branches = []
    while !self.at_eof() &&
          self.current().kind() != KwElse &&
          self.current().kind() != KwEnd &&
          !self.is_word("ELSE") &&
          !self.is_word("END") {
      let labels = [self.parse_range_expr()]
      while self.consume_kind(Comma) {
        labels.push(self.parse_range_expr())
      }
      self.expect_kind(Colon, ":")
      let body = self.parse_statement()
      branches.push(
        @ast.Spanned::new(@ast.CaseBranch::{ labels, body }, body.span),
      )
      ignore(self.consume_kind(Semicolon))
    }
    let else_stmt = if self.consume_kw(KwElse, "ELSE") {
      let s = self.parse_statement()
      ignore(self.consume_kind(Semicolon))
      Some(s)
    } else {
      None
    }
    self.expect_kw(KwEnd, "END")
    let end_span = self.tokens[self.pos - 1].span
    return make_stmt(@ast.Case(cond, branches, else_stmt), start.join(end_span))
  }

  if self.consume_word("TRY") {
    let start = self.tokens[self.pos - 1].span
    let try_stmts = []
    while !self.at_eof() && !self.is_word("EXCEPT") && !self.is_word("FINALLY") {
      try_stmts.push(self.parse_statement())
      ignore(self.consume_kind(Semicolon))
    }
    let try_inner_end = if try_stmts.length() > 0 {
      try_stmts[try_stmts.length() - 1].span
    } else {
      start
    }
    let try_block = make_stmt(
      @ast.Compound(try_stmts),
      start.join(try_inner_end),
    )
    if self.consume_word("EXCEPT") {
      let handlers = []
      let mut default_handler : @ast.Spanned[@ast.Stmt]? = None
      while !self.at_eof() &&
            self.current().kind() != KwElse &&
            self.current().kind() != KwEnd &&
            !self.is_word("ELSE") &&
            !self.is_word("END") {
        if self.consume_word("ON") {
          let h_start = self.current_span()
          let name = self.take_identifier()
          self.expect_kind(Colon, ":")
          let ty = self.parse_type_expr()
          self.expect_kw(KwDo, "DO")
          let body = self.parse_statement()
          handlers.push(
            @ast.Spanned::new(
              @ast.ExceptHandler::{ name: Some(name), ty: Some(ty), body },
              h_start.join(body.span),
            ),
          )
        } else {
          break
        }
        ignore(self.consume_kind(Semicolon))
      }
      if self.consume_kw(KwElse, "ELSE") {
        default_handler = Some(self.parse_statement())
        ignore(self.consume_kind(Semicolon))
      }
      self.expect_kw(KwEnd, "END")
      let end_span = self.tokens[self.pos - 1].span
      return make_stmt(
        @ast.TryExcept(try_block, handlers, default_handler),
        start.join(end_span),
      )
    }
    if self.consume_word("FINALLY") {
      let finally_start = self.tokens[self.pos - 1].span
      let finally_stmts = []
      while !self.at_eof() && !self.is_kind_or_word(KwEnd, "END") {
        finally_stmts.push(self.parse_statement())
        ignore(self.consume_kind(Semicolon))
      }
      self.expect_kw(KwEnd, "END")
      let end_span = self.tokens[self.pos - 1].span
      let finally_inner_end = if finally_stmts.length() > 0 {
        finally_stmts[finally_stmts.length() - 1].span
      } else {
        finally_start
      }
      let finally_block = make_stmt(
        @ast.Compound(finally_stmts),
        finally_start.join(finally_inner_end),
      )
      return make_stmt(
        @ast.TryFinally(try_block, finally_block),
        start.join(end_span),
      )
    }
    self.error_here("P0040", "expected EXCEPT or FINALLY")
    return make_stmt(@ast.Error, start)
  }

  if self.consume_word("RAISE") {
    let s = self.tokens[self.pos - 1].span
    let value = if self.current().kind() is Semicolon || self.is_stmt_end() {
      None
    } else {
      Some(self.parse_expr())
    }
    let end_span = match value {
      Some(v) => v.span
      None => s
    }
    return make_stmt(@ast.Raise(value), s.join(end_span))
  }

  if self.consume_word("BREAK") {
    let s = self.tokens[self.pos - 1].span
    return make_stmt(@ast.Break, s)
  }

  if self.consume_word("CONTINUE") {
    let s = self.tokens[self.pos - 1].span
    return make_stmt(@ast.Continue, s)
  }

  if self.consume_word("EXIT") {
    let s = self.tokens[self.pos - 1].span
    let value = if self.consume_kind(LParen) {
      let e = self.parse_expr()
      self.expect_kind(RParen, ")")
      Some(e)
    } else {
      None
    }
    let end_span = match value {
      Some(v) => v.span
      None => s
    }
    return make_stmt(@ast.Exit(value), s.join(end_span))
  }

  if self.consume_word("GOTO") {
    let s = self.tokens[self.pos - 1].span
    let label_span = self.current_span()
    let label = self.take_identifier()
    return make_stmt(@ast.Goto(label), s.join(label_span))
  }

  if self.consume_word("WITH") {
    let s = self.tokens[self.pos - 1].span
    let values = [self.parse_expr()]
    while self.consume_kind(Comma) {
      values.push(self.parse_expr())
    }
    self.expect_kw(KwDo, "DO")
    let body = self.parse_statement()
    return make_stmt(@ast.With(values, body), s.join(body.span))
  }

  if self.consume_word("ASM") {
    let s = self.tokens[self.pos - 1].span
    let out = StringBuilder::new()
    let mut first = true
    while !self.at_eof() && !self.is_kind_or_word(KwEnd, "END") {
      let text = token_text(self.current().token)
      if text != "" {
        if !first {
          out.write_string(" ")
        }
        out.write_string(text)
        first = false
      }
      ignore(self.bump())
    }
    self.expect_kw(KwEnd, "END")
    let end_span = self.tokens[self.pos - 1].span
    return make_stmt(@ast.Asm(out.to_string()), s.join(end_span))
  }

  match self.current().token {
    Identifier(label) if self.peek_kind(1) == Colon => {
      let s = self.current_span()
      ignore(self.bump())
      self.expect_kind(Colon, ":")
      let body = self.parse_statement()
      return make_stmt(@ast.Label(label, body), s.join(body.span))
    }
    IntConst(label) if self.peek_kind(1) == Colon => {
      let s = self.current_span()
      ignore(self.bump())
      self.expect_kind(Colon, ":")
      let body = self.parse_statement()
      return make_stmt(@ast.Label(label, body), s.join(body.span))
    }
    _ => ()
  }

  if self.current().kind() is Semicolon || self.is_stmt_end() {
    let s = self.current_span()
    return make_stmt(@ast.Empty, s)
  }

  let left = self.parse_expr()
  if self.consume_kind(Assign) {
    let right = self.parse_expr()
    return make_stmt(@ast.Assign(left, right), left.span.join(right.span))
  }
  match left.node {
    @ast.Call(callee, args) => make_stmt(@ast.Call(callee, args), left.span)
    @ast.Name(_) => make_stmt(@ast.Call(left, []), left.span)
    @ast.Field(_, _) => make_stmt(@ast.Call(left, []), left.span)
    _ => {
      self.error_here("P0005", "expected assignment or procedure call")
      make_stmt(@ast.Error, left.span)
    }
  }
}

///|
fn Parser::parse_block(self : Parser) -> @ast.Spanned[@ast.Block] {
  let decls = self.parse_declarations()
  let begin_span = if self.consume_kw(KwBegin, "BEGIN") {
    self.tokens[self.pos - 1].span
  } else {
    self.error_here("P0011", "expected begin")
    self.current_span()
  }

  let stmts = []
  while !self.at_eof() && self.current().kind() != KwEnd {
    stmts.push(self.parse_statement())
    self.consume_kind(Semicolon) |> ignore
  }
  self.expect_kw(KwEnd, "END")
  let end_span = self.tokens[self.pos - 1].span
  make_block(decls, stmts, begin_span.join(end_span))
}

///|
fn Parser::parse_uses_clause(
  self : Parser,
) -> Array[@ast.Spanned[@ast.UsesItem]] {
  let uses = []
  if self.consume_kind(KwUses) || self.consume_word("USES") {
    let mut keep = true
    while keep && !self.at_eof() {
      let span = self.current_span()
      let name = self.take_qualified_name()
      uses.push(@ast.Spanned::new(@ast.UsesItem::{ unit_name: name }, span))
      if self.consume_kind(Comma) {
        keep = true
      } else {
        keep = false
      }
    }
    self.expect_kind(Semicolon, ";")
  }
  uses
}

///|
fn Parser::parse_statements_until_word(
  self : Parser,
  stop1 : String,
  stop2 : String,
) -> Array[@ast.Spanned[@ast.Stmt]] {
  let out = []
  while !self.at_eof() &&
        !self.is_word(stop1) &&
        !self.is_word(stop2) &&
        self.current().kind() != KwEnd {
    out.push(self.parse_statement())
    self.consume_kind(Semicolon) |> ignore
  }
  out
}

///|
fn Parser::parse_program_unit(
  self : Parser,
) -> @ast.Spanned[@ast.CompilationUnit] {
  let start = self.current_span()
  if self.current().kind() is KwProgram {
    self.bump() |> ignore
  } else {
    self.expect_word("PROGRAM")
  }
  let name = self.take_identifier()
  self.expect_kind(Semicolon, ";")
  let uses = self.parse_uses_clause()
  let block = self.parse_block()
  let finalization = if self.consume_word("FINALIZATION") {
    self.parse_statements_until_word("END", "")
  } else {
    []
  }
  if finalization.length() > 0 ||
    self.is_word("END") ||
    self.current().kind() is KwEnd {
    self.expect_kw(KwEnd, "END")
  }
  self.expect_kind(Dot, ".")
  @ast.Spanned::new(
    @ast.CompilationUnit::ProgramUnit({ name, uses, block, finalization }),
    start.join(block.span),
  )
}

///|
fn Parser::parse_unit_module(
  self : Parser,
) -> @ast.Spanned[@ast.CompilationUnit] {
  let start = self.current_span()
  if self.current().kind() is KwUnit {
    self.bump() |> ignore
  } else {
    self.expect_word("UNIT")
  }
  let name = self.take_identifier()
  self.expect_kind(Semicolon, ";")
  self.expect_word("INTERFACE")
  let interface_uses = self.parse_uses_clause()
  let interface_decls = self.parse_declarations()
  self.expect_word("IMPLEMENTATION")
  let implementation_uses = self.parse_uses_clause()

  let impl_decls = self.parse_declarations()
  let implementation_block = if self.is_kind_or_word(KwBegin, "BEGIN") {
    let b = self.parse_block()
    let all_decls = impl_decls
    for d in b.node.decls {
      all_decls.push(d)
    }
    @ast.Spanned::new(
      @ast.Block::{ decls: all_decls, stmts: b.node.stmts },
      b.span,
    )
  } else {
    make_block(impl_decls, [], self.current_span())
  }

  let initialization = if self.consume_word("INITIALIZATION") {
    self.parse_statements_until_word("FINALIZATION", "END")
  } else {
    []
  }
  let finalization = if self.consume_word("FINALIZATION") {
    self.parse_statements_until_word("END", "")
  } else {
    []
  }

  if self.is_word("END") || self.current().kind() is KwEnd {
    self.expect_kw(KwEnd, "END")
  }
  self.expect_kind(Dot, ".")

  @ast.Spanned::new(
    @ast.CompilationUnit::UnitModule({
      name,
      interface_uses,
      interface_decls,
      implementation_uses,
      implementation_block,
      initialization,
      finalization,
    }),
    start.join(implementation_block.span),
  )
}

///|
fn Parser::parse_library_unit(
  self : Parser,
) -> @ast.Spanned[@ast.CompilationUnit] {
  let start = self.current_span()
  self.expect_word("LIBRARY")
  let name = self.take_identifier()
  self.expect_kind(Semicolon, ";")
  let uses = self.parse_uses_clause()
  let block = self.parse_block()
  let finalization = if self.consume_word("FINALIZATION") {
    self.parse_statements_until_word("END", "")
  } else {
    []
  }
  if finalization.length() > 0 ||
    self.is_word("END") ||
    self.current().kind() is KwEnd {
    self.expect_kw(KwEnd, "END")
  }
  self.expect_kind(Dot, ".")
  @ast.Spanned::new(
    @ast.CompilationUnit::LibraryUnit({ name, uses, block, finalization }),
    start.join(block.span),
  )
}

///|
pub fn parse_tokens(
  file_id : Int,
  tokens : Array[@lexer.SpannedToken],
  sink : @diag.DiagSink,
) -> @ast.Spanned[@ast.CompilationUnit] {
  let stable_tokens = if tokens.length() == 0 {
    [@lexer.SpannedToken::new(Eof, @diag.Span::new(file_id, 0, 0))]
  } else {
    tokens
  }
  let p = { tokens: stable_tokens, sink, pos: 0 }
  let cu = if p.is_kind_or_word(KwProgram, "PROGRAM") {
    p.parse_program_unit()
  } else if p.is_kind_or_word(KwUnit, "UNIT") {
    p.parse_unit_module()
  } else if p.is_word("LIBRARY") {
    p.parse_library_unit()
  } else {
    p.error_here("P0020", "expected program, unit, or library")
    p.parse_program_unit()
  }
  p.error_trailing("compilation unit")
  cu
}

///|
pub fn parse_text(
  file_id : Int,
  source : String,
  sink : @diag.DiagSink,
) -> @ast.Spanned[@ast.CompilationUnit] {
  let tokens = @lexer.tokenize(file_id, source, sink)
  parse_tokens(file_id, tokens, sink)
}
