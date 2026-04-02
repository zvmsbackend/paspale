///|
fn index_of(xs : Array[String], target : String) -> Int {
  xs.search(target).unwrap_or(-1)
}

///|
test "module graph builds direct dependencies" {
  let sink = @diag.DiagSink::new()
  let a = @parser.parse_text(
    0, "unit A; interface uses B; implementation begin end.", sink,
  )
  let b = @parser.parse_text(
    1, "unit B; interface uses C; implementation begin end.", sink,
  )
  let c = @parser.parse_text(
    2, "unit C; interface implementation begin end.", sink,
  )

  let g = collect_module_graph([a, b, c])
  let deps = g.direct_deps("A")

  assert_eq(deps.length(), 1)
  assert_eq(deps[0], "B")
}

///|
test "module graph topo order follows uses relation" {
  let sink = @diag.DiagSink::new()
  let a = @parser.parse_text(
    0, "unit A; interface uses B; implementation begin end.", sink,
  )
  let b = @parser.parse_text(
    1, "unit B; interface uses C; implementation begin end.", sink,
  )
  let c = @parser.parse_text(
    2, "unit C; interface implementation begin end.", sink,
  )

  let g = collect_module_graph([a, b, c])
  let order = g.topo_order()

  let ia = index_of(order, "A")
  let ib = index_of(order, "B")
  let ic = index_of(order, "C")
  assert_true(ic >= 0)
  assert_true(ib >= 0)
  assert_true(ia >= 0)
  assert_true(ic < ib)
  assert_true(ib < ia)
}

///|
test "module graph cycle fallback remains total" {
  let sink = @diag.DiagSink::new()
  let a = @parser.parse_text(
    0, "unit A; interface uses B; implementation begin end.", sink,
  )
  let b = @parser.parse_text(
    1, "unit B; interface uses A; implementation begin end.", sink,
  )

  let g = collect_module_graph([a, b])
  let order = g.topo_order()

  assert_eq(order.length(), 2)
  assert_true(index_of(order, "A") >= 0)
  assert_true(index_of(order, "B") >= 0)
}
