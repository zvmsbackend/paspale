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
fn emit_assign(
  out : AsmData,
  lhs : @ast.Spanned[@ast.Expr],
  rhs : @ast.Spanned[@ast.Expr],
  span : @diag.Span,
) -> Unit {
  match (lhs.node, rhs.node) {
    (Name(dst), Name(src)) if dst == src => {
      out.emit(Tai::new(Instruction, "mov", ["eax", "eax"]).with_span(span))
      out.emit(
        Tai::new(Instruction, "mov", ["[\{dst}]", "eax"]).with_span(span),
      )
    }
    (Name(dst), _) =>
      if int_lit(rhs) is Some(v) {
        out.emit(Tai::new(Instruction, "mov", ["[\{dst}]", v]).with_span(span))
      } else if lower_expr_to_eax(out, rhs, span) {
        out.emit(
          Tai::new(Instruction, "mov", ["[\{dst}]", "eax"]).with_span(span),
        )
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
fn emit_stmt(
  out : AsmData,
  s : @ast.Spanned[@ast.Stmt],
  break_labels : Array[String],
  continue_labels : Array[String],
) -> Unit {
  match s.node {
    Compound(stmts) =>
      for st in stmts {
        emit_stmt(out, st, break_labels, continue_labels)
      }
    Assign(lhs, rhs) => emit_assign(out, lhs, rhs, s.span)
    Call(callee, _) =>
      match callee.node {
        Name(name) =>
          out.emit(Tai::new(Instruction, "call", [name]).with_span(s.span))
        _ =>
          out.emit(
            Tai::new(Comment, "; call \{expr_text(callee)}", []).with_span(
              s.span,
            ),
          )
      }
    If(cond, then_s, else_s) => {
      let then_label = fresh_label(out, ".L_if_then")
      let else_label = fresh_label(out, ".L_if_else")
      let end_label = fresh_label(out, ".L_if_end")
      if lower_cond_jump(out, cond, then_label, else_label, s.span) {
        out.emit(Tai::new(Label, then_label, []).with_span(s.span))
        emit_stmt(out, then_s, break_labels, continue_labels)
        out.emit(Tai::new(Instruction, "jmp", [end_label]).with_span(s.span))
        out.emit(Tai::new(Label, else_label, []).with_span(s.span))
        if else_s is Some(es) {
          emit_stmt(out, es, break_labels, continue_labels)
        }
        out.emit(Tai::new(Label, end_label, []).with_span(s.span))
      } else {
        out.emit(Tai::new(Comment, "; if", []).with_span(s.span))
        emit_stmt(out, then_s, break_labels, continue_labels)
        if else_s is Some(es) {
          emit_stmt(out, es, break_labels, continue_labels)
        }
      }
    }
    While(cond, body) => {
      let loop_label = fresh_label(out, ".L_while_loop")
      let body_label = fresh_label(out, ".L_while_body")
      let end_label = fresh_label(out, ".L_while_end")
      out.emit(Tai::new(Label, loop_label, []).with_span(s.span))
      break_labels.push(end_label)
      continue_labels.push(loop_label)
      if lower_cond_jump(out, cond, body_label, end_label, s.span) {
        out.emit(Tai::new(Label, body_label, []).with_span(s.span))
        emit_stmt(out, body, break_labels, continue_labels)
        out.emit(Tai::new(Instruction, "jmp", [loop_label]).with_span(s.span))
        out.emit(Tai::new(Label, end_label, []).with_span(s.span))
      } else {
        out.emit(Tai::new(Comment, "; while", []).with_span(s.span))
        emit_stmt(out, body, break_labels, continue_labels)
      }
      continue_labels.pop() |> ignore
      break_labels.pop() |> ignore
    }
    RepeatUntil(stmts, cond) => {
      let loop_label = fresh_label(out, ".L_repeat_loop")
      let end_label = fresh_label(out, ".L_repeat_end")
      out.emit(Tai::new(Label, loop_label, []).with_span(s.span))
      break_labels.push(end_label)
      continue_labels.push(loop_label)
      for st in stmts {
        emit_stmt(out, st, break_labels, continue_labels)
      }
      if lower_cond_jump(out, cond, end_label, loop_label, s.span) {
        out.emit(Tai::new(Label, end_label, []).with_span(s.span))
      } else {
        out.emit(Tai::new(Comment, "; repeat until", []).with_span(s.span))
      }
      continue_labels.pop() |> ignore
      break_labels.pop() |> ignore
    }
    For(counter, start, dir, bound, body) => {
      let check_label = fresh_label(out, ".L_for_check")
      let body_label = fresh_label(out, ".L_for_body")
      let continue_label = fresh_label(out, ".L_for_continue")
      let end_label = fresh_label(out, ".L_for_end")
      emit_assign(out, counter, start, s.span)
      out.emit(Tai::new(Label, check_label, []).with_span(s.span))
      break_labels.push(end_label)
      continue_labels.push(continue_label)
      if lower_cond_jump(
          out,
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
        out.emit(Tai::new(Label, body_label, []).with_span(s.span))
        emit_stmt(out, body, break_labels, continue_labels)
        out.emit(Tai::new(Label, continue_label, []).with_span(s.span))
        if counter.node is Name(counter_name) {
          out.emit(
            Tai::new(Instruction, "mov", ["eax", "[\{counter_name}]"]).with_span(
              s.span,
            ),
          )
          out.emit(
            Tai::new(
              Instruction,
              match dir {
                To => "add"
                Downto => "sub"
              },
              ["eax", "1"],
            ).with_span(s.span),
          )
          out.emit(
            Tai::new(Instruction, "mov", ["[\{counter_name}]", "eax"]).with_span(
              s.span,
            ),
          )
        }
        out.emit(Tai::new(Instruction, "jmp", [check_label]).with_span(s.span))
        out.emit(Tai::new(Label, end_label, []).with_span(s.span))
      } else {
        out.emit(Tai::new(Comment, "; for", []).with_span(s.span))
        emit_stmt(out, body, break_labels, continue_labels)
      }
      continue_labels.pop() |> ignore
      break_labels.pop() |> ignore
    }
    Case(_, branches, else_s) => {
      out.emit(Tai::new(Comment, "; case", []).with_span(s.span))
      for b in branches {
        emit_stmt(out, b.node.body, break_labels, continue_labels)
      }
      if else_s is Some(es) {
        emit_stmt(out, es, break_labels, continue_labels)
      }
    }
    With(_, body) => emit_stmt(out, body, break_labels, continue_labels)
    TryExcept(try_s, handlers, else_s) => {
      emit_stmt(out, try_s, break_labels, continue_labels)
      for h in handlers {
        emit_stmt(out, h.node.body, break_labels, continue_labels)
      }
      if else_s is Some(es) {
        emit_stmt(out, es, break_labels, continue_labels)
      }
    }
    TryFinally(try_s, finally_s) => {
      emit_stmt(out, try_s, break_labels, continue_labels)
      emit_stmt(out, finally_s, break_labels, continue_labels)
    }
    Raise(Some(e)) =>
      out.emit(
        Tai::new(Comment, "; unsupported raise \{expr_text(e)}", []).with_span(
          s.span,
        ),
      )
    Raise(None) =>
      out.emit(Tai::new(Comment, "; unsupported raise", []).with_span(s.span))
    Label(name, body) => {
      out.emit(Tai::new(Label, name, []).with_span(s.span))
      emit_stmt(out, body, break_labels, continue_labels)
    }
    Goto(name) =>
      out.emit(Tai::new(Instruction, "jmp", [name]).with_span(s.span))
    Asm(text) => out.emit(Tai::new(Comment, text, []).with_span(s.span))
    Break =>
      if current_loop_label(break_labels) is Some(label) {
        out.emit(Tai::new(Instruction, "jmp", [label]).with_span(s.span))
      } else {
        out.emit(
          Tai::new(Comment, "; break outside loop", []).with_span(s.span),
        )
      }
    Continue =>
      if current_loop_label(continue_labels) is Some(label) {
        out.emit(Tai::new(Instruction, "jmp", [label]).with_span(s.span))
      } else {
        out.emit(
          Tai::new(Comment, "; continue outside loop", []).with_span(s.span),
        )
      }
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
fn emit_global_decl(out : AsmData, d : @ast.Spanned[@ast.Decl]) -> Unit {
  match d.node {
    VarDecl(names, _, _) =>
      for n in names {
        out.switch(Globals)
        out.emit(Tai::new(Symbol, n, []).with_span(d.span))
        out.switch(Procedures)
      }
    _ => ()
  }
}

///|
fn emit_block(out : AsmData, block : @ast.Spanned[@ast.Block]) -> Unit {
  let break_labels = []
  let continue_labels = []
  for d in block.node.decls {
    emit_global_decl(out, d)
  }
  for s in block.node.stmts {
    emit_stmt(out, s, break_labels, continue_labels)
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
  let break_labels = []
  let continue_labels = []
  out.switch(Procedures)
  out.emit(Tai::new(Section, ".text", []).with_span(cu.span))
  out.emit(Tai::new(Label, "main", []).with_span(cu.span))

  match cu.node {
    ProgramUnit(p) => {
      emit_block(out, p.block)
      for s in p.finalization {
        emit_stmt(out, s, break_labels, continue_labels)
      }
    }
    UnitModule(u) => {
      emit_block(out, u.implementation_block)
      for s in u.initialization {
        emit_stmt(out, s, break_labels, continue_labels)
      }
      for s in u.finalization {
        emit_stmt(out, s, break_labels, continue_labels)
      }
    }
    LibraryUnit(l) => {
      emit_block(out, l.block)
      for s in l.finalization {
        emit_stmt(out, s, break_labels, continue_labels)
      }
    }
  }

  out.emit(Tai::new(Instruction, "ret", []).with_span(cu.span))

  out
}
