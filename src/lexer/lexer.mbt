///|
fn classify_identifier(ident : StringView) -> Token {
  match @common.ascii_upper(ident) {
    "PROGRAM" => KwProgram
    "UNIT" => KwUnit
    "USES" => KwUses
    "VAR" => KwVar
    "CONST" => KwConst
    "TYPE" => KwType
    "BEGIN" => KwBegin
    "END" => KwEnd
    "PROCEDURE" => KwProcedure
    "FUNCTION" => KwFunction
    "IF" => KwIf
    "THEN" => KwThen
    "ELSE" => KwElse
    "WHILE" => KwWhile
    "DO" => KwDo
    "FOR" => KwFor
    "TO" => KwTo
    "DOWNTO" => KwDownto
    "REPEAT" => KwRepeat
    "UNTIL" => KwUntil
    "CASE" => KwCase
    "OF" => KwOf
    _ => Identifier(ident.to_string())
  }
}

///|
fn read_brace_comment(rest : StringView) -> (String, Bool) {
  let out = StringBuilder::new()
  for c in rest {
    out.write_char(c)
    if c == '}' {
      return (out.to_string(), true)
    }
  }
  (out.to_string(), false)
}

///|
fn read_old_comment(rest : StringView) -> (String, Bool) {
  let out = StringBuilder::new()
  for c in rest; prev_star = false {
    out.write_char(c)
    if prev_star && c == ')' {
      return (out.to_string(), true)
    }
    continue c == '*'
  }
  (out.to_string(), false)
}

///|
fn read_string_literal(rest : StringView) -> (Int, Bool) {
  if rest.char_length() == 0 {
    return (0, false)
  }
  for i = 1; i < rest.char_length(); {
    let c = match rest.get_char(i) {
      Some(c) => c
      None => break
    }
    if c == '\n' || c == '\r' {
      return (i, false)
    }
    if c == '\'' {
      if i + 1 < rest.char_length() && rest.get_char(i + 1) is Some('\'') {
        continue i + 2
      }
      return (i + 1, true)
    }
    continue i + 1
  }
  (rest.char_length(), false)
}

///|
fn decode_pascal_string(quoted : StringView) -> String {
  let out = StringBuilder::new()
  for i = 1; i + 1 < quoted.char_length(); {
    let c = match quoted.get_char(i) {
      Some(c) => c
      None => break
    }
    if c == '\'' &&
      i + 1 < quoted.char_length() - 1 &&
      quoted.get_char(i + 1) is Some('\'') {
      out.write_char('\'')
      continue i + 2
    }
    out.write_char(c)
    continue i + 1
  }
  out.to_string()
}

///|
fn push_token(
  tokens : Array[SpannedToken],
  token : Token,
  file_id : Int,
  start : Int,
  end_ : Int,
) -> Unit {
  tokens.push({ token, span: @diag.Span::new(file_id, start, end_) })
}

///|
fn push_lexer_error(
  sink : @diag.DiagSink,
  file_id : Int,
  start : Int,
  end_ : Int,
  code : String,
  message : String,
) -> Unit {
  let span = @diag.Span::new(file_id, start, end_)
  sink.push(
    @diag.Diagnostic::new(@diag.Error, code, message).with_label(
      @diag.Label::primary(span, "here"),
    ),
  )
}

///|
fn classify_punctation(sym : StringView) -> Token {
  match sym {
    "..." => DotDotDot
    ".." => DotDot
    ":=" => Assign
    "<=" => Lte
    ">=" => Gte
    "<>" => NotEqual
    "+" => Plus
    "-" => Minus
    "*" => Star
    "/" => Slash
    "=" => Equal
    "<" => Lt
    ">" => Gt
    ":" => Colon
    ";" => Semicolon
    "," => Comma
    "." => Dot
    "(" => LParen
    ")" => RParen
    "[" => LBracket
    "]" => RBracket
    "^" => Caret
    "@" => At
    _ => Eof
  }
}

///|
pub fn tokenize(
  file_id : Int,
  source : String,
  sink : @diag.DiagSink,
) -> Array[SpannedToken] {
  let tokens = []

  for rest = source[:], offset = 0; rest != ""; {
    match rest {
      ['{', ..] => {
        let (consumed, closed) = read_brace_comment(rest)
        let len = consumed.char_length()
        if !closed {
          push_lexer_error(
            sink,
            file_id,
            offset,
            offset + len,
            "L0002",
            "unterminated { ... } comment",
          )
        }
        continue rest[len:], offset + len
      }
      ['(', '*', ..] => {
        let (consumed, closed) = read_old_comment(rest)
        let len = consumed.char_length()
        if !closed {
          push_lexer_error(
            sink,
            file_id,
            offset,
            offset + len,
            "L0003",
            "unterminated (* ... *) comment",
          )
        }
        continue rest[len:], offset + len
      }
      ['\'', ..] => {
        let (len, closed) = read_string_literal(rest)
        if !closed {
          push_lexer_error(
            sink,
            file_id,
            offset,
            offset + len,
            "L0004",
            "unterminated string literal",
          )
          continue rest[len:], offset + len
        }
        push_token(
          tokens,
          StringConst(decode_pascal_string(rest[:len])),
          file_id,
          offset,
          offset + len,
        )
        continue rest[len:], offset + len
      }
      _ => ()
    }

    lexmatch rest with longest {
      ("[ \t\r\n]+" as ws, r) => {
        let len = ws.char_length()
        continue r, offset + len
      }
      ("//[^\n\r]*" as cmt, r) => {
        let len = cmt.char_length()
        continue r, offset + len
      }
      (
        "\.\.\.|\.\.|:=|:=|<=|>=|<>|\+|-|\*|/|=|<|>|:|;|,|\.|\(|\)|\[|\]|\^|@" as m,
        r
      ) => {
        let len = m.char_length()
        push_token(
          tokens,
          classify_punctation(m),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      ("[_[:alpha:]][_[:alnum:]]*" as ident, r) => {
        let len = ident.char_length()
        push_token(
          tokens,
          classify_identifier(ident),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      ("\$[[:xdigit:]]+" as n, r) => {
        let len = n.char_length()
        push_token(
          tokens,
          IntConst(n.to_string()),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      ("%[01]+" as n, r) => {
        let len = n.char_length()
        push_token(
          tokens,
          IntConst(n.to_string()),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      ("&[0-7]+" as n, r) => {
        let len = n.char_length()
        push_token(
          tokens,
          IntConst(n.to_string()),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      ("[[:digit:]]+\.[[:digit:]]+" as n, r) => {
        let len = n.char_length()
        push_token(
          tokens,
          RealConst(n.to_string()),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      ("[[:digit:]]+[eE][[:digit:]]+" as n, r) => {
        let len = n.char_length()
        push_token(
          tokens,
          RealConst(n.to_string()),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      ("[[:digit:]]+" as n, r) => {
        let len = n.char_length()
        push_token(
          tokens,
          IntConst(n.to_string()),
          file_id,
          offset,
          offset + len,
        )
        continue r, offset + len
      }
      _ => ()
    }

    let bad = match rest.get_char(0) {
      Some(c) => "\{c}"
      None => ""
    }
    push_lexer_error(
      sink,
      file_id,
      offset,
      offset + 1,
      "L0001",
      "illegal character '\{bad}'",
    )
    continue rest[1:], offset + 1
  } nobreak {
    push_token(tokens, Eof, file_id, offset, offset)
    tokens
  }
}
