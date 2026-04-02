///|
fn expr_text(e : @ast.Spanned[@ast.Expr]) -> String {
  match e.node {
    Name(name) => name
    Literal(Int(v)) => v
    Literal(Real(v)) => v
    Literal(String(v)) => "'\{v}'"
    Literal(Bool(v)) => if v { "true" } else { "false" }
    Literal(Nil) => "nil"
    Unary(_, rhs) => expr_text(rhs)
    Binary(_, lhs, rhs) => "\{expr_text(lhs)} ? \{expr_text(rhs)}"
    Call(callee, _) => expr_text(callee)
    Index(base, _) => expr_text(base)
    Field(base, field) => "\{expr_text(base)}.\{field}"
    SetLiteral(_) => "set"
    Range(a, b) => "\{expr_text(a)}..\{expr_text(b)}"
    Paren(inner) => expr_text(inner)
    Error => "<error>"
  }
}

///|
fn int_lit(e : @ast.Spanned[@ast.Expr]) -> String? {
  match e.node {
    Literal(Int(v)) => Some(v)
    _ => None
  }
}

///|
fn lower_expr_to_eax(
  out : AsmData,
  e : @ast.Spanned[@ast.Expr],
  span : @diag.Span,
) -> Bool {
  match e.node {
    Literal(Int(v)) => {
      out.emit(Tai::new(Instruction, "mov", ["eax", v]).with_span(span))
      true
    }
    Name(name) => {
      out.emit(
        Tai::new(Instruction, "mov", ["eax", "[\{name}]"]).with_span(span),
      )
      true
    }
    Paren(inner) => lower_expr_to_eax(out, inner, span)
    Unary(Minus, rhs) =>
      if lower_expr_to_eax(out, rhs, span) {
        out.emit(Tai::new(Instruction, "mov", ["ebx", "0"]).with_span(span))
        out.emit(Tai::new(Instruction, "sub", ["ebx", "eax"]).with_span(span))
        out.emit(Tai::new(Instruction, "mov", ["eax", "ebx"]).with_span(span))
        true
      } else {
        false
      }
    Binary(Add, lhs, rhs) =>
      if lower_expr_to_eax(out, lhs, span) {
        out.emit(Tai::new(Instruction, "mov", ["ebx", "eax"]).with_span(span))
        if lower_expr_to_eax(out, rhs, span) {
          out.emit(Tai::new(Instruction, "add", ["ebx", "eax"]).with_span(span))
          out.emit(Tai::new(Instruction, "mov", ["eax", "ebx"]).with_span(span))
          true
        } else {
          false
        }
      } else {
        false
      }
    Binary(Sub, lhs, rhs) =>
      if lower_expr_to_eax(out, lhs, span) {
        out.emit(Tai::new(Instruction, "mov", ["ebx", "eax"]).with_span(span))
        if lower_expr_to_eax(out, rhs, span) {
          out.emit(Tai::new(Instruction, "sub", ["ebx", "eax"]).with_span(span))
          out.emit(Tai::new(Instruction, "mov", ["eax", "ebx"]).with_span(span))
          true
        } else {
          false
        }
      } else {
        false
      }
    _ => false
  }
}

///|
fn fresh_label(out : AsmData, prefix : String) -> String {
  "\{prefix}_\{out.procedures.length()}"
}

///|
fn cond_jcc(op : @ast.BinaryOp) -> String? {
  match op {
    Eq => Some("je")
    Ne => Some("jne")
    Lt => Some("jl")
    Le => Some("jle")
    Gt => Some("jg")
    Ge => Some("jge")
    _ => None
  }
}

///|
fn lower_cond_jump(
  out : AsmData,
  cond : @ast.Spanned[@ast.Expr],
  true_label : String,
  false_label : String,
  span : @diag.Span,
) -> Bool {
  match cond.node {
    Binary(op, lhs, rhs) =>
      if cond_jcc(op) is Some(jcc) {
        if lower_expr_to_eax(out, rhs, span) {
          out.emit(Tai::new(Instruction, "mov", ["ebx", "eax"]).with_span(span))
          if lower_expr_to_eax(out, lhs, span) {
            out.emit(
              Tai::new(Instruction, "cmp", ["eax", "ebx"]).with_span(span),
            )
            out.emit(Tai::new(Instruction, jcc, [true_label]).with_span(span))
            out.emit(
              Tai::new(Instruction, "jmp", [false_label]).with_span(span),
            )
            true
          } else {
            false
          }
        } else {
          false
        }
      } else {
        false
      }
    _ => false
  }
}

