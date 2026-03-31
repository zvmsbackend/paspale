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
  }
  r.bootstrap_builtins()
  r
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
      let (low, high) = match index_expr.node {
        @ast.Range(a, b) => {
          let l = match a.node {
            @ast.Literal(@ast.Int(v)) => @string.parse_int(v) catch { _ => 0 }
            _ => 0
          }
          let h = match b.node {
            @ast.Literal(@ast.Int(v)) => @string.parse_int(v) catch { _ => 0 }
            _ => 0
          }
          (l, h)
        }
        _ => (0, 0)
      }
      self.types.make_static_array(self.types.integer_type(), low, high, elem)
    }
    @ast.Record(fields) => {
      let out_fields = []
      for f in fields {
        let fty = self.resolve_type_expr(f.node.ty)
        for n in f.node.names {
          out_fields.push(FieldDef::{ name: n, ty: fty })
        }
      }
      self.types.make_record(out_fields)
    }
    @ast.Enum(names) => self.types.make_enum(names)
    @ast.Subrange(a, b) => {
      let low = match a.node {
        @ast.Literal(@ast.Int(v)) => @string.parse_int(v) catch { _ => 0 }
        _ => 0
      }
      let high = match b.node {
        @ast.Literal(@ast.Int(v)) => @string.parse_int(v) catch { _ => 0 }
        _ => 0
      }
      self.types.make_subrange(self.types.integer_type(), low, high)
    }
    @ast.Set(elem) => {
      let et = self.resolve_type_expr(elem)
      self.types.make_set(et)
    }
    @ast.Error => self.types.register(Error)
  }
}

///|
fn Resolver::resolve_expr(self : Resolver, e : @ast.Spanned[@ast.Expr]) -> Unit {
  match e.node {
    @ast.Name(name) => {
      let _ = self.use_symbol(name, e.span)
    }
    @ast.Literal(_) => ()
    @ast.Unary(_, rhs) => self.resolve_expr(rhs)
    @ast.Binary(_, lhs, rhs) => {
      self.resolve_expr(lhs)
      self.resolve_expr(rhs)
    }
    @ast.Call(callee, args) => {
      self.resolve_expr(callee)
      for a in args {
        self.resolve_expr(a)
      }
    }
    @ast.Index(base, idx) => {
      self.resolve_expr(base)
      self.resolve_expr(idx)
    }
    @ast.Field(base, _) => self.resolve_expr(base)
    @ast.SetLiteral(items) =>
      for item in items {
        self.resolve_expr(item)
      }
    @ast.Range(a, b) => {
      self.resolve_expr(a)
      self.resolve_expr(b)
    }
    @ast.Paren(inner) => self.resolve_expr(inner)
    @ast.Error => ()
  }
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
      self.resolve_expr(lhs)
      self.resolve_expr(rhs)
    }
    @ast.Call(callee, args) => {
      self.resolve_expr(callee)
      for a in args {
        self.resolve_expr(a)
      }
    }
    @ast.If(cond, then_s, else_s) => {
      self.resolve_expr(cond)
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
      self.resolve_expr(cond)
      self.resolve_stmt(body)
    }
    @ast.RepeatUntil(stmts, cond) => {
      for st in stmts {
        self.resolve_stmt(st)
      }
      self.resolve_expr(cond)
    }
    @ast.For(loop_var, from_, _, to_, body) => {
      self.resolve_expr(loop_var)
      self.resolve_expr(from_)
      self.resolve_expr(to_)
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
        Some(e) => self.resolve_expr(e)
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
        Some(e) => self.resolve_expr(e)
        None => ()
      }
    @ast.Error => ()
  }
}

///|
fn Resolver::resolve_decl(self : Resolver, d : @ast.Spanned[@ast.Decl]) -> Unit {
  match d.node {
    @ast.ConstDecl(name, expr) => {
      self.resolve_expr(expr)
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
        Some(expr) => self.resolve_expr(expr)
        None => ()
      }
    }
    @ast.ProcDecl(pd) => {
      let param_types = pd.params.map(p => self.resolve_type_expr(p.node.ty))
      let proc_ty = self.types.make_proc(param_types, None)
      let _ = self.define_symbol(pd.name, Proc, Some(proc_ty), d.span)
      match pd.body {
        Some(body) => {
          self.enter_scope() |> ignore
          for p in pd.params {
            let ty = self.resolve_type_expr(p.node.ty)
            for n in p.node.names {
              let _ = self.define_symbol(n, Param, Some(ty), p.span)
            }
          }
          self.resolve_block(body)
          self.leave_scope()
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
