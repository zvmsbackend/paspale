///|
fn has_diag_code(sink : @diag.DiagSink, code : String) -> Bool {
  sink.all().iter().any(d => d.code == code)
}

///|
fn count_diag_code(sink : @diag.DiagSink, code : String) -> Int {
  sink.all().iter().filter(d => d.code == code).count()
}

///|
test "parse program unit with precedence" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(
    0, "program Demo; begin x := 1 + 2 * 3; end.", sink,
  )

  match cu.node {
    ProgramUnit(p) => {
      assert_eq(p.name, "Demo")
      assert_eq(p.block.node.stmts.length(), 1)
      guard p.block.node.stmts[0].node is Assign(_, rhs) else {
        fail("expected assignment statement")
      }
      guard rhs.node is Binary(Add, _, right) else {
        fail("expected additive expression")
      }
      guard right.node is Binary(Mul, _, _) else {
        fail("expected multiplication on right side")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse unit module skeleton" {
  let sink = @diag.DiagSink::new()
  let src = "unit U; interface uses SysUtils; implementation begin end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    UnitModule(u) => {
      assert_eq(u.name, "U")
      assert_eq(u.interface_uses.length(), 1)
      assert_eq(u.implementation_block.node.stmts.length(), 0)
    }
    _ => fail("expected unit module")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse expression with keyword operators" {
  let sink = @diag.DiagSink::new()
  let expr = @parser.parse_expr_text(0, "a shl 1 + b", sink)

  guard expr.node is Binary(Add, lhs, _) else {
    fail("expected additive top-level expression")
  }
  guard lhs.node is Binary(Shl, _, _) else { fail("expected shl on lhs") }
  assert_eq(sink.length(), 0)
}

///|
test "parse declarations in program block" {
  let sink = @diag.DiagSink::new()
  let src = "program D; const A = 1; type T = integer; var x, y: T; begin x := A; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    ProgramUnit(p) => {
      assert_eq(p.block.node.decls.length(), 3)
      assert_eq(p.block.node.stmts.length(), 1)
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse case and try statements" {
  let sink = @diag.DiagSink::new()
  let src = "program S; begin case x of 1: y:=1; else y:=2; end; try y:=1; except on E: Ex do y:=3; end; raise E; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    ProgramUnit(p) => {
      assert_eq(p.block.node.stmts.length(), 3)
      match p.block.node.stmts[0].node {
        Case(_) => ()
        _ => fail("expected case statement")
      }
      match p.block.node.stmts[1].node {
        TryExcept(_) => ()
        _ => fail("expected try/except statement")
      }
      match p.block.node.stmts[2].node {
        Raise(_) => ()
        _ => fail("expected raise statement")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.length(), 0)
}

///|
test "program finalization consumes trailing END" {
  let sink = @diag.DiagSink::new()
  let src = "program P; begin x:=1; end finalization x:=2; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    ProgramUnit(p) => assert_eq(p.finalization.length(), 1)
    _ => fail("expected program unit")
  }
  assert_eq(sink.length(), 0)
}

///|
test "library finalization consumes trailing END" {
  let sink = @diag.DiagSink::new()
  let src = "library L; begin end finalization exit; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    LibraryUnit(l) => assert_eq(l.finalization.length(), 1)
    _ => fail("expected library unit")
  }
  assert_eq(sink.length(), 0)
}

///|
test "expression parser reports trailing tokens" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_expr_text(0, "1 + 2 extra", sink)
  assert_eq(sink.length(), 1)
  assert_eq(sink.all()[0].code, "P0021")
}

///|
test "compilation unit parser reports trailing tokens" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "program P; begin end. extra", sink)
  assert_eq(sink.length(), 1)
  assert_eq(sink.all()[0].code, "P0021")
}

