///|
pub struct Spanned[T] {
  node : T
  span : @diag.Span
} derive(Show, Eq)

///|
pub fn[T] Spanned::new(node : T, span : @diag.Span) -> Spanned[T] {
  { node, span }
}

///|
pub(all) enum Literal {
  Int(String)
  Real(String)
  String(String)
  Bool(Bool)
  Nil
} derive(Show, Eq)

///|
pub(all) enum UnaryOp {
  Plus
  Minus
  Not
  Deref
  Addr
} derive(Show, Eq)

///|
pub(all) enum BinaryOp {
  Add
  Sub
  Mul
  RealDiv
  IntDiv
  Mod
  And
  Or
  Xor
  Shl
  Shr
  In
  Is
  As
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
} derive(Show, Eq)

///|
pub(all) enum ForDirection {
  To
  Downto
} derive(Show, Eq)

///|
pub(all) enum ParamMode {
  Value
  Var
  Const
  Out
  ConstRef
} derive(Show, Eq)

///|
pub(all) enum CallingConv {
  Default
  Pascal
  Cdecl
  Stdcall
  Register
} derive(Show, Eq)

///|
pub(all) struct UsesItem {
  unit_name : String
} derive(Show, Eq)

///|
pub(all) struct FieldDecl {
  names : Array[String]
  ty : Spanned[TypeExpr]
} derive(Show, Eq)

///|
pub(all) struct ParamDecl {
  names : Array[String]
  ty : Spanned[TypeExpr]
  mode : ParamMode
} derive(Show, Eq)

///|
pub(all) enum TypeExpr {
  Named(String)
  Pointer(Spanned[TypeExpr])
  Array(Spanned[Expr], Spanned[TypeExpr])
  Record(Array[Spanned[FieldDecl]])
  Enum(Array[String])
  Subrange(Spanned[Expr], Spanned[Expr])
  Set(Spanned[TypeExpr])
  Error
} derive(Show, Eq)

///|
pub(all) enum Expr {
  Name(String)
  Literal(Literal)
  Unary(UnaryOp, Spanned[Expr])
  Binary(BinaryOp, Spanned[Expr], Spanned[Expr])
  Call(Spanned[Expr], Array[Spanned[Expr]])
  Index(Spanned[Expr], Spanned[Expr])
  Field(Spanned[Expr], String)
  SetLiteral(Array[Spanned[Expr]])
  Range(Spanned[Expr], Spanned[Expr])
  Paren(Spanned[Expr])
  Error
} derive(Show, Eq)

///|
pub(all) enum ProcDirective {
  Forward
  External(String?)
  CallingConv(CallingConv)
  Inline
  Assembler
  Overload
  Virtual
  Abstract
  Override
  Message(String)
} derive(Show, Eq)

///|
pub(all) struct ProcDecl {
  name : String
  params : Array[Spanned[ParamDecl]]
  directives : Array[Spanned[ProcDirective]]
  body : Spanned[Block]?
} derive(Show, Eq)

///|
pub(all) struct FuncDecl {
  name : String
  params : Array[Spanned[ParamDecl]]
  result_ty : Spanned[TypeExpr]
  directives : Array[Spanned[ProcDirective]]
  body : Spanned[Block]?
} derive(Show, Eq)

///|
pub(all) enum Decl {
  ConstDecl(String, Spanned[Expr])
  TypeDecl(String, Spanned[TypeExpr])
  VarDecl(Array[String], Spanned[TypeExpr], Spanned[Expr]?)
  ProcDecl(ProcDecl)
  FuncDecl(FuncDecl)
  LabelDecl(Array[String])
  Error
} derive(Show, Eq)

///|
pub(all) struct CaseBranch {
  labels : Array[Spanned[Expr]]
  body : Spanned[Stmt]
} derive(Show, Eq)

///|
pub(all) struct ExceptHandler {
  name : String?
  ty : Spanned[TypeExpr]?
  body : Spanned[Stmt]
} derive(Show, Eq)

///|
pub(all) enum Stmt {
  Empty
  Compound(Array[Spanned[Stmt]])
  Assign(Spanned[Expr], Spanned[Expr])
  Call(Spanned[Expr], Array[Spanned[Expr]])
  If(Spanned[Expr], Spanned[Stmt], Spanned[Stmt]?)
  Case(Spanned[Expr], Array[Spanned[CaseBranch]], Spanned[Stmt]?)
  While(Spanned[Expr], Spanned[Stmt])
  RepeatUntil(Array[Spanned[Stmt]], Spanned[Expr])
  For(Spanned[Expr], Spanned[Expr], ForDirection, Spanned[Expr], Spanned[Stmt])
  With(Array[Spanned[Expr]], Spanned[Stmt])
  TryExcept(Spanned[Stmt], Array[Spanned[ExceptHandler]], Spanned[Stmt]?)
  TryFinally(Spanned[Stmt], Spanned[Stmt])
  Raise(Spanned[Expr]?)
  Label(String, Spanned[Stmt])
  Goto(String)
  Asm(String)
  Break
  Continue
  Exit(Spanned[Expr]?)
  Error
} derive(Show, Eq)

///|
pub(all) struct Block {
  decls : Array[Spanned[Decl]]
  stmts : Array[Spanned[Stmt]]
} derive(Show, Eq)

///|
pub(all) struct Program {
  name : String
  block : Spanned[Block]
} derive(Show, Eq)

///|
pub(all) struct ProgramUnit {
  name : String
  uses : Array[Spanned[UsesItem]]
  block : Spanned[Block]
  finalization : Array[Spanned[Stmt]]
} derive(Show, Eq)

///|
pub(all) struct UnitModule {
  name : String
  interface_uses : Array[Spanned[UsesItem]]
  interface_decls : Array[Spanned[Decl]]
  implementation_uses : Array[Spanned[UsesItem]]
  implementation_block : Spanned[Block]
  initialization : Array[Spanned[Stmt]]
  finalization : Array[Spanned[Stmt]]
} derive(Show, Eq)

///|
pub(all) struct LibraryUnit {
  name : String
  uses : Array[Spanned[UsesItem]]
  block : Spanned[Block]
  finalization : Array[Spanned[Stmt]]
} derive(Show, Eq)

///|
pub(all) enum CompilationUnit {
  ProgramUnit(ProgramUnit)
  UnitModule(UnitModule)
  LibraryUnit(LibraryUnit)
} derive(Show, Eq)