///|
fn current_loop_label(stack : Array[String]) -> String? {
  if stack.length() == 0 {
    None
  } else {
    Some(stack[stack.length() - 1])
  }
}

///|
fn has_callable_decl(d : @ast.Spanned[@ast.Decl]) -> Bool {
  match d.node {
    ProcDecl({ body: Some(_), .. }) => true
    FuncDecl({ body: Some(_), .. }) => true
    _ => false
  }
}

///|
priv struct LowerCtx {
  out : AsmData
  break_labels : Array[String]
  continue_labels : Array[String]
}

///|
fn LowerCtx::new(out : AsmData) -> LowerCtx {
  { out, break_labels: [], continue_labels: [] }
}

///|
fn LowerCtx::emit_assign(
  self : LowerCtx,
  lhs : @ast.Spanned[@ast.Expr],
  rhs : @ast.Spanned[@ast.Expr],
  span : @diag.Span,
) -> Unit {
  match (lhs.node, rhs.node) {
    (Name(dst), Name(src)) if dst == src => {
      self.out.emit(
        Tai::new(Instruction, "mov", ["eax", "eax"]).with_span(span),
      )
      self.out.emit(
        Tai::new(Instruction, "mov", ["[\{dst}]", "eax"]).with_span(span),
      )
    }
    (Name(dst), _) =>
      if int_lit(rhs) is Some(v) {
        self.out.emit(
          Tai::new(Instruction, "mov", ["[\{dst}]", v]).with_span(span),
        )
      } else if lower_expr_to_eax(self.out, rhs, span) {
        self.out.emit(
          Tai::new(Instruction, "mov", ["[\{dst}]", "eax"]).with_span(span),
        )
      } else {
        self.out.emit(
          Tai::new(Comment, "; assign \{expr_text(lhs)} := \{expr_text(rhs)}", []).with_span(
            span,
          ),
        )
      }
    _ =>
      self.out.emit(
        Tai::new(Comment, "; assign \{expr_text(lhs)} := \{expr_text(rhs)}", []).with_span(
          span,
        ),
      )
  }
}

///|
fn LowerCtx::emit_if_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
  cond : @ast.Spanned[@ast.Expr],
  then_s : @ast.Spanned[@ast.Stmt],
  else_s : @ast.Spanned[@ast.Stmt]?,
) -> Unit {
  let then_label = fresh_label(self.out, ".L_if_then")
  let else_label = fresh_label(self.out, ".L_if_else")
  let end_label = fresh_label(self.out, ".L_if_end")
  if lower_cond_jump(self.out, cond, then_label, else_label, s.span) {
    self.out.emit(Tai::new(Label, then_label, []).with_span(s.span))
    self.emit_stmt(then_s)
    self.out.emit(Tai::new(Instruction, "jmp", [end_label]).with_span(s.span))
    self.out.emit(Tai::new(Label, else_label, []).with_span(s.span))
    if else_s is Some(es) {
      self.emit_stmt(es)
    }
    self.out.emit(Tai::new(Label, end_label, []).with_span(s.span))
  } else {
    self.out.emit(Tai::new(Comment, "; if", []).with_span(s.span))
    self.emit_stmt(then_s)
    if else_s is Some(es) {
      self.emit_stmt(es)
    }
  }
}

///|
fn LowerCtx::emit_while_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
  cond : @ast.Spanned[@ast.Expr],
  body : @ast.Spanned[@ast.Stmt],
) -> Unit {
  let loop_label = fresh_label(self.out, ".L_while_loop")
  let body_label = fresh_label(self.out, ".L_while_body")
  let end_label = fresh_label(self.out, ".L_while_end")
  self.out.emit(Tai::new(Label, loop_label, []).with_span(s.span))
  self.break_labels.push(end_label)
  self.continue_labels.push(loop_label)
  if lower_cond_jump(self.out, cond, body_label, end_label, s.span) {
    self.out.emit(Tai::new(Label, body_label, []).with_span(s.span))
    self.emit_stmt(body)
    self.out.emit(Tai::new(Instruction, "jmp", [loop_label]).with_span(s.span))
    self.out.emit(Tai::new(Label, end_label, []).with_span(s.span))
  } else {
    self.out.emit(Tai::new(Comment, "; while", []).with_span(s.span))
    self.emit_stmt(body)
  }
  self.continue_labels.pop() |> ignore
  self.break_labels.pop() |> ignore
}

