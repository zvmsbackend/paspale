///|
test "module ir tracks stage transitions" {
  let m = @ir.ModuleIr::new()
  assert_false(m.reached(Parsed))
  m.mark_stage(Parsed)
  m.mark_stage(Resolved)
  m.mark_stage(Parsed)
  assert_true(m.reached(Parsed))
  assert_true(m.reached(Resolved))
  assert_eq(m.stages.length(), 2)
}

///|
test "proc info has stable defaults" {
  let span = @diag.Span::new(0, 1, 2)
  let p = @ir.ProcInfo::new(7, span, span)

  assert_eq(p.proc_sym, 7)
  assert_true(p.parent_proc is None)
  assert_eq(p.para_stack_size, 0)
  assert_eq(p.curr_exit_label, "L.exit")
}

///|
test "opt info starts with empty sets" {
  let opt = @ir.OptInfo::new(3)

  assert_eq(opt.index, 3)
  assert_eq(opt.def_set.length(), 0)
  assert_eq(opt.use_set.length(), 0)
  assert_eq(opt.life_set.length(), 0)
  assert_eq(opt.defsum_set.length(), 0)
}
