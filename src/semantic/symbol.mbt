///|
fn norm_name(s : String) -> String {
  @common.ascii_upper(s)
}

///|
pub(all) enum SymKind {
  Var
  Const
  Type
  Proc
  Unit
  Label
  Param
} derive(Show, Eq)

///|
struct Symbol {
  id : Int
  name : String
  kind : SymKind
  ty : TypeRef?
  owner_scope : Int
  flags : Int
  decl_span : @diag.Span
} derive(Show, Eq)

///|
priv struct Scope {
  parent : Int?
  table : Map[String, Int]
}

///|
struct Resolver {
  sink : @diag.DiagSink
  scopes : Array[Scope]
  symbols : Array[Symbol]
  proc_param_modes : Map[Int, Array[@ast.ParamMode]]
  mut current_scope : Int
  mut loop_depth : Int
  types : TypeRegistry
  return_type_stack : Array[TypeRef?]
}

///|
fn Resolver::error_type(self : Resolver) -> TypeRef {
  self.types.register(Error)
}

///|
fn Resolver::symbol_type(
  self : Resolver,
  sym_id : Int,
  span : @diag.Span,
) -> TypeRef {
  match self.symbols[sym_id].ty {
    Some(t) => t
    None => {
      self.sink.push_error(
        "S0005",
        "symbol '\{self.symbols[sym_id].name}' has no type information",
        span,
      )
      self.error_type()
    }
  }
}

///|
fn Resolver::expect_boolean(
  self : Resolver,
  ty : TypeRef,
  span : @diag.Span,
) -> Unit {
  if !self.types.is_boolean(ty) {
    self.sink.push_error("S0011", "expected boolean expression", span)
  }
}

///|
fn Resolver::expect_numeric(
  self : Resolver,
  ty : TypeRef,
  span : @diag.Span,
) -> Unit {
  if !self.types.is_numeric(ty) {
    self.sink.push_error("S0012", "expected numeric expression", span)
  }
}

///|
fn Resolver::expect_ordinal(
  self : Resolver,
  ty : TypeRef,
  span : @diag.Span,
) -> Unit {
  if !self.types.is_ordinal(ty) {
    self.sink.push_error("S0032", "expected ordinal expression", span)
  }
}

///|
fn Resolver::resolve_call(
  self : Resolver,
  callee : @ast.Spanned[@ast.Expr],
  args : Array[@ast.Spanned[@ast.Expr]],
  span : @diag.Span,
) -> TypeRef {
  let param_modes = match callee.node {
    Name(name) =>
      self.lookup_symbol(name).bind(sym_id => self.proc_param_modes.get(sym_id))
    _ => None
  }
  let callee_ty = self.infer_expr_type(callee)
  let arg_types = args.map(a => self.infer_expr_type(a))

  match self.types.get(callee_ty) {
    Proc(params, ret) => {
      if params.length() != arg_types.length() {
        self.sink.push_error(
          "S0016",
          "argument count mismatch: expected \{params.length()}, got \{arg_types.length()}",
          span,
        )
      }
      let n = @cmp.minimum(params.length(), arg_types.length())
      for i in 0..<n {
        if !self.types.is_assignable_from(params[i], arg_types[i]) {
          self.sink.push_error(
            "S0017",
            "argument type mismatch at index \{i}",
            args[i].span,
          )
        }
        if param_modes is Some(modes) && modes.get(i) is Some(Var | Out) {
          if !self.is_assignable_expr(args[i]) {
            self.sink.push_error(
              "S0030",
              "VAR/OUT argument must be assignable",
              args[i].span,
            )
          }
        }
      }
      match ret {
        Some(rt) => rt
        None => self.types.void_type()
      }
    }
    _ => {
      self.sink.push_error(
        "S0015", "call target is not a procedure/function", span,
      )
      self.error_type()
    }
  }
}

