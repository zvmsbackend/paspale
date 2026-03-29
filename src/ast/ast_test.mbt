///|
test "construct simple untyped program ast" {
  let s1 = @diag.Span::new(0, 1, 2)
  let s2 = @diag.Span::new(0, 3, 4)
  let s3 = @diag.Span::new(0, 1, 4)

  let lhs = @ast.Spanned::new(@ast.Name("x"), s1)
  let rhs = @ast.Spanned::new(
    @ast.Binary(
      @ast.Add,
      @ast.Spanned::new(@ast.Literal(@ast.Int("1")), s1),
      @ast.Spanned::new(@ast.Literal(@ast.Int("2")), s2),
    ),
    s3,
  )
  let stmt = @ast.Spanned::new(@ast.Assign(lhs, rhs), s3)
  let block = @ast.Spanned::new(@ast.Block::{ decls: [], stmts: [stmt] }, s3)
  let prog : @ast.Program = { name: "Demo", block }

  assert_eq(prog.name, "Demo")
  assert_eq(prog.block.node.stmts.length(), 1)
}

///|
test "error nodes can be represented in ast" {
  let s = @diag.Span::new(1, 10, 10)
  let err_expr = @ast.Spanned::new(@ast.Expr::Error, s)
  let err_stmt = @ast.Spanned::new(@ast.Stmt::Error, s)
  let block = @ast.Block::{
    decls: [@ast.Spanned::new(@ast.Decl::Error, s)],
    stmts: [@ast.Spanned::new(@ast.Assign(err_expr, err_expr), s), err_stmt],
  }

  assert_eq(block.decls.length(), 1)
  assert_eq(block.stmts.length(), 2)
}

///|
test "p0 module-level structures are representable" {
  let s = @diag.Span::new(0, 0, 0)
  let uses = [@ast.Spanned::new(@ast.UsesItem::{ unit_name: "SysUtils" }, s)]
  let main_block = @ast.Spanned::new(@ast.Block::{ decls: [], stmts: [] }, s)
  let unit = @ast.ProgramUnit::{
    name: "Demo",
    uses,
    block: main_block,
    finalization: [@ast.Spanned::new(@ast.Exit(None), s)],
  }
  let cu = @ast.CompilationUnit::ProgramUnit(unit)

  match cu {
    ProgramUnit(p) => {
      assert_eq(p.name, "Demo")
      assert_eq(p.uses.length(), 1)
    }
    _ => fail("expected program unit")
  }
}

///|
test "p0 statements and directives are representable" {
  let s = @diag.Span::new(0, 0, 0)
  let loop_var = @ast.Spanned::new(@ast.Name("i"), s)
  let from_ = @ast.Spanned::new(@ast.Literal(@ast.Int("0")), s)
  let to_ = @ast.Spanned::new(@ast.Literal(@ast.Int("10")), s)
  let body = @ast.Spanned::new(@ast.Continue, s)
  let for_stmt = @ast.For(loop_var, from_, @ast.To, to_, body)

  let proc_decl = @ast.ProcDecl::{
    name: "P",
    params: [],
    directives: [@ast.Spanned::new(@ast.Forward, s)],
    body: None,
  }

  assert_eq(for_stmt, @ast.For(loop_var, from_, @ast.To, to_, body))
  assert_eq(proc_decl.directives.length(), 1)
}
