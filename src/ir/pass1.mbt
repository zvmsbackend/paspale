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
fn fold_expr(
  e : @ast.Spanned[@ast.Expr],
  report : FirstPassReport,
) -> @ast.Spanned[@ast.Expr] {
  let rebuilt : @ast.Spanned[@ast.Expr] = match e.node {
    Unary(op, rhs) =>
      @ast.Spanned::new(Unary(op, fold_expr(rhs, report)), e.span)
    Binary(op, lhs, rhs) =>
      @ast.Spanned::new(
        Binary(op, fold_expr(lhs, report), fold_expr(rhs, report)),
        e.span,
      )
    Call(callee, args) =>
      @ast.Spanned::new(
        Call(
          fold_expr(callee, report),
          args.map(a => fold_expr(a, report)),
        ),
        e.span,
      )
    Index(base, idx) =>
      @ast.Spanned::new(
        Index(fold_expr(base, report), fold_expr(idx, report)),
        e.span,
      )
    Field(base, name) =>
      @ast.Spanned::new(Field(fold_expr(base, report), name), e.span)
    SetLiteral(items) =>
      @ast.Spanned::new(
        SetLiteral(items.map(it => fold_expr(it, report))),
        e.span,
      )
    Range(a, b) =>
      @ast.Spanned::new(
        Range(fold_expr(a, report), fold_expr(b, report)),
        e.span,
      )
    Paren(inner) =>
      @ast.Spanned::new(Paren(fold_expr(inner, report)), e.span)
    _ => e
  }

  match rebuilt.node {
    Unary(Plus | Minus, _) =>
      if eval_int_expr(rebuilt) is Some(v) {
        report.folded_unary += 1
        @ast.Spanned::new(Literal(Int(v.to_string())), rebuilt.span)
      } else {
        rebuilt
      }
    Binary(_, _, _) =>
      if eval_int_expr(rebuilt) is Some(v) {
        report.folded_binary += 1
        @ast.Spanned::new(Literal(Int(v.to_string())), rebuilt.span)
      } else {
        rebuilt
      }
    _ => rebuilt
  }
}

///|
fn fold_stmt(
  s : @ast.Spanned[@ast.Stmt],
  report : FirstPassReport,
) -> @ast.Spanned[@ast.Stmt] {
  let node : @ast.Stmt = match s.node {
    Compound(stmts) => Compound(stmts.map(st => fold_stmt(st, report)))
    Assign(lhs, rhs) =>
      Assign(fold_expr(lhs, report), fold_expr(rhs, report))
    Call(callee, args) =>
      Call(fold_expr(callee, report), args.map(a => fold_expr(a, report)))
    If(cond, then_s, else_s) =>
      If(
        fold_expr(cond, report),
        fold_stmt(then_s, report),
        else_s.map(es => fold_stmt(es, report)),
      )
    Case(cond, branches, else_s) =>
      Case(
        fold_expr(cond, report),
        branches.map(b => {
          @ast.Spanned::new(
            {
              labels: b.node.labels.map(lbl => fold_expr(lbl, report)),
              body: fold_stmt(b.node.body, report),
            },
            b.span,
          )
        }),
        else_s.map(es => fold_stmt(es, report)),
      )
    While(cond, body) =>
      While(fold_expr(cond, report), fold_stmt(body, report))
    RepeatUntil(stmts, cond) =>
      RepeatUntil(
        stmts.map(st => fold_stmt(st, report)),
        fold_expr(cond, report),
      )
    For(loop_var, from_, dir, to_, body) =>
      For(
        fold_expr(loop_var, report),
        fold_expr(from_, report),
        dir,
        fold_expr(to_, report),
        fold_stmt(body, report),
      )
    With(items, body) =>
      With(items.map(it => fold_expr(it, report)), fold_stmt(body, report))
    TryExcept(try_s, handlers, else_s) =>
      TryExcept(
        fold_stmt(try_s, report),
        handlers.map(h => {
          @ast.Spanned::new(
            {
              name: h.node.name,
              ty: h.node.ty,
              body: fold_stmt(h.node.body, report),
            },
            h.span,
          )
        }),
        else_s.map(es => fold_stmt(es, report)),
      )
    TryFinally(try_s, finally_s) =>
      TryFinally(fold_stmt(try_s, report), fold_stmt(finally_s, report))
    Raise(Some(e)) => Raise(Some(fold_expr(e, report)))
    Raise(None) => Raise(None)
    Label(name, body) => Label(name, fold_stmt(body, report))
    Exit(Some(e)) => Exit(Some(fold_expr(e, report)))
    Exit(None) => Exit(None)
    _ => s.node
  }
  @ast.Spanned::new(node, s.span)
}

///|
fn fold_decl(
  d : @ast.Spanned[@ast.Decl],
  report : FirstPassReport,
) -> @ast.Spanned[@ast.Decl] {
  let node : @ast.Decl = match d.node {
    ConstDecl(name, expr) => ConstDecl(name, fold_expr(expr, report))
    VarDecl(names, ty, Some(init)) =>
      VarDecl(names, ty, Some(fold_expr(init, report)))
    VarDecl(names, ty, None) => VarDecl(names, ty, None)
    ProcDecl(pd) =>
      ProcDecl({ ..pd, body: pd.body.map(b => fold_block(b, report)) })
    FuncDecl(fd) =>
      FuncDecl({ ..fd, body: fd.body.map(b => fold_block(b, report)) })
    _ => d.node
  }
  @ast.Spanned::new(node, d.span)
}

///|
fn fold_block(
  b : @ast.Spanned[@ast.Block],
  report : FirstPassReport,
) -> @ast.Spanned[@ast.Block] {
  @ast.Spanned::new(
    {
      decls: b.node.decls.map(d => fold_decl(d, report)),
      stmts: b.node.stmts.map(s => fold_stmt(s, report)),
    },
    b.span,
  )
}

///|
pub fn run_first_pass_pipeline(
  unit : @ast.Spanned[@ast.CompilationUnit],
) -> FirstPassResult {
  let report = FirstPassReport::new()
  let folded_unit : @ast.Spanned[@ast.CompilationUnit] = match unit.node {
    ProgramUnit(p) =>
      @ast.Spanned::new(
        ProgramUnit({
          ..p,
          block: fold_block(p.block, report),
          finalization: p.finalization.map(s => fold_stmt(s, report)),
        }),
        unit.span,
      )
    UnitModule(u) =>
      @ast.Spanned::new(
        UnitModule({
          ..u,
          interface_decls: u.interface_decls.map(d => fold_decl(d, report)),
          implementation_block: fold_block(u.implementation_block, report),
          initialization: u.initialization.map(s => fold_stmt(s, report)),
          finalization: u.finalization.map(s => fold_stmt(s, report)),
        }),
        unit.span,
      )
    LibraryUnit(l) =>
      @ast.Spanned::new(
        LibraryUnit({
          ..l,
          block: fold_block(l.block, report),
          finalization: l.finalization.map(s => fold_stmt(s, report)),
        }),
        unit.span,
      )
  }
  { unit: folded_unit, report }
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
  run_first_pass_pipeline(unit).report
}