///|
fn Resolver::infer_expr_type(
  self : Resolver,
  e : @ast.Spanned[@ast.Expr],
) -> TypeRef {
  match e.node {
    Name(name) =>
      match self.use_symbol(name, e.span) {
        Some(id) => self.symbol_type(id, e.span)
        None => self.error_type()
      }
    Literal(lit) =>
      match lit {
        Int(_) => self.types.integer_type()
        Real(_) => self.types.real_type()
        String(_) => self.types.string_type()
        Bool(_) => self.types.boolean_type()
        Nil => self.error_type()
      }
    Unary(op, rhs) => {
      let rty = self.infer_expr_type(rhs)
      match op {
        Plus => {
          self.expect_numeric(rty, e.span)
          rty
        }
        Minus => {
          self.expect_numeric(rty, e.span)
          rty
        }
        Not => {
          self.expect_boolean(rty, e.span)
          self.types.boolean_type()
        }
        Deref =>
          match self.types.get(rty) {
            Pointer(base) => base
            _ => {
              self.sink.push_error(
                "S0013",
                "cannot dereference non-pointer value",
                e.span,
              )
              self.error_type()
            }
          }
        Addr => self.types.make_pointer(rty)
      }
    }
    Binary(op, lhs, rhs) => {
      let lty = self.infer_expr_type(lhs)
      let rty = self.infer_expr_type(rhs)
      match op {
        Add | Sub | Mul => {
          self.expect_numeric(lty, lhs.span)
          self.expect_numeric(rty, rhs.span)
          if self.types.is_compatible_with(lty, self.types.real_type()) ||
            self.types.is_compatible_with(rty, self.types.real_type()) {
            self.types.real_type()
          } else {
            self.types.integer_type()
          }
        }
        RealDiv => {
          self.expect_numeric(lty, lhs.span)
          self.expect_numeric(rty, rhs.span)
          self.types.real_type()
        }
        IntDiv | Mod | Shl | Shr => {
          self.expect_numeric(lty, lhs.span)
          self.expect_numeric(rty, rhs.span)
          self.types.integer_type()
        }
        And | Or | Xor =>
          if self.types.is_boolean(lty) && self.types.is_boolean(rty) {
            self.types.boolean_type()
          } else {
            self.expect_numeric(lty, lhs.span)
            self.expect_numeric(rty, rhs.span)
            self.types.integer_type()
          }
        Eq | Ne | Lt | Le | Gt | Ge => {
          if !self.types.is_compatible_with(lty, rty) {
            self.sink.push_error(
              "S0014",
              "incompatible operands in comparison",
              e.span,
            )
          }
          self.types.boolean_type()
        }
        In | Is => self.types.boolean_type()
        As => lty
      }
    }
    Call(callee, args) => self.resolve_call(callee, args, e.span)
    Index(base, idx) => {
      let bty = self.infer_expr_type(base)
      let ity = self.infer_expr_type(idx)
      if !self.types.is_ordinal(ity) {
        self.sink.push_error("S0020", "array index must be ordinal", idx.span)
      }
      match self.types.array_element_type(bty) {
        Some(elem) => elem
        None => {
          self.sink.push_error("S0018", "indexing non-array value", e.span)
          self.error_type()
        }
      }
    }
    Field(base, field_name) => {
      let bty = self.infer_expr_type(base)
      match self.types.record_fields(bty) {
        Some(fields) => {
          let matched = fields
            .iter()
            .find_first(f => norm_name(f.name) == norm_name(field_name))
          match matched {
            Some(f) => f.ty
            None => {
              self.sink.push_error(
                "S0021",
                "unknown field '\{field_name}'",
                e.span,
              )
              self.error_type()
            }
          }
        }
        None => {
          self.sink.push_error(
            "S0022",
            "field access on non-record value",
            e.span,
          )
          self.error_type()
        }
      }
    }
    SetLiteral(items) => {
      for item in items {
        let _ = self.infer_expr_type(item)
      }
      self.error_type()
    }
    Range(a, b) => {
      let _ = self.infer_expr_type(a)
      let _ = self.infer_expr_type(b)
      self.error_type()
    }
    Paren(inner) => self.infer_expr_type(inner)
    Error => self.error_type()
  }
}

///|
pub fn Resolver::new(sink : @diag.DiagSink) -> Resolver {
  let r : Resolver = {
    sink,
    scopes: [{ parent: None, table: {} }],
    symbols: [],
    proc_param_modes: {},
    current_scope: 0,
    loop_depth: 0,
    types: TypeRegistry::new(),
    return_type_stack: [],
  }
  r.bootstrap_builtins()
  r
}

