///|
fn parse_int_lit(v : String) -> Int? {
  (try? @string.parse_int(v)).to_option()
}

///|
fn eval_int_expr(e : @ast.Spanned[@ast.Expr]) -> Int? {
  match e.node {
    Literal(Int(v)) => parse_int_lit(v)
    Unary(Plus, rhs) => eval_int_expr(rhs)
    Unary(Minus, rhs) => eval_int_expr(rhs).map(v => -v)
    Binary(Add, lhs, rhs) =>
      match (eval_int_expr(lhs), eval_int_expr(rhs)) {
        (Some(a), Some(b)) => Some(a + b)
        _ => None
      }
    Binary(Sub, lhs, rhs) =>
      match (eval_int_expr(lhs), eval_int_expr(rhs)) {
        (Some(a), Some(b)) => Some(a - b)
        _ => None
      }
    Binary(Mul, lhs, rhs) =>
      match (eval_int_expr(lhs), eval_int_expr(rhs)) {
        (Some(a), Some(b)) => Some(a * b)
        _ => None
      }
    Binary(IntDiv, lhs, rhs) =>
      match (eval_int_expr(lhs), eval_int_expr(rhs)) {
        (Some(_), Some(0)) => None
        (Some(a), Some(b)) => Some(a / b)
        _ => None
      }
    Binary(Mod, lhs, rhs) =>
      match (eval_int_expr(lhs), eval_int_expr(rhs)) {
        (Some(_), Some(0)) => None
        (Some(a), Some(b)) => Some(a % b)
        _ => None
      }
    Binary(Shl, lhs, rhs) =>
      match (eval_int_expr(lhs), eval_int_expr(rhs)) {
        (Some(a), Some(b)) => Some(a << b)
        _ => None
      }
    Binary(Shr, lhs, rhs) =>
      match (eval_int_expr(lhs), eval_int_expr(rhs)) {
        (Some(a), Some(b)) => Some(a >> b)
        _ => None
      }
    Paren(inner) => eval_int_expr(inner)
    _ => None
  }
}

///|
fn visit_expr(e : @ast.Spanned[@ast.Expr], report : FirstPassReport) -> Unit {
  match e.node {
    Unary(Plus | Minus, rhs) => {
      visit_expr(rhs, report)
      if eval_int_expr(e) is Some(_) {
        report.folded_unary += 1
      }
    }
    Unary(_, rhs) => visit_expr(rhs, report)
    Binary(_, lhs, rhs) => {
      visit_expr(lhs, report)
      visit_expr(rhs, report)
      if eval_int_expr(e) is Some(_) {
        report.folded_binary += 1
      }
    }
    Call(callee, args) => {
      visit_expr(callee, report)
      for a in args {
        visit_expr(a, report)
      }
    }
    Index(base, idx) => {
      visit_expr(base, report)
      visit_expr(idx, report)
    }
    Field(base, _) => visit_expr(base, report)
    SetLiteral(items) =>
      for it in items {
        visit_expr(it, report)
      }
    Range(a, b) => {
      visit_expr(a, report)
      visit_expr(b, report)
    }
    Paren(inner) => visit_expr(inner, report)
    _ => ()
  }
}

///|
fn visit_stmt(s : @ast.Spanned[@ast.Stmt], report : FirstPassReport) -> Unit {
  match s.node {
    Compound(stmts) =>
      for st in stmts {
        visit_stmt(st, report)
      }
    Assign(lhs, rhs) => {
      visit_expr(lhs, report)
      visit_expr(rhs, report)
    }
    Call(callee, args) => {
      visit_expr(callee, report)
      for a in args {
        visit_expr(a, report)
      }
    }
    If(cond, then_s, else_s) => {
      visit_expr(cond, report)
      visit_stmt(then_s, report)
      if else_s is Some(es) {
        visit_stmt(es, report)
      }
    }
    Case(cond, branches, else_s) => {
      visit_expr(cond, report)
      for b in branches {
        for lbl in b.node.labels {
          visit_expr(lbl, report)
        }
        visit_stmt(b.node.body, report)
      }
      if else_s is Some(es) {
        visit_stmt(es, report)
      }
    }
    While(cond, body) => {
      visit_expr(cond, report)
      visit_stmt(body, report)
    }
    RepeatUntil(stmts, cond) => {
      for st in stmts {
        visit_stmt(st, report)
      }
      visit_expr(cond, report)
    }
    For(loop_var, from_, _, to_, body) => {
      visit_expr(loop_var, report)
      visit_expr(from_, report)
      visit_expr(to_, report)
      visit_stmt(body, report)
    }
    With(items, body) => {
      for it in items {
        visit_expr(it, report)
      }
      visit_stmt(body, report)
    }
    TryExcept(try_s, handlers, else_s) => {
      visit_stmt(try_s, report)
      for h in handlers {
        visit_stmt(h.node.body, report)
      }
      if else_s is Some(es) {
        visit_stmt(es, report)
      }
    }
    TryFinally(try_s, finally_s) => {
      visit_stmt(try_s, report)
      visit_stmt(finally_s, report)
    }
    Raise(Some(e)) => visit_expr(e, report)
    Raise(None) => ()
    Label(_, body) => visit_stmt(body, report)
    Exit(Some(e)) => visit_expr(e, report)
    Exit(None) => ()
    _ => ()
  }
}

///|
fn visit_decl(d : @ast.Spanned[@ast.Decl], report : FirstPassReport) -> Unit {
  match d.node {
    ConstDecl(_, expr) => visit_expr(expr, report)
    VarDecl(_, _, Some(init)) => visit_expr(init, report)
    VarDecl(_, _, None) => ()
    ProcDecl({ body: Some(b), .. }) => visit_block(b, report)
    FuncDecl({ body: Some(b), .. }) => visit_block(b, report)
    _ => ()
  }
}

///|
fn visit_block(b : @ast.Spanned[@ast.Block], report : FirstPassReport) -> Unit {
  for d in b.node.decls {
    visit_decl(d, report)
  }
  for s in b.node.stmts {
    visit_stmt(s, report)
  }
}

///|
pub fn run_first_pass(
  unit : @ast.Spanned[@ast.CompilationUnit],
) -> FirstPassReport {
  let report = FirstPassReport::new()
  match unit.node {
    ProgramUnit(p) => {
      visit_block(p.block, report)
      for s in p.finalization {
        visit_stmt(s, report)
      }
    }
    UnitModule(u) => {
      for d in u.interface_decls {
        visit_decl(d, report)
      }
      visit_block(u.implementation_block, report)
      for s in u.initialization {
        visit_stmt(s, report)
      }
      for s in u.finalization {
        visit_stmt(s, report)
      }
    }
    LibraryUnit(l) => {
      visit_block(l.block, report)
      for s in l.finalization {
        visit_stmt(s, report)
      }
    }
  }
  report
}
