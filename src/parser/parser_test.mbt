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
  let sink = @diag.new_sink()
  let cu = @parser.parse_text(
    0, "program Demo; begin x := 1 + 2 * 3; end.", sink,
  )

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.name, "Demo")
      assert_eq(p.block.node.stmts.length(), 1)
      match p.block.node.stmts[0].node {
        @ast.Assign(_, rhs) =>
          match rhs.node {
            @ast.Binary(@ast.Add, _, right) =>
              match right.node {
                @ast.Binary(@ast.Mul, _, _) => ()
                _ => fail("expected multiplication on right side")
              }
            _ => fail("expected additive expression")
          }
        _ => fail("expected assignment statement")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse unit module skeleton" {
  let sink = @diag.new_sink()
  let src = "unit U; interface uses SysUtils; implementation begin end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.UnitModule(u) => {
      assert_eq(u.name, "U")
      assert_eq(u.interface_uses.length(), 1)
      assert_eq(u.implementation_block.node.stmts.length(), 0)
    }
    _ => fail("expected unit module")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse expression with keyword operators" {
  let sink = @diag.new_sink()
  let expr = @parser.parse_expr_text(0, "a shl 1 + b", sink)

  match expr.node {
    @ast.Binary(@ast.Add, lhs, _) =>
      match lhs.node {
        @ast.Binary(@ast.Shl, _, _) => ()
        _ => fail("expected shl on lhs")
      }
    _ => fail("expected additive top-level expression")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse declarations in program block" {
  let sink = @diag.new_sink()
  let src = "program D; const A = 1; type T = integer; var x, y: T; begin x := A; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.decls.length(), 3)
      assert_eq(p.block.node.stmts.length(), 1)
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse case and try statements" {
  let sink = @diag.new_sink()
  let src = "program S; begin case x of 1: y:=1; else y:=2; end; try y:=1; except on E: Ex do y:=3; end; raise E; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.stmts.length(), 3)
      match p.block.node.stmts[0].node {
        @ast.Case(_, _, _) => ()
        _ => fail("expected case statement")
      }
      match p.block.node.stmts[1].node {
        @ast.TryExcept(_, _, _) => ()
        _ => fail("expected try/except statement")
      }
      match p.block.node.stmts[2].node {
        @ast.Raise(_) => ()
        _ => fail("expected raise statement")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "program finalization consumes trailing END" {
  let sink = @diag.new_sink()
  let src = "program P; begin x:=1; end finalization x:=2; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => assert_eq(p.finalization.length(), 1)
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "library finalization consumes trailing END" {
  let sink = @diag.new_sink()
  let src = "library L; begin end finalization exit; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.LibraryUnit(l) => assert_eq(l.finalization.length(), 1)
    _ => fail("expected library unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "expression parser reports trailing tokens" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_expr_text(0, "1 + 2 extra", sink)
  assert_eq(sink.len(), 1)
  assert_eq(sink.all()[0].code, "P0021")
}

///|
test "compilation unit parser reports trailing tokens" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "program P; begin end. extra", sink)
  assert_eq(sink.len(), 1)
  assert_eq(sink.all()[0].code, "P0021")
}

///|
test "bare procedure call without parentheses" {
  let sink = @diag.new_sink()
  let cu = @parser.parse_text(0, "program P; begin foo; obj.bar; end.", sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.stmts.length(), 2)
      match p.block.node.stmts[0].node {
        @ast.Call(callee, args) => {
          assert_eq(args.length(), 0)
          match callee.node {
            @ast.Name("foo") => ()
            _ => fail("expected foo call")
          }
        }
        _ => fail("expected call statement")
      }
      match p.block.node.stmts[1].node {
        @ast.Call(_, args) => assert_eq(args.length(), 0)
        _ => fail("expected qualified call statement")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "uses clause supports dotted unit names" {
  let sink = @diag.new_sink()
  let src = "program P; uses System.SysUtils, Foo.Bar.Baz; begin end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.uses.length(), 2)
      assert_eq(p.uses[0].node.unit_name, "System.SysUtils")
      assert_eq(p.uses[1].node.unit_name, "Foo.Bar.Baz")
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse with asm and label statement" {
  let sink = @diag.new_sink()
  let src = "program P; label 10; begin with obj do foo; asm mov ax, bx end; 10: foo; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.decls.length(), 1)
      match p.block.node.decls[0].node {
        @ast.LabelDecl(labels) => assert_eq(labels[0], "10")
        _ => fail("expected label declaration")
      }
      assert_eq(p.block.node.stmts.length(), 3)
      match p.block.node.stmts[0].node {
        @ast.With(_, _) => ()
        _ => fail("expected with statement")
      }
      match p.block.node.stmts[1].node {
        @ast.Asm(_) => ()
        _ => fail("expected asm statement")
      }
      match p.block.node.stmts[2].node {
        @ast.Label("10", _) => ()
        _ => fail("expected label statement")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse message directive and set range expression" {
  let sink = @diag.new_sink()
  let src = "program P; procedure Foo; message WM_USER; begin end; begin x := [1, 2..3]; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      match p.block.node.decls[0].node {
        @ast.ProcDecl(pd) => {
          assert_eq(pd.directives.length(), 1)
          match pd.directives[0].node {
            @ast.Message("WM_USER") => ()
            _ => fail("expected message directive")
          }
        }
        _ => fail("expected proc declaration")
      }
      match p.block.node.stmts[0].node {
        @ast.Assign(_, rhs) =>
          match rhs.node {
            @ast.SetLiteral(items) => {
              assert_eq(items.length(), 2)
              match items[1].node {
                @ast.Range(_, _) => ()
                _ => fail("expected range item")
              }
            }
            _ => fail("expected set literal")
          }
        _ => fail("expected assignment")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "non-happy expr missing closing paren" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_expr_text(0, "(1 + 2", sink)
  assert_true(has_diag_code(sink, "P0003"))
}

///|
test "non-happy statement expression-only is rejected" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "program P; begin 1 + 2; end.", sink)
  assert_true(has_diag_code(sink, "P0005"))
}

///|
test "non-happy invalid type expression" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "program P; type T = 1 + 2; begin end.", sink)
  assert_true(has_diag_code(sink, "P0030"))
}

///|
test "non-happy invalid label declaration" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "program P; label ; begin end.", sink)
  assert_true(has_diag_code(sink, "P0031"))
}