///|
test "bare procedure call without parentheses" {
  let sink = @diag.DiagSink::new()
  let cu = @parser.parse_text(0, "program P; begin foo; obj.bar; end.", sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(p.block.node.stmts.length(), 2)
  guard p.block.node.stmts[0].node is Call(callee, args) else {
    fail("expected call statement")
  }
  assert_eq(args.length(), 0)
  guard callee.node is Name("foo") else { fail("expected foo call") }
  guard p.block.node.stmts[1].node is Call(_, args) else {
    fail("expected qualified call statement")
  }
  assert_eq(args.length(), 0)
  assert_eq(sink.length(), 0)
}

///|
test "uses clause supports dotted unit names" {
  let sink = @diag.DiagSink::new()
  let src = "program P; uses System.SysUtils, Foo.Bar.Baz; begin end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    ProgramUnit(p) => {
      assert_eq(p.uses.length(), 2)
      assert_eq(p.uses[0].node.unit_name, "System.SysUtils")
      assert_eq(p.uses[1].node.unit_name, "Foo.Bar.Baz")
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse with asm and label statement" {
  let sink = @diag.DiagSink::new()
  let src = "program P; label 10; begin with obj do foo; asm mov ax, bx end; 10: foo; end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(p.block.node.decls.length(), 1)
  match p.block.node.decls[0].node {
    LabelDecl(labels) => assert_eq(labels[0], "10")
    _ => fail("expected label declaration")
  }
  assert_eq(p.block.node.stmts.length(), 3)
  match p.block.node.stmts[0].node {
    With(_, _) => ()
    _ => fail("expected with statement")
  }
  match p.block.node.stmts[1].node {
    Asm(_) => ()
    _ => fail("expected asm statement")
  }
  match p.block.node.stmts[2].node {
    Label("10", _) => ()
    _ => fail("expected label statement")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse message directive and set range expression" {
  let sink = @diag.DiagSink::new()
  let src = "program P; procedure Foo; message WM_USER; begin end; begin x := [1, 2..3]; end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  guard p.block.node.decls[0].node is ProcDecl(pd) else {
    fail("expected proc declaration")
  }
  assert_eq(pd.directives.length(), 1)
  match pd.directives[0].node {
    Message("WM_USER") => ()
    _ => fail("expected message directive")
  }
  guard p.block.node.stmts[0].node is Assign(_, rhs) else {
    fail("expected assignment")
  }
  guard rhs.node is SetLiteral(items) else { fail("expected set literal") }
  assert_eq(items.length(), 2)
  guard items[1].node is Range(_) else { fail("expected range item") }
  assert_eq(sink.length(), 0)
}

///|
test "parse array type with subrange index" {
  let sink = @diag.DiagSink::new()
  let src = "program P; type A = array[1..10] of integer; var a: A; begin end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  guard p.block.node.decls[0].node is TypeDecl("A", ty) else {
    fail("expected type declaration")
  }
  guard ty.node is Array(idx, _) else { fail("expected array type") }
  guard idx.node is Range(_) else { fail("expected range index type") }
  assert_eq(sink.length(), 0)
}

///|
test "non-happy expr missing closing paren" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_expr_text(0, "(1 + 2", sink)
  assert_true(has_diag_code(sink, "P0003"))
}

///|
test "non-happy statement expression-only is rejected" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "program P; begin 1 + 2; end.", sink)
  assert_true(has_diag_code(sink, "P0005"))
}

///|
test "non-happy invalid type expression" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "program P; type T = 1 + 2; begin end.", sink)
  assert_true(has_diag_code(sink, "P0030"))
}

///|
test "non-happy invalid label declaration" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "program P; label ; begin end.", sink)
  assert_true(has_diag_code(sink, "P0031"))
}

///|
test "non-happy missing unit terminator dot" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(
    0, "unit U; interface implementation begin end", sink,
  )
  assert_true(has_diag_code(sink, "P0001"))
}

///|
test "non-happy missing compilation-unit header" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "begin end.", sink)
  assert_true(has_diag_code(sink, "P0020"))
}