///|
fn Resolver::push_return_type(self : Resolver, ty : TypeRef?) -> Unit {
  self.return_type_stack.push(ty)
}

///|
fn Resolver::is_assignable_expr(
  self : Resolver,
  e : @ast.Spanned[@ast.Expr],
) -> Bool {
  if e.node is Paren(inner) {
    self.is_assignable_expr(inner)
  } else {
    e.node is (Name(_) | Index(_) | Field(_) | Unary(Deref, _))
  }
}

///|
fn Resolver::flatten_param_signature(
  self : Resolver,
  params : Array[@ast.Spanned[@ast.ParamDecl]],
) -> (Array[TypeRef], Array[@ast.ParamMode]) {
  let types = []
  let modes = []
  for p in params {
    let ty = self.resolve_type_expr(p.node.ty)
    for _n in p.node.names {
      types.push(ty)
      modes.push(p.node.mode)
    }
  }
  (types, modes)
}

///|
fn Resolver::enter_loop(self : Resolver) -> Unit {
  self.loop_depth = self.loop_depth + 1
}

///|
fn Resolver::leave_loop(self : Resolver) -> Unit {
  if self.loop_depth > 0 {
    self.loop_depth = self.loop_depth - 1
  }
}

///|
fn Resolver::expect_in_loop(
  self : Resolver,
  code : String,
  span : @diag.Span,
) -> Unit {
  if self.loop_depth == 0 {
    let msg = match code {
      "S0036" => "break is only allowed inside loops"
      "S0037" => "continue is only allowed inside loops"
      _ => "loop control statement is not allowed here"
    }
    self.sink.push_error(code, msg, span)
  }
}

///|
fn Resolver::expect_label_symbol(
  self : Resolver,
  name : String,
  span : @diag.Span,
) -> Unit {
  match self.lookup_symbol(name) {
    Some(id) =>
      if self.symbols[id].kind != Label {
        self.sink.push_error(
          "S0038", "goto/label target must be declared as label", span,
        )
      }
    None => self.sink.push_error("S0002", "undefined symbol '\{name}'", span)
  }
}

///|
fn Resolver::case_label_key(
  self : Resolver,
  e : @ast.Spanned[@ast.Expr],
) -> String? {
  let _ = self
  match e.node {
    Literal(Int(v)) => Some("I:\{v}")
    Literal(String(v)) => Some("S:\{v}")
    Literal(Bool(v)) => Some("B:\{v}")
    _ => None
  }
}

///|
fn Resolver::check_case_label_compat(
  self : Resolver,
  selector_ty : TypeRef,
  label : @ast.Spanned[@ast.Expr],
) -> Unit {
  match label.node {
    Range(lo, hi) => {
      let lty = self.infer_expr_type(lo)
      let hty = self.infer_expr_type(hi)
      if !self.types.is_assignable_from(selector_ty, lty) &&
        !self.types.is_compatible_with(selector_ty, lty) {
        self.sink.push_error(
          "S0034",
          "case label type is incompatible with selector",
          lo.span,
        )
      }
      if !self.types.is_assignable_from(selector_ty, hty) &&
        !self.types.is_compatible_with(selector_ty, hty) {
        self.sink.push_error(
          "S0034",
          "case label type is incompatible with selector",
          hi.span,
        )
      }
    }
    _ => {
      let lty = self.infer_expr_type(label)
      if !self.types.is_assignable_from(selector_ty, lty) &&
        !self.types.is_compatible_with(selector_ty, lty) {
        self.sink.push_error(
          "S0034",
          "case label type is incompatible with selector",
          label.span,
        )
      }
    }
  }
}

///|
fn Resolver::pop_return_type(self : Resolver) -> Unit {
  if self.return_type_stack.length() > 0 {
    self.return_type_stack.pop() |> ignore
  }
}

///|
fn Resolver::current_return_type(self : Resolver) -> TypeRef? {
  match self.return_type_stack {
    [] => None
    [..] => self.return_type_stack[self.return_type_stack.length() - 1]
  }
}