///|
fn LowerCtx::emit_repeat_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
  stmts : Array[@ast.Spanned[@ast.Stmt]],
  cond : @ast.Spanned[@ast.Expr],
) -> Unit {
  let loop_label = fresh_label(self.out, ".L_repeat_loop")
  let end_label = fresh_label(self.out, ".L_repeat_end")
  self.out.emit(Tai::new(Label, loop_label, []).with_span(s.span))
  self.break_labels.push(end_label)
  self.continue_labels.push(loop_label)
  for st in stmts {
    self.emit_stmt(st)
  }
  if lower_cond_jump(self.out, cond, end_label, loop_label, s.span) {
    self.out.emit(Tai::new(Label, end_label, []).with_span(s.span))
  } else {
    self.out.emit(Tai::new(Comment, "; repeat until", []).with_span(s.span))
  }
  self.continue_labels.pop() |> ignore
  self.break_labels.pop() |> ignore
}

///|
fn LowerCtx::emit_for_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
  counter : @ast.Spanned[@ast.Expr],
  start : @ast.Spanned[@ast.Expr],
  dir : @ast.ForDirection,
  bound : @ast.Spanned[@ast.Expr],
  body : @ast.Spanned[@ast.Stmt],
) -> Unit {
  let check_label = fresh_label(self.out, ".L_for_check")
  let body_label = fresh_label(self.out, ".L_for_body")
  let continue_label = fresh_label(self.out, ".L_for_continue")
  let end_label = fresh_label(self.out, ".L_for_end")
  self.emit_assign(counter, start, s.span)
  self.out.emit(Tai::new(Label, check_label, []).with_span(s.span))
  self.break_labels.push(end_label)
  self.continue_labels.push(continue_label)
  if lower_cond_jump(
      self.out,
      @ast.Spanned::new(
        Binary(
          match dir {
            To => Le
            Downto => Ge
          },
          counter,
          bound,
        ),
        s.span,
      ),
      body_label,
      end_label,
      s.span,
    ) {
    self.out.emit(Tai::new(Label, body_label, []).with_span(s.span))
    self.emit_stmt(body)
    self.out.emit(Tai::new(Label, continue_label, []).with_span(s.span))
    if counter.node is Name(counter_name) {
      self.out.emit(
        Tai::new(Instruction, "mov", ["eax", "[\{counter_name}]"]).with_span(
          s.span,
        ),
      )
      self.out.emit(
        Tai::new(
          Instruction,
          match dir {
            To => "add"
            Downto => "sub"
          },
          ["eax", "1"],
        ).with_span(s.span),
      )
      self.out.emit(
        Tai::new(Instruction, "mov", ["[\{counter_name}]", "eax"]).with_span(
          s.span,
        ),
      )
    }
    self.out.emit(Tai::new(Instruction, "jmp", [check_label]).with_span(s.span))
    self.out.emit(Tai::new(Label, end_label, []).with_span(s.span))
  } else {
    self.out.emit(Tai::new(Comment, "; for", []).with_span(s.span))
    self.emit_stmt(body)
  }
  self.continue_labels.pop() |> ignore
  self.break_labels.pop() |> ignore
}

