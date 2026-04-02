///|
fn expr_text(e : @ast.Spanned[@ast.Expr]) -> String {
  match e.node {
    Name(name) => name
    Literal(Int(v)) => v
    Literal(Real(v)) => v
    Literal(String(v)) => "'\{v}'"
    Literal(Bool(true)) => "true"
    Literal(Bool(false)) => "false"
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
  if e.node is Literal(Int(v)) {
    Some(v)
  } else {
    None
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
fn current_loop_label(stack : Array[String]) -> String? {
  stack.last()
}

///|
fn has_callable_decl(d : @ast.Spanned[@ast.Decl]) -> Bool {
  d.node is (ProcDecl({ body: Some(_), .. }) | FuncDecl({ body: Some(_), .. }))
}

///|
fn collect_local_offsets(block : @ast.Spanned[@ast.Block]) -> Map[String, Int] {
  let offsets = {}
  let mut next = 8
  for d in block.node.decls {
    match d.node {
      VarDecl(names, _, _) =>
        for name in names {
          if !offsets.contains(name) {
            offsets.set(name, next)
            next = next + 8
          }
        }
      _ => ()
    }
  }
  offsets
}

///|
fn collect_param_offsets(
  params : Array[@ast.Spanned[@ast.ParamDecl]],
) -> Map[String, Int] {
  let names = flatten_param_names(params)
  let offsets = {}
  let mut next = 16
  for i in int_arg_regs.length()..<names.length() {
    let name = names[i]
    if !offsets.contains(name) {
      offsets.set(name, next)
      next = next + 8
    }
  }
  offsets
}

///|
fn flatten_param_names(
  params : Array[@ast.Spanned[@ast.ParamDecl]],
) -> Array[String] {
  params.iter().flat_map(p => p.node.names.iter()).collect()
}

///|
let int_arg_regs : Array[String] = ["edi", "esi", "edx", "ecx", "r8d", "r9d"]

///|
let callee_saved_regs : Array[String] = ["rbx", "r12", "r13", "r14", "r15"]

///|
fn local_stack_size(offsets : Map[String, Int]) -> Int {
  offsets.length() * 8
}

///|
priv struct LowerCtx {
  out : AsmData
  break_labels : Array[String]
  continue_labels : Array[String]
  mut next_vreg : Int
  in_callable : Bool
  exit_label : String?
  return_slot_offset : Int?
  local_offsets : Map[String, Int]
  param_offsets : Map[String, Int]
}

///|
fn LowerCtx::new(out : AsmData) -> LowerCtx {
  {
    out,
    break_labels: [],
    continue_labels: [],
    next_vreg: 0,
    in_callable: false,
    exit_label: None,
    return_slot_offset: None,
    local_offsets: {},
    param_offsets: {},
  }
}

///|
fn LowerCtx::for_callable(
  out : AsmData,
  exit_label : String,
  return_slot_offset : Int?,
  local_offsets : Map[String, Int],
  param_offsets : Map[String, Int],
) -> LowerCtx {
  {
    out,
    break_labels: [],
    continue_labels: [],
    next_vreg: 0,
    in_callable: true,
    exit_label: Some(exit_label),
    return_slot_offset,
    local_offsets,
    param_offsets,
  }
}

///|
fn LowerCtx::fresh_vreg(self : LowerCtx) -> String {
  let name = "v\{self.next_vreg}"
  self.next_vreg = self.next_vreg + 1
  name
}

///|
fn LowerCtx::var_addr(self : LowerCtx, name : String) -> String {
  match self.local_offsets.get(name) {
    Some(ofs) => "[rbp-\{ofs}]"
    None =>
      match self.param_offsets.get(name) {
        Some(ofs) => "[rbp+\{ofs}]"
        None => "[\{name}]"
      }
  }
}

///|
fn LowerCtx::emit_named_call(
  self : LowerCtx,
  name : String,
  args : Array[@ast.Spanned[@ast.Expr]],
  span : @diag.Span,
) -> Bool {
  let arg_regs = int_arg_regs
  let arg_tmps = []
  for arg in args {
    if self.lower_expr_to_eax(arg, arg.span) {
      let arg_reg = self.fresh_vreg()
      self.out.emit(
        Tai::new(Instruction, "mov", [arg_reg, "eax"]).with_span(arg.span),
      )
      arg_tmps.push(arg_reg)
    } else {
      return false
    }
  }

  let reg_count = @cmp.minimum(arg_tmps.length(), arg_regs.length())

  let mut pushed = 0
  for i in reg_count..<arg_tmps.length() {
    let idx = arg_tmps.length() - 1 - (i - reg_count)
    self.out.emit(
      Tai::new(Instruction, "push", [arg_tmps[idx]]).with_span(span),
    )
    pushed = pushed + 1
  }

  for i in 0..<reg_count {
    self.out.emit(
      Tai::new(Instruction, "mov", [arg_regs[i], arg_tmps[i]]).with_span(span),
    )
  }

  self.out.emit(Tai::new(Instruction, "call", [name]).with_span(span))
  if pushed > 0 {
    self.out.emit(
      Tai::new(Instruction, "add", ["rsp", (pushed * 8).to_string()]).with_span(
        span,
      ),
    )
  }
  true
}

///|
fn LowerCtx::emit_binary_to_eax(
  self : LowerCtx,
  span : @diag.Span,
  lhs : @ast.Spanned[@ast.Expr],
  rhs : @ast.Spanned[@ast.Expr],
  op : String,
) -> Bool {
  guard self.lower_expr_to_eax(lhs, span) else { return false }
  let tmp = self.fresh_vreg()
  self.out.emit(Tai::new(Instruction, "mov", [tmp, "eax"]).with_span(span))
  if self.lower_expr_to_eax(rhs, span) {
    self.out.emit(Tai::new(Instruction, op, [tmp, "eax"]).with_span(span))
    self.out.emit(Tai::new(Instruction, "mov", ["eax", tmp]).with_span(span))
    true
  } else {
    false
  }
}

///|
fn LowerCtx::lower_expr_to_eax(
  self : LowerCtx,
  e : @ast.Spanned[@ast.Expr],
  span : @diag.Span,
) -> Bool {
  match e.node {
    Literal(Int(v)) => {
      let tmp = self.fresh_vreg()
      self.out
      ..emit(Tai::new(Instruction, "mov", [tmp, v]).with_span(span))
      .emit(Tai::new(Instruction, "mov", ["eax", tmp]).with_span(span))
      true
    }
    Name(name) => {
      let tmp = self.fresh_vreg()
      self.out
      ..emit(
        Tai::new(Instruction, "mov", [tmp, self.var_addr(name)]).with_span(span),
      )
      .emit(Tai::new(Instruction, "mov", ["eax", tmp]).with_span(span))
      true
    }
    Paren(inner) => self.lower_expr_to_eax(inner, span)
    Unary(Minus, rhs) =>
      if self.lower_expr_to_eax(rhs, span) {
        let tmp = self.fresh_vreg()
        self.out
        ..emit(Tai::new(Instruction, "mov", [tmp, "0"]).with_span(span))
        ..emit(Tai::new(Instruction, "sub", [tmp, "eax"]).with_span(span))
        .emit(Tai::new(Instruction, "mov", ["eax", tmp]).with_span(span))
        true
      } else {
        false
      }
    Binary(op, lhs, rhs) =>
      match op {
        Add => self.emit_binary_to_eax(span, lhs, rhs, "add")
        Sub => self.emit_binary_to_eax(span, lhs, rhs, "sub")
        _ => false
      }
    Call(callee, args) =>
      match callee.node {
        Name(name) => self.emit_named_call(name, args, span)
        _ => false
      }
    _ => false
  }
}

///|
fn LowerCtx::lower_cond_jump(
  self : LowerCtx,
  cond : @ast.Spanned[@ast.Expr],
  true_label : String,
  false_label : String,
  span : @diag.Span,
) -> Bool {
  guard cond.node is Binary(op, lhs, rhs) else { return false }
  guard cond_jcc(op) is Some(jcc) else { return false }
  guard self.lower_expr_to_eax(rhs, span) else { return false }
  let tmp = self.fresh_vreg()
  self.out.emit(Tai::new(Instruction, "mov", [tmp, "eax"]).with_span(span))
  if self.lower_expr_to_eax(lhs, span) {
    self.out
    ..emit(Tai::new(Instruction, "cmp", ["eax", tmp]).with_span(span))
    ..emit(Tai::new(Instruction, jcc, [true_label]).with_span(span))
    .emit(Tai::new(Instruction, "jmp", [false_label]).with_span(span))
    true
  } else {
    false
  }
}

///|
fn LowerCtx::emit_assign(
  self : LowerCtx,
  lhs : @ast.Spanned[@ast.Expr],
  rhs : @ast.Spanned[@ast.Expr],
  span : @diag.Span,
) -> Unit {
  match (lhs.node, rhs.node) {
    (Name(dst), Name(src)) if dst == src => ()
    (Name(dst), _) =>
      if int_lit(rhs) is Some(v) {
        let tmp = self.fresh_vreg()
        self.out
        ..emit(Tai::new(Instruction, "mov", [tmp, v]).with_span(span))
        .emit(
          Tai::new(Instruction, "mov", [self.var_addr(dst), tmp]).with_span(
            span,
          ),
        )
      } else if self.lower_expr_to_eax(rhs, span) {
        let tmp = self.fresh_vreg()
        self.out
        ..emit(Tai::new(Instruction, "mov", [tmp, "eax"]).with_span(span))
        .emit(
          Tai::new(Instruction, "mov", [self.var_addr(dst), tmp]).with_span(
            span,
          ),
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
  if self.lower_cond_jump(cond, then_label, else_label, s.span) {
    self.out.emit(Tai::new(Label, then_label, []).with_span(s.span))
    self.emit_stmt(then_s)
    self.out
    ..emit(Tai::new(Instruction, "jmp", [end_label]).with_span(s.span))
    .emit(Tai::new(Label, else_label, []).with_span(s.span))
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
  if self.lower_cond_jump(cond, body_label, end_label, s.span) {
    self.out.emit(Tai::new(Label, body_label, []).with_span(s.span))
    self.emit_stmt(body)
    self.out
    ..emit(Tai::new(Instruction, "jmp", [loop_label]).with_span(s.span))
    .emit(Tai::new(Label, end_label, []).with_span(s.span))
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
  if self.lower_cond_jump(cond, end_label, loop_label, s.span) {
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
  if self.lower_cond_jump(
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
      let step_tmp = self.fresh_vreg()
      self.out.emit(
        Tai::new(Instruction, "mov", [step_tmp, "[\{counter_name}]"]).with_span(
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
          [step_tmp, "1"],
        ).with_span(s.span),
      )
      self.out.emit(
        Tai::new(Instruction, "mov", ["[\{counter_name}]", step_tmp]).with_span(
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
  if self.lower_expr_to_eax(selector, s.span) {
    let selector_tmp = self.fresh_vreg()
    self.out.emit(
      Tai::new(Instruction, "mov", [selector_tmp, "eax"]).with_span(s.span),
    )
    let branch_labels = branches.map(_ => {
      fresh_label(self.out, ".L_case_branch")
    })
    for idx, b in branches {
      let target = branch_labels[idx]
      for l in b.node.labels {
        match l.node {
          Literal(Int(v)) => {
            self.out.emit(
              Tai::new(Instruction, "cmp", [selector_tmp, v]).with_span(l.span),
            )
            self.out.emit(
              Tai::new(Instruction, "je", [target]).with_span(l.span),
            )
          }
          Range(lo, hi) =>
            if int_lit(lo) is Some(lo_v) && int_lit(hi) is Some(hi_v) {
              let next_label = fresh_label(self.out, ".L_case_next")
              self.out
              ..emit(
                Tai::new(Instruction, "cmp", [selector_tmp, lo_v]).with_span(
                  l.span,
                ),
              )
              ..emit(
                Tai::new(Instruction, "jl", [next_label]).with_span(l.span),
              )
              ..emit(
                Tai::new(Instruction, "cmp", [selector_tmp, hi_v]).with_span(
                  l.span,
                ),
              )
              ..emit(Tai::new(Instruction, "jle", [target]).with_span(l.span))
              .emit(Tai::new(Label, next_label, []).with_span(l.span))
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
    for idx, b in branches {
      self.out.emit(Tai::new(Label, branch_labels[idx], []).with_span(b.span))
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
    Call(callee, args) =>
      match callee.node {
        Name(name) =>
          if !self.emit_named_call(name, args, s.span) {
            self.out.emit(
              Tai::new(Comment, "; call args unsupported", []).with_span(s.span),
            )
          }
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
      ignore(self.lower_expr_to_eax(e, s.span))
      if self.return_slot_offset is Some(ofs) {
        self.out.emit(
          Tai::new(Instruction, "mov", ["[rbp-\{ofs}]", "eax"]).with_span(
            s.span,
          ),
        )
      }
      match self.exit_label {
        Some(label) =>
          self.out.emit(Tai::new(Instruction, "jmp", [label]).with_span(s.span))
        None =>
          self.out.emit(Tai::new(Instruction, "ret", []).with_span(s.span))
      }
    }
    Exit(None) =>
      match self.exit_label {
        Some(label) =>
          self.out.emit(Tai::new(Instruction, "jmp", [label]).with_span(s.span))
        None =>
          self.out.emit(Tai::new(Instruction, "ret", []).with_span(s.span))
      }
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
      if !self.in_callable {
        for n in names {
          self.out
          ..switch(Globals)
          ..emit(Tai::new(Symbol, n, []).with_span(d.span))
          .switch(Procedures)
        }
      }
    ProcDecl(proc_decl) =>
      if proc_decl.body is Some(body) {
        let exit_label = fresh_label(self.out, ".L_proc_exit")
        let offsets = collect_local_offsets(body)
        let all_params = flatten_param_names(proc_decl.params)
        let reg_param_count = @cmp.minimum(
          all_params.length(),
          int_arg_regs.length(),
        )
        let local_and_reg_params = offsets.copy()
        let mut next_local = local_stack_size(offsets) + 8
        for i in 0..<reg_param_count {
          let pname = all_params[i]
          if !local_and_reg_params.contains(pname) {
            local_and_reg_params[pname] = next_local
            next_local = next_local + 8
          }
        }
        let param_offsets = collect_param_offsets(proc_decl.params)
        let stack_size = next_local - 8
        self.out
        ..switch(Procedures)
        ..emit(Tai::new(Label, proc_decl.name, []).with_span(d.span))
        ..emit(Tai::new(Instruction, "push", ["rbp"]).with_span(d.span))
        .emit(Tai::new(Instruction, "mov", ["rbp", "rsp"]).with_span(d.span))
        if stack_size > 0 {
          self.out.emit(
            Tai::new(Instruction, "sub", ["rsp", stack_size.to_string()]).with_span(
              d.span,
            ),
          )
        }
        for r in callee_saved_regs {
          self.out.emit(Tai::new(Instruction, "push", [r]).with_span(d.span))
        }
        for i in 0..<reg_param_count {
          let pname = all_params[i]
          if local_and_reg_params.get(pname) is Some(ofs) {
            self.out.emit(
              Tai::new(Instruction, "mov", ["[rbp-\{ofs}]", int_arg_regs[i]]).with_span(
                d.span,
              ),
            )
          }
        }
        let nested = LowerCtx::for_callable(
          self.out,
          exit_label,
          None,
          local_and_reg_params,
          param_offsets,
        )
        nested.emit_block(body)
        self.out.emit(Tai::new(Label, exit_label, []).with_span(d.span))
        for saved in callee_saved_regs.rev_iter() {
          self.out.emit(Tai::new(Instruction, "pop", [saved]).with_span(d.span))
        }
        self.out.emit(
          Tai::new(Instruction, "mov", ["rsp", "rbp"]).with_span(d.span),
        )
        self.out.emit(Tai::new(Instruction, "pop", ["rbp"]).with_span(d.span))
        self.out.emit(Tai::new(Instruction, "ret", []).with_span(d.span))
      }
    FuncDecl(func_decl) =>
      if func_decl.body is Some(body) {
        let exit_label = fresh_label(self.out, ".L_func_exit")
        let offsets = collect_local_offsets(body)
        let all_params = flatten_param_names(func_decl.params)
        let reg_param_count = @cmp.minimum(
          all_params.length(),
          int_arg_regs.length(),
        )
        let local_and_reg_params = offsets.copy()
        let mut next_local = local_stack_size(offsets) + 8
        for i in 0..<reg_param_count {
          let pname = all_params[i]
          if !local_and_reg_params.contains(pname) {
            local_and_reg_params[pname] = next_local
            next_local = next_local + 8
          }
        }
        let param_offsets = collect_param_offsets(func_decl.params)
        let return_slot_offset = next_local
        let stack_size = return_slot_offset
        self.out.switch(Procedures)
        self.out.emit(Tai::new(Label, func_decl.name, []).with_span(d.span))
        self.out.emit(Tai::new(Instruction, "push", ["rbp"]).with_span(d.span))
        self.out.emit(
          Tai::new(Instruction, "mov", ["rbp", "rsp"]).with_span(d.span),
        )
        if stack_size > 0 {
          self.out.emit(
            Tai::new(Instruction, "sub", ["rsp", stack_size.to_string()]).with_span(
              d.span,
            ),
          )
        }
        let saved = callee_saved_regs
        for r in saved {
          self.out.emit(Tai::new(Instruction, "push", [r]).with_span(d.span))
        }
        for i in 0..<reg_param_count {
          let pname = all_params[i]
          if local_and_reg_params.get(pname) is Some(ofs) {
            self.out.emit(
              Tai::new(Instruction, "mov", ["[rbp-\{ofs}]", int_arg_regs[i]]).with_span(
                d.span,
              ),
            )
          }
        }
        let nested = LowerCtx::for_callable(
          self.out,
          exit_label,
          Some(return_slot_offset),
          local_and_reg_params,
          param_offsets,
        )
        nested.emit_block(body)
        self.out.emit(Tai::new(Label, exit_label, []).with_span(d.span))
        for saved in callee_saved_regs.rev_iter() {
          self.out.emit(Tai::new(Instruction, "pop", [saved]).with_span(d.span))
        }
        self.out
        ..emit(
          Tai::new(Instruction, "mov", ["eax", "[rbp-\{return_slot_offset}]"]).with_span(
            d.span,
          ),
        )
        ..emit(Tai::new(Instruction, "mov", ["rsp", "rbp"]).with_span(d.span))
        ..emit(Tai::new(Instruction, "pop", ["rbp"]).with_span(d.span))
        .emit(Tai::new(Instruction, "ret", []).with_span(d.span))
      }
    _ => ()
  }
}

///|
fn LowerCtx::emit_block(
  self : LowerCtx,
  block : @ast.Spanned[@ast.Block],
) -> Unit {
  let has_callable = !self.in_callable &&
    block.node.decls.iter().any(has_callable_decl)
  let body_label = fresh_label(self.out, ".L_main_body")
  if !self.in_callable && has_callable {
    self.out.emit(
      Tai::new(Instruction, "jmp", [body_label]).with_span(block.span),
    )
  }
  for d in block.node.decls {
    self.emit_global_decl(d)
  }
  if !self.in_callable && has_callable {
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
  let main_saved = callee_saved_regs
  for r in main_saved {
    out.emit(Tai::new(Instruction, "push", [r]).with_span(cu.span))
  }

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

  for saved in main_saved.rev_iter() {
    out.emit(Tai::new(Instruction, "pop", [saved]).with_span(cu.span))
  }
  out.emit(Tai::new(Instruction, "ret", []).with_span(cu.span))

  out
}