///|
fn Resolver::bootstrap_builtins(self : Resolver) -> Unit {
  let _ = self.define_symbol(
    "Integer",
    Type,
    Some(self.types.integer_type()),
    @diag.Span::new(0, 0, 0),
  )
  let _ = self.define_symbol(
    "Real",
    Type,
    Some(self.types.real_type()),
    @diag.Span::new(0, 0, 0),
  )
  let _ = self.define_symbol(
    "Boolean",
    Type,
    Some(self.types.boolean_type()),
    @diag.Span::new(0, 0, 0),
  )
  let _ = self.define_symbol(
    "Char",
    Type,
    Some(self.types.char_type()),
    @diag.Span::new(0, 0, 0),
  )
  let _ = self.define_symbol(
    "String",
    Type,
    Some(self.types.string_type()),
    @diag.Span::new(0, 0, 0),
  )
}

///|
pub fn Resolver::symbols(self : Resolver) -> Array[Symbol] {
  self.symbols
}

///|
pub fn Resolver::enter_scope(self : Resolver) -> Int {
  let id = self.scopes.length()
  self.scopes.push({ parent: Some(self.current_scope), table: {} })
  self.current_scope = id
  id
}

///|
pub fn Resolver::leave_scope(self : Resolver) -> Unit {
  if self.scopes[self.current_scope].parent is Some(parent) {
    self.current_scope = parent
  }
}

///|
pub fn Resolver::define_symbol(
  self : Resolver,
  name : String,
  kind : SymKind,
  ty : TypeRef?,
  span : @diag.Span,
) -> Int? {
  let key = norm_name(name)
  let table = self.scopes[self.current_scope].table
  match table.get(key) {
    Some(prev_id) => {
      let prev_name = self.symbols[prev_id].name
      self.sink.push_error(
        "S0001",
        "duplicate symbol '\{name}' (previously declared as '\{prev_name}')",
        span,
      )
      None
    }
    None => {
      let id = self.symbols.length()
      self.symbols.push({
        id,
        name,
        kind,
        ty,
        owner_scope: self.current_scope,
        flags: 0,
        decl_span: span,
      })
      table[key] = id
      Some(id)
    }
  }
}

///|
pub fn Resolver::lookup_symbol(self : Resolver, name : String) -> Int? {
  let key = norm_name(name)
  for scope_id = Some(self.current_scope) {
    guard scope_id is Some(id) else { return None }
    guard self.scopes[id].table.get(key) is Some(sym_id) else {
      continue self.scopes[id].parent
    }
    return Some(sym_id)
  }
}

///|
fn Resolver::use_symbol(
  self : Resolver,
  name : String,
  span : @diag.Span,
) -> Int? {
  match self.lookup_symbol(name) {
    Some(id) => Some(id)
    None => {
      self.sink.push_error("S0002", "undefined symbol '\{name}'", span)
      None
    }
  }
}

///|
fn Resolver::expect_type(
  self : Resolver,
  name : String,
  span : @diag.Span,
) -> TypeRef {
  match self.lookup_symbol(name) {
    Some(id) => {
      let sym = self.symbols[id]
      if sym.kind != Type {
        self.sink.push_error("S0004", "'\{name}' is not a type symbol", span)
        self.types.register(Error)
      } else {
        match sym.ty {
          Some(t) => t
          None => {
            self.sink.push_error(
              "S0003",
              "type symbol '\{name}' has no resolved type",
              span,
            )
            self.types.register(Error)
          }
        }
      }
    }
    None => {
      self.sink.push_error("S0003", "unknown type '\{name}'", span)
      self.types.register(Error)
    }
  }
}

///|
fn Resolver::int_bound_value(
  self : Resolver,
  e : @ast.Spanned[@ast.Expr],
) -> Int? {
  match e.node {
    Literal(Int(v)) =>
      (v |> @string.parse_int |> Some) catch {
        _ => {
          self.sink.push_error(
            "S0026",
            "subrange bound must be integer literal",
            e.span,
          )
          None
        }
      }
    _ => {
      self.sink.push_error(
        "S0026",
        "subrange bound must be integer literal",
        e.span,
      )
      None
    }
  }
}