///|
fn LowerCtx::emit_case_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
  selector : @ast.Spanned[@ast.Expr],
  branches : Array[@ast.Spanned[@ast.CaseBranch]],
  else_s : @ast.Spanned[@ast.Stmt]?,
) -> Unit {
  let end_label = fresh_label(self.out, ".L_case_end")
  let else_label = fresh_label(self.out, ".L_case_else")
  if lower_expr_to_eax(self.out, selector, s.span) {
    self.out.emit(
      Tai::new(Instruction, "mov", ["ebx", "eax"]).with_span(s.span),
    )
    let branch_labels = []
    for _ in branches {
      branch_labels.push(fresh_label(self.out, ".L_case_branch"))
    }
    let mut idx = 0
    for b in branches {
      let target = branch_labels[idx]
      idx = idx + 1
      for l in b.node.labels {
        match l.node {
          Literal(Int(v)) => {
            self.out.emit(
              Tai::new(Instruction, "cmp", ["ebx", v]).with_span(l.span),
            )
            self.out.emit(
              Tai::new(Instruction, "je", [target]).with_span(l.span),
            )
          }
          Range(lo, hi) =>
            if int_lit(lo) is Some(lo_v) && int_lit(hi) is Some(hi_v) {
              let next_label = fresh_label(self.out, ".L_case_next")
              self.out.emit(
                Tai::new(Instruction, "cmp", ["ebx", lo_v]).with_span(l.span),
              )
              self.out.emit(
                Tai::new(Instruction, "jl", [next_label]).with_span(l.span),
              )
              self.out.emit(
                Tai::new(Instruction, "cmp", ["ebx", hi_v]).with_span(l.span),
              )
              self.out.emit(
                Tai::new(Instruction, "jle", [target]).with_span(l.span),
              )
              self.out.emit(Tai::new(Label, next_label, []).with_span(l.span))
            } else {
              self.out.emit(
                Tai::new(Comment, "; unsupported case range label", []).with_span(
                  l.span,
                ),
              )
            }
          _ =>
            self.out.emit(
              Tai::new(Comment, "; unsupported case label", []).with_span(
                l.span,
              ),
            )
        }
      }
    }
    self.out.emit(Tai::new(Instruction, "jmp", [else_label]).with_span(s.span))
    let mut idx = 0
    for b in branches {
      self.out.emit(Tai::new(Label, branch_labels[idx], []).with_span(b.span))
      idx = idx + 1
      self.emit_stmt(b.node.body)
      self.out.emit(Tai::new(Instruction, "jmp", [end_label]).with_span(b.span))
    }
    self.out.emit(Tai::new(Label, else_label, []).with_span(s.span))
    if else_s is Some(es) {
      self.emit_stmt(es)
    }
    self.out.emit(Tai::new(Label, end_label, []).with_span(s.span))
  } else {
    self.out.emit(Tai::new(Comment, "; case", []).with_span(s.span))
    for b in branches {
      self.emit_stmt(b.node.body)
    }
    if else_s is Some(es) {
      self.emit_stmt(es)
    }
  }
}

///|
fn LowerCtx::emit_break_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
) -> Unit {
  if current_loop_label(self.break_labels) is Some(label) {
    self.out.emit(Tai::new(Instruction, "jmp", [label]).with_span(s.span))
  } else {
    self.out.emit(
      Tai::new(Comment, "; break outside loop", []).with_span(s.span),
    )
  }
}

///|
fn LowerCtx::emit_continue_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
) -> Unit {
  if current_loop_label(self.continue_labels) is Some(label) {
    self.out.emit(Tai::new(Instruction, "jmp", [label]).with_span(s.span))
  } else {
    self.out.emit(
      Tai::new(Comment, "; continue outside loop", []).with_span(s.span),
    )
  }
}

///|
fn LowerCtx::emit_raise_stmt(
  self : LowerCtx,
  s : @ast.Spanned[@ast.Stmt],
  payload : @ast.Spanned[@ast.Expr]?,
) -> Unit {
  match payload {
    Some(e) =>
      self.out.emit(
        Tai::new(Comment, "; unsupported raise \{expr_text(e)}", []).with_span(
          s.span,
        ),
      )
    None =>
      self.out.emit(
        Tai::new(Comment, "; unsupported raise", []).with_span(s.span),
      )
  }
}

