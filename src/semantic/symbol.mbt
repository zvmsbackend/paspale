///|
fn ascii_upper(s : String) -> String {
  String::from_iter(s.iter().map(Char::to_ascii_uppercase))
}

///|
fn norm_name(s : String) -> String {
  ascii_upper(s)
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
pub struct Symbol {
  id : Int
  name : String
  kind : SymKind
  ty : TypeRef?
  owner_scope : Int
  flags : Int
  decl_span : @diag.Span
} derive(Show, Eq)

///|
pub struct Scope {
  id : Int
  parent : Int?
  table : Map[String, Int]
}

///|
pub struct Resolver {
  sink : @diag.DiagSink
  scopes : Array[Scope]
  symbols : Array[Symbol]
  mut current_scope : Int
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
      push_error(
        self.sink,
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
    push_error(self.sink, "S0011", "expected boolean expression", span)
  }
}

///|
fn Resolver::expect_numeric(
  self : Resolver,
  ty : TypeRef,
  span : @diag.Span,
) -> Unit {
  if !self.types.is_numeric(ty) {
    push_error(self.sink, "S0012", "expected numeric expression", span)
  }
}

///|
fn Resolver::resolve_call(
  self : Resolver,
  callee : @ast.Spanned[@ast.Expr],
  args : Array[@ast.Spanned[@ast.Expr]],
  span : @diag.Span,
) -> TypeRef {
  let callee_ty = self.infer_expr_type(callee)
  let arg_types = args.map(a => self.infer_expr_type(a))

  match self.types.get(callee_ty) {
    Proc(params, ret) => {
      if params.length() != arg_types.length() {
        push_error(
          self.sink,
          "S0016",
          "argument count mismatch: expected \{params.length()}, got \{arg_types.length()}",
          span,
        )
      }
      let n = if params.length() < arg_types.length() {
        params.length()
      } else {
        arg_types.length()
      }
      for i = 0; i < n; i = i + 1 {
        if !self.types.is_assignable_from(params[i], arg_types[i]) {
          push_error(
            self.sink,
            "S0017",
            "argument type mismatch at index \{i}",
            args[i].span,
          )
        }
      }
      match ret {
        Some(rt) => rt
        None => self.types.void_type()
      }
    }
    _ => {
      push_error(
        self.sink,
        "S0015",
        "call target is not a procedure/function",
        span,
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
    @ast.Name(name) =>
      match self.use_symbol(name, e.span) {
        Some(id) => self.symbol_type(id, e.span)
        None => self.error_type()
      }
    @ast.Literal(lit) =>
      match lit {
        @ast.Int(_) => self.types.integer_type()
        @ast.Real(_) => self.types.real_type()
        @ast.String(_) => self.types.string_type()
        @ast.Bool(_) => self.types.boolean_type()
        @ast.Nil => self.error_type()
      }
    @ast.Unary(op, rhs) => {
      let rty = self.infer_expr_type(rhs)
      match op {
        @ast.Plus => {
          self.expect_numeric(rty, e.span)
          rty
        }
        @ast.Minus => {
          self.expect_numeric(rty, e.span)
          rty
        }
        @ast.Not => {
          self.expect_boolean(rty, e.span)
          self.types.boolean_type()
        }
        @ast.Deref =>
          match self.types.get(rty) {
            Pointer(base) => base
            _ => {
              push_error(
                self.sink,
                "S0013",
                "cannot dereference non-pointer value",
                e.span,
              )
              self.error_type()
            }
          }
        @ast.Addr => self.types.make_pointer(rty)
      }
    }
    @ast.Binary(op, lhs, rhs) => {
      let lty = self.infer_expr_type(lhs)
      let rty = self.infer_expr_type(rhs)
      match op {
        @ast.Add | @ast.Sub | @ast.Mul => {
          self.expect_numeric(lty, lhs.span)
          self.expect_numeric(rty, rhs.span)
          if self.types.is_compatible_with(lty, self.types.real_type()) ||
            self.types.is_compatible_with(rty, self.types.real_type()) {
            self.types.real_type()
          } else {
            self.types.integer_type()
          }
        }
        @ast.RealDiv => {
          self.expect_numeric(lty, lhs.span)
          self.expect_numeric(rty, rhs.span)
          self.types.real_type()
        }
        @ast.IntDiv | @ast.Mod | @ast.Shl | @ast.Shr => {
          self.expect_numeric(lty, lhs.span)
          self.expect_numeric(rty, rhs.span)
          self.types.integer_type()
        }
        @ast.And | @ast.Or | @ast.Xor =>
          if self.types.is_boolean(lty) && self.types.is_boolean(rty) {
            self.types.boolean_type()
          } else {
            self.expect_numeric(lty, lhs.span)
            self.expect_numeric(rty, rhs.span)
            self.types.integer_type()
          }
        @ast.Eq | @ast.Ne | @ast.Lt | @ast.Le | @ast.Gt | @ast.Ge => {
          if !self.types.is_compatible_with(lty, rty) {
            push_error(
              self.sink,
              "S0014",
              "incompatible operands in comparison",
              e.span,
            )
          }
          self.types.boolean_type()
        }
        @ast.In | @ast.Is => self.types.boolean_type()
        @ast.As => lty
      }
    }
    @ast.Call(callee, args) => self.resolve_call(callee, args, e.span)
    @ast.Index(base, idx) => {
      let bty = self.infer_expr_type(base)
      let ity = self.infer_expr_type(idx)
      if !self.types.is_ordinal(ity) {
        push_error(self.sink, "S0020", "array index must be ordinal", idx.span)
      }
      match self.types.array_element_type(bty) {
        Some(elem) => elem
        None => {
          push_error(self.sink, "S0018", "indexing non-array value", e.span)
          self.error_type()
        }
      }
    }
    @ast.Field(base, field_name) => {
      let bty = self.infer_expr_type(base)
      match self.types.record_fields(bty) {
        Some(fields) => {
          let matched = fields
            .iter()
            .find_first(f => norm_name(f.name) == norm_name(field_name))
          match matched {
            Some(f) => f.ty
            None => {
              push_error(
                self.sink,
                "S0021",
                "unknown field '\{field_name}'",
                e.span,
              )
              self.error_type()
            }
          }
        }
        None => {
          push_error(
            self.sink,
            "S0022",
            "field access on non-record value",
            e.span,
          )
          self.error_type()
        }
      }
    }
    @ast.SetLiteral(items) => {
      for item in items {
        let _ = self.infer_expr_type(item)
      }
      self.error_type()
    }
    @ast.Range(a, b) => {
      let _ = self.infer_expr_type(a)
      let _ = self.infer_expr_type(b)
      self.error_type()
    }
    @ast.Paren(inner) => self.infer_expr_type(inner)
    @ast.Error => self.error_type()
  }
}

///|
fn push_error(
  sink : @diag.DiagSink,
  code : String,
  message : String,
  span : @diag.Span,
) -> Unit {
  sink.push(
    @diag.Diagnostic::new(@diag.Error, code, message).with_label(
      @diag.Label::primary(span, "here"),
    ),
  )
}

///|
pub fn Resolver::new(sink : @diag.DiagSink) -> Resolver {
  let r : Resolver = {
    sink,
    scopes: [{ id: 0, parent: None, table: Map::new() }],
    symbols: [],
    current_scope: 0,
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
fn Resolver::pop_return_type(self : Resolver) -> Unit {
  if self.return_type_stack.length() > 0 {
    self.return_type_stack.pop() |> ignore
  }
}

///|
fn Resolver::current_return_type(self : Resolver) -> TypeRef? {
  if self.return_type_stack.length() == 0 {
    None
  } else {
    self.return_type_stack[self.return_type_stack.length() - 1]
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
  self.scopes.push({ id, parent: Some(self.current_scope), table: Map::new() })
  self.current_scope = id
  id
}

///|
pub fn Resolver::leave_scope(self : Resolver) -> Unit {
  match self.scopes[self.current_scope].parent {
    Some(parent) => self.current_scope = parent
    None => ()
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
      push_error(
        self.sink,
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
      table.set(key, id)
      Some(id)
    }
  }
}

///|
pub fn Resolver::lookup_symbol(self : Resolver, name : String) -> Int? {
  let key = norm_name(name)
  let mut scope_id = Some(self.current_scope)
  while true {
    match scope_id {
      Some(id) =>
        match self.scopes[id].table.get(key) {
          Some(sym_id) => return Some(sym_id)
          None => scope_id = self.scopes[id].parent
        }
      None => return None
    }
  }
  None
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
      push_error(self.sink, "S0002", "undefined symbol '\{name}'", span)
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
        push_error(self.sink, "S0004", "'\{name}' is not a type symbol", span)
        self.types.register(Error)
      } else {
        match sym.ty {
          Some(t) => t
          None => {
            push_error(
              self.sink,
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
      push_error(self.sink, "S0003", "unknown type '\{name}'", span)
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
    @ast.Literal(@ast.Int(v)) =>
      Some(@string.parse_int(v)) catch {
        _ => {
          push_error(
            self.sink,
            "S0026",
            "subrange bound must be integer literal",
            e.span,
          )
          None
        }
      }
    _ => {
      push_error(
        self.sink,
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
    @ast.Named(name) => self.expect_type(name, ty.span)
    @ast.Pointer(inner) => {
      let base = self.resolve_type_expr(inner)
      self.types.make_pointer(base)
    }
    @ast.Array(index_expr, elem_ty) => {
      let elem = self.resolve_type_expr(elem_ty)
      match index_expr.node {
        @ast.Range(a, b) => {
          let low = self.int_bound_value(a)
          let high = self.int_bound_value(b)
          match (low, high) {
            (Some(l), Some(h)) =>
              if l > h {
                push_error(
                  self.sink,
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
          push_error(
            self.sink,
            "S0025",
            "array index type must be subrange",
            index_expr.span,
          )
          self.error_type()
        }
      }
    }
    @ast.Record(fields) => {
      let out_fields = []
      for f in fields {
        let fty = self.resolve_type_expr(f.node.ty)
        for n in f.node.names {
          out_fields.push(FieldDef::{ name: n, ty: fty })
        }
      }
      match self.types.create_record(out_fields) {
        Some(rec) => rec
        None => {
          push_error(
            self.sink,
            "S0029",
            "record fields must be unique and valid",
            ty.span,
          )
          self.error_type()
        }
      }
    }
    @ast.Enum(names) => self.types.make_enum(names)
    @ast.Subrange(a, b) => {
      let low = self.int_bound_value(a)
      let high = self.int_bound_value(b)
      match (low, high) {
        (Some(l), Some(h)) =>
          if l > h {
            push_error(
              self.sink,
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
    @ast.Set(elem) => {
      let et = self.resolve_type_expr(elem)
      match self.types.create_set(et) {
        Some(st) => st
        None => {
          push_error(
            self.sink,
            "S0028",
            "set element type must be ordinal",
            elem.span,
          )
          self.error_type()
        }
      }
    }
    @ast.Error => self.types.register(Error)
  }
}

///|
fn Resolver::resolve_expr(self : Resolver, e : @ast.Spanned[@ast.Expr]) -> Unit {
  let _ = self.infer_expr_type(e)
}

///|
fn Resolver::resolve_stmt(self : Resolver, s : @ast.Spanned[@ast.Stmt]) -> Unit {
  match s.node {
    @ast.Empty => ()
    @ast.Compound(stmts) =>
      for st in stmts {
        self.resolve_stmt(st)
      }
    @ast.Assign(lhs, rhs) => {
      let lty = self.infer_expr_type(lhs)
      let rty = self.infer_expr_type(rhs)
      if !self.types.is_assignable_from(lty, rty) {
        push_error(self.sink, "S0010", "incompatible assignment types", s.span)
      }
    }
    @ast.Call(callee, args) => {
      let _ = self.resolve_call(callee, args, s.span)
    }
    @ast.If(cond, then_s, else_s) => {
      let cty = self.infer_expr_type(cond)
      self.expect_boolean(cty, cond.span)
      self.resolve_stmt(then_s)
      match else_s {
        Some(es) => self.resolve_stmt(es)
        None => ()
      }
    }
    @ast.Case(cond, branches, else_s) => {
      self.resolve_expr(cond)
      for b in branches {
        for lbl in b.node.labels {
          self.resolve_expr(lbl)
        }
        self.resolve_stmt(b.node.body)
      }
      match else_s {
        Some(es) => self.resolve_stmt(es)
        None => ()
      }
    }
    @ast.While(cond, body) => {
      let cty = self.infer_expr_type(cond)
      self.expect_boolean(cty, cond.span)
      self.resolve_stmt(body)
    }
    @ast.RepeatUntil(stmts, cond) => {
      for st in stmts {
        self.resolve_stmt(st)
      }
      let cty = self.infer_expr_type(cond)
      self.expect_boolean(cty, cond.span)
    }
    @ast.For(loop_var, from_, _, to_, body) => {
      let vty = self.infer_expr_type(loop_var)
      let fty = self.infer_expr_type(from_)
      let tty = self.infer_expr_type(to_)
      self.expect_numeric(vty, loop_var.span)
      if !self.types.is_assignable_from(vty, fty) {
        push_error(
          self.sink,
          "S0010",
          "for-range start type mismatch",
          from_.span,
        )
      }
      if !self.types.is_assignable_from(vty, tty) {
        push_error(self.sink, "S0010", "for-range end type mismatch", to_.span)
      }
      self.resolve_stmt(body)
    }
    @ast.With(items, body) => {
      for it in items {
        self.resolve_expr(it)
      }
      self.resolve_stmt(body)
    }
    @ast.TryExcept(try_s, handlers, else_s) => {
      self.resolve_stmt(try_s)
      for h in handlers {
        self.enter_scope() |> ignore
        match h.node.name {
          Some(name) => {
            let hty = match h.node.ty {
              Some(tyexpr) => Some(self.resolve_type_expr(tyexpr))
              None => None
            }
            let _ = self.define_symbol(name, Var, hty, h.span)
          }
          None => ()
        }
        self.resolve_stmt(h.node.body)
        self.leave_scope()
      }
      match else_s {
        Some(es) => self.resolve_stmt(es)
        None => ()
      }
    }
    @ast.TryFinally(try_s, finally_s) => {
      self.resolve_stmt(try_s)
      self.resolve_stmt(finally_s)
    }
    @ast.Raise(expr) =>
      match expr {
        Some(e) => {
          let _ = self.infer_expr_type(e)
        }
        None => ()
      }
    @ast.Label(name, stmt) => {
      let _ = self.use_symbol(name, s.span)
      self.resolve_stmt(stmt)
    }
    @ast.Goto(name) => {
      let _ = self.use_symbol(name, s.span)
    }
    @ast.Asm(_) => ()
    @ast.Break => ()
    @ast.Continue => ()
    @ast.Exit(expr) =>
      match expr {
        Some(e) => {
          let ety = self.infer_expr_type(e)
          match self.current_return_type() {
            Some(rty) =>
              if !self.types.is_assignable_from(rty, ety) {
                push_error(
                  self.sink,
                  "S0023",
                  "exit expression type mismatch",
                  e.span,
                )
              }
            None =>
              push_error(
                self.sink,
                "S0024",
                "exit expression is only allowed in function",
                e.span,
              )
          }
        }
        None => ()
      }
    @ast.Error => ()
  }
}

///|
fn Resolver::resolve_decl(self : Resolver, d : @ast.Spanned[@ast.Decl]) -> Unit {
  match d.node {
    @ast.ConstDecl(name, expr) => {
      let cty = self.infer_expr_type(expr)
      if self.types.get(cty) is Error {
        push_error(
          self.sink,
          "S0019",
          "constant expression has invalid type",
          expr.span,
        )
      }
      let _ = self.define_symbol(name, Const, None, d.span)
    }
    @ast.TypeDecl(name, tyexpr) => {
      let ty = self.resolve_type_expr(tyexpr)
      let _ = self.define_symbol(name, Type, Some(ty), d.span)
    }
    @ast.VarDecl(names, tyexpr, init) => {
      let ty = self.resolve_type_expr(tyexpr)
      for n in names {
        let _ = self.define_symbol(n, Var, Some(ty), d.span)
      }
      match init {
        Some(expr) => {
          let ety = self.infer_expr_type(expr)
          if !self.types.is_assignable_from(ty, ety) {
            push_error(
              self.sink,
              "S0010",
              "initializer type mismatch",
              expr.span,
            )
          }
        }
        None => ()
      }
    }
    @ast.ProcDecl(pd) => {
      let param_types = pd.params.map(p => self.resolve_type_expr(p.node.ty))
      let proc_ty = self.types.make_proc(param_types, None)
      let _ = self.define_symbol(pd.name, Proc, Some(proc_ty), d.span)
      match pd.body {
        Some(body) => {
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
        None => ()
      }
    }
    @ast.FuncDecl(fd) => {
      let param_types = fd.params.map(p => self.resolve_type_expr(p.node.ty))
      let ret = self.resolve_type_expr(fd.result_ty)
      let fn_ty = self.types.make_proc(param_types, Some(ret))
      let _ = self.define_symbol(fd.name, Proc, Some(fn_ty), d.span)
      match fd.body {
        Some(body) => {
          self.push_return_type(Some(ret))
          self.enter_scope() |> ignore
          for p in fd.params {
            let ty = self.resolve_type_expr(p.node.ty)
            for n in p.node.names {
              let _ = self.define_symbol(n, Param, Some(ty), p.span)
            }
          }
          let _ = self.define_symbol("Result", Var, Some(ret), d.span)
          self.resolve_block(body)
          self.leave_scope()
          self.pop_return_type()
        }
        None => ()
      }
    }
    @ast.LabelDecl(names) =>
      for n in names {
        let _ = self.define_symbol(n, Label, None, d.span)
      }
    @ast.Error => ()
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