///|
fn Resolver::resolve_type_expr(
  self : Resolver,
  ty : @ast.Spanned[@ast.TypeExpr],
) -> TypeRef {
  match ty.node {
    Named(name) => self.expect_type(name, ty.span)
    Pointer(inner) => {
      let base = self.resolve_type_expr(inner)
      self.types.make_pointer(base)
    }
    Array(index_expr, elem_ty) => {
      let elem = self.resolve_type_expr(elem_ty)
      match index_expr.node {
        Range(a, b) => {
          let low = self.int_bound_value(a)
          let high = self.int_bound_value(b)
          match (low, high) {
            (Some(l), Some(h)) =>
              if l > h {
                self.sink.push_error(
                  "S0027",
                  "subrange lower bound must not exceed upper bound",
                  index_expr.span,
                )
                self.error_type()
              } else {
                match
                  self.types.create_static_array(
                    self.types.integer_type(),
                    l,
                    h,
                    elem,
                  ) {
                  Some(arr) => arr
                  None => self.error_type()
                }
              }
            _ => self.error_type()
          }
        }
        _ => {
          self.sink.push_error(
            "S0025",
            "array index type must be subrange",
            index_expr.span,
          )
          self.error_type()
        }
      }
    }
    Record(fields) => {
      let out_fields = []
      for f in fields {
        let fty = self.resolve_type_expr(f.node.ty)
        for n in f.node.names {
          out_fields.push({ name: n, ty: fty })
        }
      }
      match self.types.create_record(out_fields) {
        Some(rec) => rec
        None => {
          self.sink.push_error(
            "S0029",
            "record fields must be unique and valid",
            ty.span,
          )
          self.error_type()
        }
      }
    }
    Enum(names) => self.types.make_enum(names)
    Subrange(a, b) => {
      let low = self.int_bound_value(a)
      let high = self.int_bound_value(b)
      match (low, high) {
        (Some(l), Some(h)) =>
          if l > h {
            self.sink.push_error(
              "S0027",
              "subrange lower bound must not exceed upper bound",
              ty.span,
            )
            self.error_type()
          } else {
            match self.types.create_subrange(self.types.integer_type(), l, h) {
              Some(sr) => sr
              None => self.error_type()
            }
          }
        _ => self.error_type()
      }
    }
    Set(elem) => {
      let et = self.resolve_type_expr(elem)
      match self.types.create_set(et) {
        Some(st) => st
        None => {
          self.sink.push_error(
            "S0028",
            "set element type must be ordinal",
            elem.span,
          )
          self.error_type()
        }
      }
    }
    Error => self.types.register(Error)
  }
}

///|
fn Resolver::resolve_expr(self : Resolver, e : @ast.Spanned[@ast.Expr]) -> Unit {
  let _ = self.infer_expr_type(e)
}

