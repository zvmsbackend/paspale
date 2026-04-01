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
fn emit_stmt(out : AsmData, s : @ast.Spanned[@ast.Stmt]) -> Unit {
  match s.node {
    Compound(stmts) =>
      for st in stmts {
        emit_stmt(out, st)
      }
    Assign(lhs, rhs) =>
      out.emit(
        Tai::new(Instruction, "mov", [expr_text(lhs), expr_text(rhs)]).with_span(
          s.span,
        ),
      )
    Call(callee, _) =>
      out.emit(
        Tai::new(Instruction, "call", [expr_text(callee)]).with_span(s.span),
      )
    If(_, then_s, else_s) => {
      out.emit(Tai::new(Comment, "; if", []).with_span(s.span))
      emit_stmt(out, then_s)
      if else_s is Some(es) {
        emit_stmt(out, es)
      }
    }
    While(_, body) => {
      out.emit(Tai::new(Comment, "; while", []).with_span(s.span))
      emit_stmt(out, body)
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
    Exit(Some(e)) =>
      out.emit(Tai::new(Instruction, "retv", [expr_text(e)]).with_span(s.span))
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

  out
}
