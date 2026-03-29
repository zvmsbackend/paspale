///|
pub(all) enum TokenKind {
  Eof
  Identifier
  IntConst
  RealConst
  StringConst
  KwProgram
  KwUnit
  KwUses
  KwVar
  KwConst
  KwType
  KwBegin
  KwEnd
  KwProcedure
  KwFunction
  KwIf
  KwThen
  KwElse
  KwWhile
  KwDo
  KwFor
  KwTo
  KwDownto
  KwRepeat
  KwUntil
  KwCase
  KwOf
  Plus
  Minus
  Star
  Slash
  Equal
  Lt
  Gt
  Lte
  Gte
  NotEqual
  Assign
  Colon
  Semicolon
  Comma
  Dot
  DotDot
  DotDotDot
  LParen
  RParen
  LBracket
  RBracket
  Caret
  At
} derive(Show, Eq)

///|
pub(all) enum Token {
  Eof
  Identifier(String)
  IntConst(String)
  RealConst(String)
  StringConst(String)
  KwProgram
  KwUnit
  KwUses
  KwVar
  KwConst
  KwType
  KwBegin
  KwEnd
  KwProcedure
  KwFunction
  KwIf
  KwThen
  KwElse
  KwWhile
  KwDo
  KwFor
  KwTo
  KwDownto
  KwRepeat
  KwUntil
  KwCase
  KwOf
  Plus
  Minus
  Star
  Slash
  Equal
  Lt
  Gt
  Lte
  Gte
  NotEqual
  Assign
  Colon
  Semicolon
  Comma
  Dot
  DotDot
  DotDotDot
  LParen
  RParen
  LBracket
  RBracket
  Caret
  At
} derive(Show, Eq)

///|
pub fn Token::kind(self : Token) -> TokenKind {
  match self {
    Eof => Eof
    Identifier(_) => Identifier
    IntConst(_) => IntConst
    RealConst(_) => RealConst
    StringConst(_) => StringConst
    KwProgram => KwProgram
    KwUnit => KwUnit
    KwUses => KwUses
    KwVar => KwVar
    KwConst => KwConst
    KwType => KwType
    KwBegin => KwBegin
    KwEnd => KwEnd
    KwProcedure => KwProcedure
    KwFunction => KwFunction
    KwIf => KwIf
    KwThen => KwThen
    KwElse => KwElse
    KwWhile => KwWhile
    KwDo => KwDo
    KwFor => KwFor
    KwTo => KwTo
    KwDownto => KwDownto
    KwRepeat => KwRepeat
    KwUntil => KwUntil
    KwCase => KwCase
    KwOf => KwOf
    Plus => Plus
    Minus => Minus
    Star => Star
    Slash => Slash
    Equal => Equal
    Lt => Lt
    Gt => Gt
    Lte => Lte
    Gte => Gte
    NotEqual => NotEqual
    Assign => Assign
    Colon => Colon
    Semicolon => Semicolon
    Comma => Comma
    Dot => Dot
    DotDot => DotDot
    DotDotDot => DotDotDot
    LParen => LParen
    RParen => RParen
    LBracket => LBracket
    RBracket => RBracket
    Caret => Caret
    At => At
  }
}

///|
pub struct SpannedToken {
  token : Token
  span : @diag.Span
}

///|
pub fn SpannedToken::new(token : Token, span : @diag.Span) -> SpannedToken {
  { token, span }
}

///|
pub fn SpannedToken::kind(self : SpannedToken) -> TokenKind {
  self.token.kind()
}