///|
test "non-happy missing unit terminator dot" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(
    0, "unit U; interface implementation begin end", sink,
  )
  assert_true(has_diag_code(sink, "P0001"))
}

///|
test "non-happy missing compilation-unit header" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "begin end.", sink)
  assert_true(has_diag_code(sink, "P0020"))
}

///|
test "recovery continues after multiple statement errors" {
  let sink = @diag.new_sink()
  let src = "program P; begin x := ; 1 + 2; y := 3; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.stmts.length(), 3)
      match p.block.node.stmts[2].node {
        @ast.Assign(_, _) => ()
        _ => fail("expected trailing assignment to be parsed")
      }
    }
    _ => fail("expected program unit")
  }
  assert_true(has_diag_code(sink, "P0004"))
  assert_true(has_diag_code(sink, "P0005"))
}

///|
test "recovery continues from declaration errors" {
  let sink = @diag.new_sink()
  let src = "program P; const A = ; var x: integer; begin x := 1; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_true(p.block.node.decls.length() >= 2)
      assert_eq(p.block.node.stmts.length(), 1)
      match p.block.node.stmts[0].node {
        @ast.Assign(_, _) => ()
        _ => fail("expected assignment after declaration error")
      }
    }
    _ => fail("expected program unit")
  }
  assert_true(has_diag_code(sink, "P0004"))
  assert_true(count_diag_code(sink, "P0004") >= 1)
}