///|
test "recovery continues after multiple statement errors" {
  let sink = @diag.DiagSink::new()
  let src = "program P; begin x := ; 1 + 2; y := 3; end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(p.block.node.stmts.length(), 3)
  match p.block.node.stmts[2].node {
    Assign(_, _) => ()
    _ => fail("expected trailing assignment to be parsed")
  }
  assert_true(has_diag_code(sink, "P0004"))
  assert_true(has_diag_code(sink, "P0005"))
}

///|
test "recovery continues from declaration errors" {
  let sink = @diag.DiagSink::new()
  let src = "program P; const A = ; var x: integer; begin x := 1; end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_true(p.block.node.decls.length() >= 2)
  assert_eq(p.block.node.stmts.length(), 1)
  match p.block.node.stmts[0].node {
    Assign(_, _) => ()
    _ => fail("expected assignment after declaration error")
  }
  assert_true(has_diag_code(sink, "P0004"))
  assert_true(count_diag_code(sink, "P0004") >= 1)
}

///|
test "non-happy missing identifier emits P0002" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "program ; begin end.", sink)
  assert_true(has_diag_code(sink, "P0002"))
}

///|
test "non-happy missing begin emits P0011" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "program P; x := 1; end.", sink)
  assert_true(has_diag_code(sink, "P0011"))
}

///|
test "non-happy try without except/finally emits P0040" {
  let sink = @diag.DiagSink::new()
  let _ = @parser.parse_text(0, "program P; begin try x := 1; y := 2", sink)
  assert_true(has_diag_code(sink, "P0040"))
}

///|
test "parse try-finally shape" {
  let sink = @diag.DiagSink::new()
  let src = "program P; begin try a:=1; b:=2; finally c:=3; end; end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(p.block.node.stmts.length(), 1)
  guard p.block.node.stmts[0].node is TryFinally(try_block, finally_block) else {
    fail("expected try-finally")
  }
  match try_block.node {
    Compound(items) => assert_eq(items.length(), 2)
    _ => fail("expected compound try block")
  }
  match finally_block.node {
    Compound(items) => assert_eq(items.length(), 1)
    _ => fail("expected compound finally block")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse if while for repeat branches" {
  let sink = @diag.DiagSink::new()
  let src = "program P; begin if x then a:=1 else a:=2; while x do a:=3; for i := 10 downto 1 do foo; repeat a:=4; b:=5; until done; end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(p.block.node.stmts.length(), 4)
  match p.block.node.stmts[0].node {
    If(_, _, Some(_)) => ()
    _ => fail("expected if with else")
  }
  match p.block.node.stmts[1].node {
    While(_, _) => ()
    _ => fail("expected while")
  }
  match p.block.node.stmts[2].node {
    For(_, _, Downto, _, _) => ()
    _ => fail("expected downto for")
  }
  match p.block.node.stmts[3].node {
    RepeatUntil(items, _) => assert_eq(items.length(), 2)
    _ => fail("expected repeat-until")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse goto break continue exit edges" {
  let sink = @diag.DiagSink::new()
  let src = "program P; begin break; continue; exit; exit(1); goto done; done: foo; end."
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(p.block.node.stmts.length(), 6)
  assert_true(p.block.node.stmts[0].node is Break)
  assert_true(p.block.node.stmts[1].node is Continue)
  match p.block.node.stmts[2].node {
    Exit(None) => ()
    _ => fail("expected bare exit")
  }
  match p.block.node.stmts[3].node {
    Exit(Some(_)) => ()
    _ => fail("expected exit(value)")
  }
  assert_true(p.block.node.stmts[4].node is Goto(_))
  match p.block.node.stmts[5].node {
    Label("done", _) => ()
    _ => fail("expected label statement")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse broad procedure directive branches" {
  let sink = @diag.DiagSink::new()
  let src =
    #| program P;
    #| procedure Fwd; forward;
    #| procedure Ext; external 'm';
    #| procedure C; cdecl; begin end;
    #| procedure S; stdcall; begin end;
    #| procedure Pa; pascal; begin end;
    #| procedure R; register; begin end;
    #| procedure I; inline; begin end;
    #| procedure A; assembler; begin end;
    #| procedure O; overload; begin end;
    #| procedure V; virtual; begin end;
    #| procedure Ab; abstract; begin end;
    #| procedure Ov; override; begin end;
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_true(p.block.node.decls.length() >= 12)
  match p.block.node.decls[0].node {
    ProcDecl(pd) => {
      assert_true(pd.directives[0].node is Forward)
      assert_true(pd.body is None)
    }
    _ => fail("expected forward proc")
  }
  match p.block.node.decls[1].node {
    ProcDecl(pd) => {
      assert_true(pd.directives[0].node is External(_))
      assert_true(pd.body is None)
    }
    _ => fail("expected external proc")
  }
  match p.block.node.decls[2].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is CallingConv(Cdecl))
    _ => fail("expected cdecl proc")
  }
  match p.block.node.decls[3].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is CallingConv(Stdcall))
    _ => fail("expected stdcall proc")
  }
  match p.block.node.decls[4].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is CallingConv(Pascal))
    _ => fail("expected pascal proc")
  }
  match p.block.node.decls[5].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is CallingConv(Register))
    _ => fail("expected register proc")
  }
  match p.block.node.decls[6].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is Inline)
    _ => fail("expected inline proc")
  }
  match p.block.node.decls[7].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is Assembler)
    _ => fail("expected assembler proc")
  }
  match p.block.node.decls[8].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is Overload)
    _ => fail("expected overload proc")
  }
  match p.block.node.decls[9].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is Virtual)
    _ => fail("expected virtual proc")
  }
  match p.block.node.decls[10].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is Abstract)
    _ => fail("expected abstract proc")
  }
  match p.block.node.decls[11].node {
    ProcDecl(pd) => assert_true(pd.directives[0].node is Override)
    _ => fail("expected override proc")
  }
  assert_eq(sink.length(), 0)
}