///|
fn LowerCtx::emit_stmt(self : LowerCtx, s : @ast.Spanned[@ast.Stmt]) -> Unit {
  match s.node {
    Compound(stmts) =>
      for st in stmts {
        self.emit_stmt(st)
      }
    Assign(lhs, rhs) => self.emit_assign(lhs, rhs, s.span)
    Call(callee, _) =>
      match callee.node {
        Name(name) =>
          self.out.emit(Tai::new(Instruction, "call", [name]).with_span(s.span))
        _ =>
          self.out.emit(
            Tai::new(Comment, "; call \{expr_text(callee)}", []).with_span(
              s.span,
            ),
          )
      }
    If(cond, then_s, else_s) => self.emit_if_stmt(s, cond, then_s, else_s)
    While(cond, body) => self.emit_while_stmt(s, cond, body)
    RepeatUntil(stmts, cond) => self.emit_repeat_stmt(s, stmts, cond)
    For(counter, start, dir, bound, body) =>
      self.emit_for_stmt(s, counter, start, dir, bound, body)
    Case(selector, branches, else_s) =>
      self.emit_case_stmt(s, selector, branches, else_s)
    With(_, body) => self.emit_stmt(body)
    TryExcept(try_s, handlers, else_s) => {
      self.emit_stmt(try_s)
      for h in handlers {
        self.emit_stmt(h.node.body)
      }
      if else_s is Some(es) {
        self.emit_stmt(es)
      }
    }
    TryFinally(try_s, finally_s) => {
      self.emit_stmt(try_s)
      self.emit_stmt(finally_s)
    }
    Raise(payload) => self.emit_raise_stmt(s, payload)
    Label(name, body) => {
      self.out.emit(Tai::new(Label, name, []).with_span(s.span))
      self.emit_stmt(body)
    }
    Goto(name) =>
      self.out.emit(Tai::new(Instruction, "jmp", [name]).with_span(s.span))
    Asm(text) => self.out.emit(Tai::new(Comment, text, []).with_span(s.span))
    Break => self.emit_break_stmt(s)
    Continue => self.emit_continue_stmt(s)
    Exit(Some(e)) => {
      if int_lit(e) is Some(v) {
        self.out.emit(
          Tai::new(Instruction, "mov", ["eax", v]).with_span(s.span),
        )
      }
      self.out.emit(Tai::new(Instruction, "ret", []).with_span(s.span))
    }
    Exit(None) =>
      self.out.emit(Tai::new(Instruction, "ret", []).with_span(s.span))
    Empty | Error => ()
  }
}

///|
fn LowerCtx::emit_global_decl(
  self : LowerCtx,
  d : @ast.Spanned[@ast.Decl],
) -> Unit {
  match d.node {
    VarDecl(names, _, _) =>
      for n in names {
        self.out.switch(Globals)
        self.out.emit(Tai::new(Symbol, n, []).with_span(d.span))
        self.out.switch(Procedures)
      }
    ProcDecl(proc_decl) =>
      if proc_decl.body is Some(body) {
        self.out.switch(Procedures)
        self.out.emit(Tai::new(Label, proc_decl.name, []).with_span(d.span))
        let nested = LowerCtx::new(self.out)
        nested.emit_block(body)
        self.out.emit(Tai::new(Instruction, "ret", []).with_span(d.span))
      }
    FuncDecl(func_decl) =>
      if func_decl.body is Some(body) {
        self.out.switch(Procedures)
        self.out.emit(Tai::new(Label, func_decl.name, []).with_span(d.span))
        let nested = LowerCtx::new(self.out)
        nested.emit_block(body)
        self.out.emit(Tai::new(Instruction, "ret", []).with_span(d.span))
      }
    _ => ()
  }
}

///|
fn LowerCtx::emit_block(
  self : LowerCtx,
  block : @ast.Spanned[@ast.Block],
) -> Unit {
  let mut has_callable = false
  for d in block.node.decls {
    if has_callable_decl(d) {
      has_callable = true
    }
  }
  let body_label = fresh_label(self.out, ".L_main_body")
  if has_callable {
    self.out.emit(
      Tai::new(Instruction, "jmp", [body_label]).with_span(block.span),
    )
  }
  for d in block.node.decls {
    self.emit_global_decl(d)
  }
  if has_callable {
    self.out.emit(Tai::new(Label, body_label, []).with_span(block.span))
  }
  for s in block.node.stmts {
    self.emit_stmt(s)
  }
}

///|
pub fn lower_compilation_unit(
  cu : @ast.Spanned[@ast.CompilationUnit],
) -> AsmData {
  let name = match cu.node {
    ProgramUnit(p) => p.name
    UnitModule(u) => u.name
    LibraryUnit(l) => l.name
  }
  let out = AsmData::new(name)
  let ctx = LowerCtx::new(out)
  out.switch(Procedures)
  out.emit(Tai::new(Section, ".text", []).with_span(cu.span))
  out.emit(Tai::new(Label, "main", []).with_span(cu.span))

  match cu.node {
    ProgramUnit(p) => {
      ctx.emit_block(p.block)
      for s in p.finalization {
        ctx.emit_stmt(s)
      }
    }
    UnitModule(u) => {
      ctx.emit_block(u.implementation_block)
      for s in u.initialization {
        ctx.emit_stmt(s)
      }
      for s in u.finalization {
        ctx.emit_stmt(s)
      }
    }
    LibraryUnit(l) => {
      ctx.emit_block(l.block)
      for s in l.finalization {
        ctx.emit_stmt(s)
      }
    }
  }

  out.emit(Tai::new(Instruction, "ret", []).with_span(cu.span))

  out
}