///|
fn Resolver::resolve_stmt(self : Resolver, s : @ast.Spanned[@ast.Stmt]) -> Unit {
  match s.node {
    Empty => ()
    Compound(stmts) =>
      for st in stmts {
        self.resolve_stmt(st)
      }
    Assign(lhs, rhs) => {
      let lty = self.infer_expr_type(lhs)
      let rty = self.infer_expr_type(rhs)
      if !self.types.is_assignable_from(lty, rty) {
        self.sink.push_error("S0010", "incompatible assignment types", s.span)
      }
    }
    Call(callee, args) => {
      let _ = self.resolve_call(callee, args, s.span)
    }
    If(cond, then_s, else_s) => {
      let cty = self.infer_expr_type(cond)
      self.expect_boolean(cty, cond.span)
      self.resolve_stmt(then_s)
      if else_s is Some(es) {
        self.resolve_stmt(es)
      }
    }
    Case(cond, branches, else_s) => {
      let cty = self.infer_expr_type(cond)
      self.expect_ordinal(cty, cond.span)
      let seen_labels = Set::new()
      for b in branches {
        for lbl in b.node.labels {
          self.check_case_label_compat(cty, lbl)
          match lbl.node {
            Range(_, _) => ()
            _ =>
              if self.case_label_key(lbl) is Some(key) {
                if seen_labels.contains(key) {
                  self.sink.push_error(
                    "S0035",
                    "duplicate case label",
                    lbl.span,
                  )
                } else {
                  seen_labels.add(key)
                }
              }
          }
        }
        self.resolve_stmt(b.node.body)
      }
      if else_s is Some(es) {
        self.resolve_stmt(es)
      }
    }
    While(cond, body) => {
      let cty = self.infer_expr_type(cond)
      self.expect_boolean(cty, cond.span)
      self.enter_loop()
      self.resolve_stmt(body)
      self.leave_loop()
    }
    RepeatUntil(stmts, cond) => {
      self.enter_loop()
      for st in stmts {
        self.resolve_stmt(st)
      }
      self.leave_loop()
      let cty = self.infer_expr_type(cond)
      self.expect_boolean(cty, cond.span)
    }
    For(loop_var, from_, _, to_, body) => {
      let vty = self.infer_expr_type(loop_var)
      let fty = self.infer_expr_type(from_)
      let tty = self.infer_expr_type(to_)
      if !self.is_assignable_expr(loop_var) {
        self.sink.push_error(
          "S0031",
          "for-loop control variable must be assignable",
          loop_var.span,
        )
      }
      self.expect_ordinal(vty, loop_var.span)
      self.expect_ordinal(fty, from_.span)
      self.expect_ordinal(tty, to_.span)
      if !self.types.is_assignable_from(vty, fty) {
        self.sink.push_error(
          "S0010",
          "for-range start type mismatch",
          from_.span,
        )
      }
      if !self.types.is_assignable_from(vty, tty) {
        self.sink.push_error("S0010", "for-range end type mismatch", to_.span)
      }
      self.enter_loop()
      self.resolve_stmt(body)
      self.leave_loop()
    }
    With(items, body) => {
      for it in items {
        self.resolve_expr(it)
      }
      self.resolve_stmt(body)
    }
    TryExcept(try_s, handlers, else_s) => {
      self.resolve_stmt(try_s)
      for h in handlers {
        self.enter_scope() |> ignore
        if h.node.name is Some(name) {
          let hty = h.node.ty.map(tyexpr => self.resolve_type_expr(tyexpr))
          self.define_symbol(name, Var, hty, h.span) |> ignore
        }
        self.resolve_stmt(h.node.body)
        self.leave_scope()
      }
      if else_s is Some(es) {
        self.resolve_stmt(es)
      }
    }
    TryFinally(try_s, finally_s) =>
      self..resolve_stmt(try_s).resolve_stmt(finally_s)
    Raise(Some(e)) => ignore(self.infer_expr_type(e))
    Raise(None) => ()
    Label(name, stmt) => {
      self.expect_label_symbol(name, s.span)
      self.resolve_stmt(stmt)
    }
    Goto(name) => self.expect_label_symbol(name, s.span)
    Asm(_) => ()
    Break => self.expect_in_loop("S0036", s.span)
    Continue => self.expect_in_loop("S0037", s.span)
    Exit(Some(e)) => {
      let ety = self.infer_expr_type(e)
      match self.current_return_type() {
        Some(rty) =>
          if !self.types.is_assignable_from(rty, ety) {
            self.sink.push_error(
              "S0023",
              "exit expression type mismatch",
              e.span,
            )
          }
        None =>
          self.sink.push_error(
            "S0024",
            "exit expression is only allowed in function",
            e.span,
          )
      }
    }
    Exit(None) => ()
    Error => ()
  }
}