///|
test "non-happy missing identifier emits P0002" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "program ; begin end.", sink)
  assert_true(has_diag_code(sink, "P0002"))
}

///|
test "non-happy missing begin emits P0011" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "program P; x := 1; end.", sink)
  assert_true(has_diag_code(sink, "P0011"))
}

///|
test "non-happy try without except/finally emits P0040" {
  let sink = @diag.new_sink()
  let _ = @parser.parse_text(0, "program P; begin try x := 1; y := 2", sink)
  assert_true(has_diag_code(sink, "P0040"))
}

///|
test "parse try-finally shape" {
  let sink = @diag.new_sink()
  let src = "program P; begin try a:=1; b:=2; finally c:=3; end; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.stmts.length(), 1)
      match p.block.node.stmts[0].node {
        @ast.TryFinally(try_block, finally_block) => {
          match try_block.node {
            @ast.Compound(items) => assert_eq(items.length(), 2)
            _ => fail("expected compound try block")
          }
          match finally_block.node {
            @ast.Compound(items) => assert_eq(items.length(), 1)
            _ => fail("expected compound finally block")
          }
        }
        _ => fail("expected try-finally")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse if while for repeat branches" {
  let sink = @diag.new_sink()
  let src = "program P; begin if x then a:=1 else a:=2; while x do a:=3; for i := 10 downto 1 do foo; repeat a:=4; b:=5; until done; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.stmts.length(), 4)
      match p.block.node.stmts[0].node {
        @ast.If(_, _, Some(_)) => ()
        _ => fail("expected if with else")
      }
      match p.block.node.stmts[1].node {
        @ast.While(_, _) => ()
        _ => fail("expected while")
      }
      match p.block.node.stmts[2].node {
        @ast.For(_, _, @ast.Downto, _, _) => ()
        _ => fail("expected downto for")
      }
      match p.block.node.stmts[3].node {
        @ast.RepeatUntil(items, _) => assert_eq(items.length(), 2)
        _ => fail("expected repeat-until")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse goto break continue exit edges" {
  let sink = @diag.new_sink()
  let src = "program P; begin break; continue; exit; exit(1); goto done; done: foo; end."
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(p.block.node.stmts.length(), 6)
      assert_true(p.block.node.stmts[0].node is @ast.Break)
      assert_true(p.block.node.stmts[1].node is @ast.Continue)
      match p.block.node.stmts[2].node {
        @ast.Exit(None) => ()
        _ => fail("expected bare exit")
      }
      match p.block.node.stmts[3].node {
        @ast.Exit(Some(_)) => ()
        _ => fail("expected exit(value)")
      }
      assert_true(p.block.node.stmts[4].node is @ast.Goto(_))
      match p.block.node.stmts[5].node {
        @ast.Label("done", _) => ()
        _ => fail("expected label statement")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse broad procedure directive branches" {
  let sink = @diag.new_sink()
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

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_true(p.block.node.decls.length() >= 12)
      match p.block.node.decls[0].node {
        @ast.ProcDecl(pd) => {
          assert_true(pd.directives[0].node is @ast.Forward)
          assert_true(pd.body is None)
        }
        _ => fail("expected forward proc")
      }
      match p.block.node.decls[1].node {
        @ast.ProcDecl(pd) => {
          assert_true(pd.directives[0].node is @ast.External(_))
          assert_true(pd.body is None)
        }
        _ => fail("expected external proc")
      }
      match p.block.node.decls[2].node {
        @ast.ProcDecl(pd) =>
          assert_true(pd.directives[0].node is @ast.CallingConv(@ast.Cdecl))
        _ => fail("expected cdecl proc")
      }
      match p.block.node.decls[3].node {
        @ast.ProcDecl(pd) =>
          assert_true(pd.directives[0].node is @ast.CallingConv(@ast.Stdcall))
        _ => fail("expected stdcall proc")
      }
      match p.block.node.decls[4].node {
        @ast.ProcDecl(pd) =>
          assert_true(pd.directives[0].node is @ast.CallingConv(@ast.Pascal))
        _ => fail("expected pascal proc")
      }
      match p.block.node.decls[5].node {
        @ast.ProcDecl(pd) =>
          assert_true(pd.directives[0].node is @ast.CallingConv(@ast.Register))
        _ => fail("expected register proc")
      }
      match p.block.node.decls[6].node {
        @ast.ProcDecl(pd) => assert_true(pd.directives[0].node is @ast.Inline)
        _ => fail("expected inline proc")
      }
      match p.block.node.decls[7].node {
        @ast.ProcDecl(pd) =>
          assert_true(pd.directives[0].node is @ast.Assembler)
        _ => fail("expected assembler proc")
      }
      match p.block.node.decls[8].node {
        @ast.ProcDecl(pd) => assert_true(pd.directives[0].node is @ast.Overload)
        _ => fail("expected overload proc")
      }
      match p.block.node.decls[9].node {
        @ast.ProcDecl(pd) => assert_true(pd.directives[0].node is @ast.Virtual)
        _ => fail("expected virtual proc")
      }
      match p.block.node.decls[10].node {
        @ast.ProcDecl(pd) => assert_true(pd.directives[0].node is @ast.Abstract)
        _ => fail("expected abstract proc")
      }
      match p.block.node.decls[11].node {
        @ast.ProcDecl(pd) => assert_true(pd.directives[0].node is @ast.Override)
        _ => fail("expected override proc")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse function declaration with result type" {
  let sink = @diag.new_sink()
  let src =
    #| program P;
    #| function Add(a, b: integer): integer;
    #| begin Add := a + b; end;
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_true(p.block.node.decls.length() >= 1)
      match p.block.node.decls[0].node {
        @ast.FuncDecl(fd) => {
          assert_eq(fd.name, "Add")
          assert_true(fd.body is Some(_))
        }
        _ => fail("expected func decl")
      }
    }
    _ => fail("expected program unit")
  }
  assert_eq(sink.len(), 0)
}

///|
test "parse type declarations with record pointer enum" {
  let sink = @diag.new_sink()
  let src =
    #| program P;
    #| type
    #|   IntPtr = ^integer;
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(sink.len(), 0)
      match p.block.node.decls[0].node {
        @ast.TypeDecl("IntPtr", ty) =>
          match ty.node {
            @ast.Pointer(_) => ()
            _ => fail("expected pointer type")
          }
        _ => fail("expected intptr type decl")
      }
    }
    _ => fail("expected program unit")
  }
}

///|
test "parse enum type declaration" {
  let sink = @diag.new_sink()
  let src =
    #| program P;
    #| type Color = (Red, Green, Blue);
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(sink.len(), 0)
      match p.block.node.decls[0].node {
        @ast.TypeDecl("Color", ty) =>
          match ty.node {
            @ast.Enum(names) => assert_eq(names.length(), 3)
            _ => fail("expected enum type")
          }
        _ => fail("expected color type decl")
      }
    }
    _ => fail("expected program unit")
  }
}

///|
test "parse record type declaration" {
  let sink = @diag.new_sink()
  let src =
    #| program P;
    #| type Point = record x, y: integer; end;
    #| begin end.
    #|
  let cu = @parser.parse_text(0, src, sink)

  match cu.node {
    @ast.ProgramUnit(p) => {
      assert_eq(sink.len(), 0)
      match p.block.node.decls[0].node {
        @ast.TypeDecl("Point", ty) =>
          match ty.node {
            @ast.Record(fields) => {
              assert_eq(fields.length(), 1)
              assert_eq(fields[0].node.names.length(), 2)
            }
            _ => fail("expected record type")
          }
        _ => fail("expected point type decl")
      }
    }
    _ => fail("expected program unit")
  }
}
