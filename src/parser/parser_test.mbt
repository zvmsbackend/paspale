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