///|
fn Resolver::resolve_decl(self : Resolver, d : @ast.Spanned[@ast.Decl]) -> Unit {
  match d.node {
    ConstDecl(name, expr) => {
      let cty = self.infer_expr_type(expr)
      if self.types.get(cty) is Error {
        self.sink.push_error(
          "S0019",
          "constant expression has invalid type",
          expr.span,
        )
      }
      let _ = self.define_symbol(name, Const, None, d.span)
    }
    TypeDecl(name, tyexpr) => {
      let ty = self.resolve_type_expr(tyexpr)
      let _ = self.define_symbol(name, Type, Some(ty), d.span)
    }
    VarDecl(names, tyexpr, init) => {
      let ty = self.resolve_type_expr(tyexpr)
      for n in names {
        let _ = self.define_symbol(n, Var, Some(ty), d.span)
      }
      if init is Some(expr) {
        let ety = self.infer_expr_type(expr)
        if !self.types.is_assignable_from(ty, ety) {
          self.sink.push_error("S0010", "initializer type mismatch", expr.span)
        }
      }
    }
    ProcDecl(pd) => {
      let (param_types, param_modes) = self.flatten_param_signature(pd.params)
      let proc_ty = self.types.make_proc(param_types, None)
      let proc_id = self.define_symbol(pd.name, Proc, Some(proc_ty), d.span)
      if proc_id is Some(id) {
        self.proc_param_modes[id] = param_modes
      }
      if pd.body is Some(body) {
        self.push_return_type(None)
        self.enter_scope() |> ignore
        for p in pd.params {
          let ty = self.resolve_type_expr(p.node.ty)
          for n in p.node.names {
            let _ = self.define_symbol(n, Param, Some(ty), p.span)
          }
        }
        self.resolve_block(body)
        self.leave_scope()
        self.pop_return_type()
      }
    }
    FuncDecl(fd) => {
      let (param_types, param_modes) = self.flatten_param_signature(fd.params)
      let ret = self.resolve_type_expr(fd.result_ty)
      let fn_ty = self.types.make_proc(param_types, Some(ret))
      let fn_id = self.define_symbol(fd.name, Proc, Some(fn_ty), d.span)
      if fn_id is Some(id) {
        self.proc_param_modes[id] = param_modes
      }
      if fd.body is Some(body) {
        self.push_return_type(Some(ret))
        self.enter_scope() |> ignore
        for p in fd.params {
          let ty = self.resolve_type_expr(p.node.ty)
          for n in p.node.names {
            let _ = self.define_symbol(n, Param, Some(ty), p.span)
          }
        }
        let _ = self.define_symbol("Result", Var, Some(ret), d.span)
        self..resolve_block(body)..leave_scope().pop_return_type()
      }
    }
    LabelDecl(names) =>
      for n in names {
        let _ = self.define_symbol(n, Label, None, d.span)
      }
    Error => ()
  }
}

///|
fn Resolver::resolve_block(
  self : Resolver,
  b : @ast.Spanned[@ast.Block],
) -> Unit {
  for d in b.node.decls {
    self.resolve_decl(d)
  }
  for s in b.node.stmts {
    self.resolve_stmt(s)
  }
}

///|
fn Resolver::resolve_uses(
  self : Resolver,
  items : Array[@ast.Spanned[@ast.UsesItem]],
) -> Unit {
  for u in items {
    let _ = self.define_symbol(u.node.unit_name, Unit, None, u.span)
  }
}

///|
pub fn Resolver::resolve_compilation_unit(
  self : Resolver,
  cu : @ast.Spanned[@ast.CompilationUnit],
) -> Unit {
  match cu.node {
    @ast.ProgramUnit(p) => {
      let _ = self.define_symbol(p.name, Unit, None, cu.span)
      self.resolve_uses(p.uses)
      self.resolve_block(p.block)
      for s in p.finalization {
        self.resolve_stmt(s)
      }
    }
    @ast.UnitModule(u) => {
      let _ = self.define_symbol(u.name, Unit, None, cu.span)
      self.resolve_uses(u.interface_uses)
      for d in u.interface_decls {
        self.resolve_decl(d)
      }
      self.resolve_uses(u.implementation_uses)
      self.resolve_block(u.implementation_block)
      for s in u.initialization {
        self.resolve_stmt(s)
      }
      for s in u.finalization {
        self.resolve_stmt(s)
      }
    }
    @ast.LibraryUnit(l) => {
      let _ = self.define_symbol(l.name, Unit, None, cu.span)
      self.resolve_uses(l.uses)
      self.resolve_block(l.block)
      for s in l.finalization {
        self.resolve_stmt(s)
      }
    }
  }
}

///|
pub fn analyze(
  cu : @ast.Spanned[@ast.CompilationUnit],
  sink : @diag.DiagSink,
) -> Resolver {
  let resolver = Resolver::new(sink)
  resolver.resolve_compilation_unit(cu)
  resolver
}
