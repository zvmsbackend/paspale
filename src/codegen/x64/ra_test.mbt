///|
test "ra plan colors non-overlapping vregs with same register" {
  let insts = [
    @x64.LiveInst::new([], [0]),
    @x64.LiveInst::new([0], []),
    @x64.LiveInst::new([], [1]),
    @x64.LiveInst::new([1], []),
  ]
  let plan = @x64.allocate_plan(insts, 1)

  assert_eq(plan.colors.length(), 2)
  assert_true(plan.colors[0] is Some(0))
  assert_true(plan.colors[1] is Some(0))
}

///|
test "ra plan spills when register budget is too small" {
  let insts = [
    @x64.LiveInst::new([], [0]),
    @x64.LiveInst::new([], [1]),
    @x64.LiveInst::new([0, 1], [2]),
    @x64.LiveInst::new([2], []),
  ]
  let plan = @x64.allocate_plan(insts, 2)

  let mut spilled = 0
  for c in plan.colors {
    if c is None {
      spilled = spilled + 1
    }
  }
  assert_true(spilled >= 1)
}

///|
test "ra physical allocation returns register and spill maps" {
  let insts = [
    @x64.LiveInst::new([], [0]),
    @x64.LiveInst::new([], [1]),
    @x64.LiveInst::new([], [2]),
    @x64.LiveInst::new([0, 1, 2], []),
  ]
  let alloc = @x64.allocate_physical(insts, ["eax", "ebx"])

  assert_true(
    alloc.reg_of_vreg.contains(0) || alloc.spill_offset_of_vreg.contains(0),
  )
  assert_true(
    alloc.reg_of_vreg.contains(1) || alloc.spill_offset_of_vreg.contains(1),
  )
  assert_true(
    alloc.reg_of_vreg.contains(2) || alloc.spill_offset_of_vreg.contains(2),
  )
  assert_true(alloc.stack_size >= 8)
}