///|
test "parse function declaration with result type" {
  let sink = @diag.DiagSink::new()
  let src =
    #| program P;
    #| function Add(a, b: integer): integer;
    #| begin Add := a + b; end;
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_true(p.block.node.decls.length() >= 1)
  guard p.block.node.decls[0].node is FuncDecl(fd) else {
    fail("expected func decl")
  }
  assert_eq(fd.name, "Add")
  assert_true(fd.body is Some(_))
  assert_eq(sink.length(), 0)
}

///|
test "parse type declarations with record pointer enum" {
  let sink = @diag.DiagSink::new()
  let src =
    #| program P;
    #| type
    #|   IntPtr = ^integer;
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(sink.length(), 0)
  guard p.block.node.decls[0].node is TypeDecl("IntPtr", ty) else {
    fail("expected intptr type decl")
  }
  guard ty.node is Pointer(_) else { fail("expected pointer type") }
}

///|
test "parse enum type declaration" {
  let sink = @diag.DiagSink::new()
  let src =
    #| program P;
    #| type Color = (Red, Green, Blue);
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(sink.length(), 0)
  guard p.block.node.decls[0].node is TypeDecl("Color", ty) else {
    fail("expected color type decl")
  }
  guard ty.node is Enum(names) else { fail("expected enum type") }
  assert_eq(names.length(), 3)
}

///|
test "parse record type declaration" {
  let sink = @diag.DiagSink::new()
  let src =
    #| program P;
    #| type Point = record x, y: integer; end;
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  guard cu.node is ProgramUnit(p) else { fail("expected program unit") }
  assert_eq(sink.length(), 0)
  guard p.block.node.decls[0].node is TypeDecl("Point", ty) else {
    fail("expected point type decl")
  }
  guard ty.node is Record(fields) else { fail("expected record type") }
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].node.names.length(), 2)
}
