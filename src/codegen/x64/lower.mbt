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
fn lower_int_expr(
  out : AsmData,
  e : @ast.Spanned[@ast.Expr],
  span : @diag.Span,
) -> Bool {
  match e.node {
    Literal(Int(v)) => {
      out.emit(Tai::new(Instruction, "mov", ["eax", v]).with_span(span))
      true
    }
    Unary(Minus, rhs) =>
      if int_lit(rhs) is Some(v) {
        out.emit(Tai::new(Instruction, "mov", ["eax", "0"]).with_span(span))
        out.emit(Tai::new(Instruction, "sub", ["eax", v]).with_span(span))
        true
      } else {
        false
      }
    Binary(Add, lhs, rhs) =>
      if int_lit(lhs) is Some(a) && int_lit(rhs) is Some(b) {
        out.emit(Tai::new(Instruction, "mov", ["eax", a]).with_span(span))
        out.emit(Tai::new(Instruction, "add", ["eax", b]).with_span(span))
        true
      } else {
        false
      }
    Binary(Sub, lhs, rhs) =>
      if int_lit(lhs) is Some(a) && int_lit(rhs) is Some(b) {
        out.emit(Tai::new(Instruction, "mov", ["eax", a]).with_span(span))
        out.emit(Tai::new(Instruction, "sub", ["eax", b]).with_span(span))
        true
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
      if cond_jcc(op) is Some(jcc) &&
        int_lit(lhs) is Some(a) &&
        int_lit(rhs) is Some(b) {
        out.emit(Tai::new(Instruction, "mov", ["eax", a]).with_span(span))
        out.emit(Tai::new(Instruction, "cmp", ["eax", b]).with_span(span))
        out.emit(Tai::new(Instruction, jcc, [true_label]).with_span(span))
        out.emit(Tai::new(Instruction, "jmp", [false_label]).with_span(span))
        true
      } else {
        false
      }
    _ => false
  }
}

///|
fn emit_assign(
  out : AsmData,
  lhs : @ast.Spanned[@ast.Expr],
  rhs : @ast.Spanned[@ast.Expr],
  span : @diag.Span,
) -> Unit {
  match (lhs.node, rhs.node) {
    (Name(dst), Name(src)) if dst == src =>
      out.emit(Tai::new(Instruction, "mov", ["eax", "eax"]).with_span(span))
    (Name(_), _) =>
      if lower_int_expr(out, rhs, span) {
        ()
      } else {
        out.emit(
          Tai::new(Comment, "; assign \{expr_text(lhs)} := \{expr_text(rhs)}", []).with_span(
            span,
          ),
        )
      }
    _ =>
      out.emit(
        Tai::new(Comment, "; assign \{expr_text(lhs)} := \{expr_text(rhs)}", []).with_span(
          span,
        ),
      )
  }
}

///|
fn emit_stmt(out : AsmData, s : @ast.Spanned[@ast.Stmt]) -> Unit {
  match s.node {
    Compound(stmts) =>
      for st in stmts {
        emit_stmt(out, st)
      }
    Assign(lhs, rhs) => emit_assign(out, lhs, rhs, s.span)
    Call(callee, _) =>
      out.emit(
        Tai::new(Comment, "; call \{expr_text(callee)}", []).with_span(s.span),
      )
    If(cond, then_s, else_s) => {
      let then_label = fresh_label(out, ".L_if_then")
      let else_label = fresh_label(out, ".L_if_else")
      let end_label = fresh_label(out, ".L_if_end")
      if lower_cond_jump(out, cond, then_label, else_label, s.span) {
        out.emit(Tai::new(Label, then_label, []).with_span(s.span))
        emit_stmt(out, then_s)
        out.emit(Tai::new(Instruction, "jmp", [end_label]).with_span(s.span))
        out.emit(Tai::new(Label, else_label, []).with_span(s.span))
        if else_s is Some(es) {
          emit_stmt(out, es)
        }
        out.emit(Tai::new(Label, end_label, []).with_span(s.span))
      } else {
        out.emit(Tai::new(Comment, "; if", []).with_span(s.span))
        emit_stmt(out, then_s)
        if else_s is Some(es) {
          emit_stmt(out, es)
        }
      }
    }
    While(cond, body) => {
      let loop_label = fresh_label(out, ".L_while_loop")
      let body_label = fresh_label(out, ".L_while_body")
      let end_label = fresh_label(out, ".L_while_end")
      out.emit(Tai::new(Label, loop_label, []).with_span(s.span))
      if lower_cond_jump(out, cond, body_label, end_label, s.span) {
        out.emit(Tai::new(Label, body_label, []).with_span(s.span))
        emit_stmt(out, body)
        out.emit(Tai::new(Instruction, "jmp", [loop_label]).with_span(s.span))
        out.emit(Tai::new(Label, end_label, []).with_span(s.span))
      } else {
        out.emit(Tai::new(Comment, "; while", []).with_span(s.span))
        emit_stmt(out, body)
      }
    }
    RepeatUntil(stmts, _) =>
      for st in stmts {
        emit_stmt(out, st)
      }
    For(_, _, _, _, body) => {
      out.emit(Tai::new(Comment, "; for", []).with_span(s.span))
      emit_stmt(out, body)
    }
    Case(_, branches, else_s) => {
      out.emit(Tai::new(Comment, "; case", []).with_span(s.span))
      for b in branches {
        emit_stmt(out, b.node.body)
      }
      if else_s is Some(es) {
        emit_stmt(out, es)
      }
    }
    With(_, body) => emit_stmt(out, body)
    TryExcept(try_s, handlers, else_s) => {
      emit_stmt(out, try_s)
      for h in handlers {
        emit_stmt(out, h.node.body)
      }
      if else_s is Some(es) {
        emit_stmt(out, es)
      }
    }
    TryFinally(try_s, finally_s) => {
      emit_stmt(out, try_s)
      emit_stmt(out, finally_s)
    }
    Raise(Some(e)) =>
      out.emit(Tai::new(Instruction, "raise", [expr_text(e)]).with_span(s.span))
    Raise(None) =>
      out.emit(Tai::new(Instruction, "raise", []).with_span(s.span))
    Label(name, body) => {
      out.emit(Tai::new(Label, name, []).with_span(s.span))
      emit_stmt(out, body)
    }
    Goto(name) =>
      out.emit(Tai::new(Instruction, "jmp", [name]).with_span(s.span))
    Asm(text) => out.emit(Tai::new(Comment, text, []).with_span(s.span))
    Break => out.emit(Tai::new(Instruction, "break", []).with_span(s.span))
    Continue =>
      out.emit(Tai::new(Instruction, "continue", []).with_span(s.span))
    Exit(Some(e)) => {
      if int_lit(e) is Some(v) {
        out.emit(Tai::new(Instruction, "mov", ["eax", v]).with_span(s.span))
      }
      out.emit(Tai::new(Instruction, "ret", []).with_span(s.span))
    }
    Exit(None) => out.emit(Tai::new(Instruction, "ret", []).with_span(s.span))
    Empty | Error => ()
  }
}

///|
fn emit_block(out : AsmData, block : @ast.Spanned[@ast.Block]) -> Unit {
  for s in block.node.stmts {
    emit_stmt(out, s)
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
  out.switch(Procedures)
  out.emit(Tai::new(Section, ".text", []).with_span(cu.span))
  out.emit(Tai::new(Label, "main", []).with_span(cu.span))

  match cu.node {
    ProgramUnit(p) => {
      emit_block(out, p.block)
      for s in p.finalization {
        emit_stmt(out, s)
      }
    }
    UnitModule(u) => {
      emit_block(out, u.implementation_block)
      for s in u.initialization {
        emit_stmt(out, s)
      }
      for s in u.finalization {
        emit_stmt(out, s)
      }
    }
    LibraryUnit(l) => {
      emit_block(out, l.block)
      for s in l.finalization {
        emit_stmt(out, s)
      }
    }
  }

  out.emit(Tai::new(Instruction, "ret", []).with_span(cu.span))

  out
}
