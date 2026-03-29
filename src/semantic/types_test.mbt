///|
test "type registry initializes with built-in types" {
  let reg = TypeRegistry::new()
  assert_true(reg.is_resolved(reg.integer_type()))
  assert_true(reg.is_resolved(reg.real_type()))
  assert_true(reg.is_resolved(reg.boolean_type()))
  assert_true(reg.is_resolved(reg.char_type()))
  assert_true(reg.is_resolved(reg.string_type()))
  assert_true(reg.is_resolved(reg.void_type()))
}

///|
test "type ref equality" {
  let reg = TypeRegistry::new()
  let int1 = reg.integer_type()
  let int2 = reg.integer_type()
  let real = reg.real_type()
  assert_true(int1.eq(int2))
  assert_false(int1.eq(real))
}

///|
test "create pointer type" {
  let reg = TypeRegistry::new()
  let ptr_int = reg.make_pointer(reg.integer_type())
  match reg.get(ptr_int) {
    Pointer(base) => assert_true(base.eq(reg.integer_type()))
    _ => fail("expected pointer type")
  }
}

///|
test "create static array type" {
  let reg = TypeRegistry::new()
  let arr = reg.make_static_array(reg.integer_type(), 1, 10, reg.string_type())
  assert_true(reg.is_static_array(arr))
  assert_true(reg.is_array(arr))
  match reg.get(arr) {
    StaticArray(idx, low, high, elem) => {
      assert_true(idx.eq(reg.integer_type()))
      assert_eq(low, 1)
      assert_eq(high, 10)
      assert_true(elem.eq(reg.string_type()))
    }
    _ => fail("expected static array")
  }
}

///|
test "create open array type" {
  let reg = TypeRegistry::new()
  let arr = reg.make_open_array(reg.integer_type())
  assert_true(reg.is_open_array(arr))
  assert_true(reg.is_array(arr))
  match reg.get(arr) {
    OpenArray(elem) => assert_true(elem.eq(reg.integer_type()))
    _ => fail("expected open array")
  }
}

///|
test "create dynamic array type" {
  let reg = TypeRegistry::new()
  let arr = reg.make_dynamic_array(reg.integer_type())
  assert_true(reg.is_dynamic_array(arr))
  assert_true(reg.is_array(arr))
  match reg.get(arr) {
    DynamicArray(elem) => assert_true(elem.eq(reg.integer_type()))
    _ => fail("expected dynamic array")
  }
}

///|
test "array element type" {
  let reg = TypeRegistry::new()
  let static_arr = reg.make_static_array(
    reg.integer_type(),
    0,
    9,
    reg.real_type(),
  )
  let open_arr = reg.make_open_array(reg.boolean_type())
  let dyn_arr = reg.make_dynamic_array(reg.char_type())
  let int_type = reg.integer_type()

  match reg.array_element_type(static_arr) {
    Some(elem) => assert_true(elem.eq(reg.real_type()))
    None => fail("expected element type")
  }
  match reg.array_element_type(open_arr) {
    Some(elem) => assert_true(elem.eq(reg.boolean_type()))
    None => fail("expected element type")
  }
  match reg.array_element_type(dyn_arr) {
    Some(elem) => assert_true(elem.eq(reg.char_type()))
    None => fail("expected element type")
  }
  assert_true(reg.array_element_type(int_type) is None)
}

///|
test "static array bounds" {
  let reg = TypeRegistry::new()
  let arr = reg.make_static_array(reg.char_type(), 1, 26, reg.integer_type())
  match reg.static_array_bounds(arr) {
    Some((low, high)) => {
      assert_eq(low, 1)
      assert_eq(high, 26)
    }
    None => fail("expected bounds")
  }
  let open_arr = reg.make_open_array(reg.integer_type())
  assert_true(reg.static_array_bounds(open_arr) is None)
}

///|
test "create enum type" {
  let reg = TypeRegistry::new()
  let names = ["Red", "Green", "Blue"]
  let enum_ty = reg.make_enum(names)
  match reg.get(enum_ty) {
    Enum(n) => {
      assert_eq(n.length(), 3)
      assert_eq(n[0], "Red")
      assert_eq(n[1], "Green")
      assert_eq(n[2], "Blue")
    }
    _ => fail("expected enum type")
  }
}

///|
test "create record type with fields" {
  let reg = TypeRegistry::new()
  let fields = [
    FieldDef::{ name: "x", ty: reg.integer_type() },
    FieldDef::{ name: "y", ty: reg.integer_type() },
  ]
  let rec = reg.make_record(fields)
  assert_true(reg.is_record(rec))
  match reg.record_fields(rec) {
    Some(f) => {
      assert_eq(f.length(), 2)
      assert_eq(f[0].name, "x")
      assert_eq(f[1].name, "y")
    }
    None => fail("expected fields")
  }
}

///|
test "create set type" {
  let reg = TypeRegistry::new()
  let set_ty = reg.make_set(reg.char_type())
  match reg.get(set_ty) {
    Set(elem) => assert_true(elem.eq(reg.char_type()))
    _ => fail("expected set type")
  }
}

///|
test "create subrange type" {
  let reg = TypeRegistry::new()
  let subrange = reg.make_subrange(reg.integer_type(), 1, 100)
  match reg.get(subrange) {
    Subrange(base, low, high) => {
      assert_true(base.eq(reg.integer_type()))
      assert_eq(low, 1)
      assert_eq(high, 100)
    }
    _ => fail("expected subrange type")
  }
}

///|
test "forward declaration resolution" {
  let reg = TypeRegistry::new()
  let fwd = reg.make_forward("MyType")
  assert_false(reg.is_resolved(fwd))
  let fields = [FieldDef::{ name: "value", ty: reg.integer_type() }]
  let resolved_count = reg.resolve_forward("MyType", Record(fields))
  assert_eq(resolved_count, 1)
  assert_true(reg.is_resolved(fwd))
  assert_false(reg.has_unresolved())
}

///|
test "multiple forward declarations" {
  let reg = TypeRegistry::new()
  let fwd1 = reg.make_forward("T")
  let fwd2 = reg.make_forward("T")
  assert_false(reg.is_resolved(fwd1))
  assert_false(reg.is_resolved(fwd2))
  let fields = [FieldDef::{ name: "x", ty: reg.integer_type() }]
  let count = reg.resolve_forward("T", Record(fields))
  assert_eq(count, 2)
  assert_true(reg.is_resolved(fwd1))
  assert_true(reg.is_resolved(fwd2))
}

///|
test "unresolved forward declarations" {
  let reg = TypeRegistry::new()
  assert_false(reg.has_unresolved())
  ignore(reg.make_forward("UnresolvedType"))
  assert_true(reg.has_unresolved())
  let names = reg.unresolved_names()
  assert_eq(names.length(), 1)
  assert_eq(names[0], "UnresolvedType")
}

///|
test "is_numeric check" {
  let reg = TypeRegistry::new()
  assert_true(reg.is_numeric(reg.integer_type()))
  assert_true(reg.is_numeric(reg.real_type()))
  assert_false(reg.is_numeric(reg.boolean_type()))
  assert_false(reg.is_numeric(reg.string_type()))
}

///|
test "is_ordinal check" {
  let reg = TypeRegistry::new()
  let names = ["A", "B"]
  let enum_ty = reg.make_enum(names)
  let subrange_ty = reg.make_subrange(reg.integer_type(), 1, 10)

  assert_true(reg.is_ordinal(reg.integer_type()))
  assert_true(reg.is_ordinal(reg.boolean_type()))
  assert_true(reg.is_ordinal(reg.char_type()))
  assert_true(reg.is_ordinal(enum_ty))
  assert_true(reg.is_ordinal(subrange_ty))
  assert_false(reg.is_ordinal(reg.real_type()))
  assert_false(reg.is_ordinal(reg.string_type()))
}

///|
test "create proc type" {
  let reg = TypeRegistry::new()
  let params = [reg.integer_type(), reg.real_type()]
  let proc_ty = reg.make_proc(params, Some(reg.boolean_type()))
  match reg.get(proc_ty) {
    Proc(p, r) => {
      assert_eq(p.length(), 2)
      assert_true(p[0].eq(reg.integer_type()))
      assert_true(p[1].eq(reg.real_type()))
      match r {
        Some(ret) => assert_true(ret.eq(reg.boolean_type()))
        None => fail("expected return type")
      }
    }
    _ => fail("expected proc type")
  }
  let void_proc = reg.make_proc([], None)
  match reg.get(void_proc) {
    Proc(p, r) => {
      assert_eq(p.length(), 0)
      assert_true(r is None)
    }
    _ => fail("expected void proc type")
  }
}

///|
test "is_assignable_from same types" {
  let reg = TypeRegistry::new()
  let int1 = reg.integer_type()
  let int2 = reg.integer_type()
  assert_true(reg.is_assignable_from(int1, int2))

  let real1 = reg.real_type()
  assert_true(reg.is_assignable_from(real1, real1))
}

///|
test "is_assignable_from numeric conversion" {
  let reg = TypeRegistry::new()
  let int = reg.integer_type()
  let real = reg.real_type()
  assert_true(reg.is_assignable_from(real, int))
  assert_false(reg.is_assignable_from(int, real))
}

///|
test "is_assignable_from subrange" {
  let reg = TypeRegistry::new()
  let int = reg.integer_type()
  let subrange = reg.make_subrange(int, 1, 10)

  assert_true(reg.is_assignable_from(int, subrange))
  assert_true(reg.is_assignable_from(subrange, int))
}

///|
test "is_assignable_from arrays" {
  let reg = TypeRegistry::new()
  let static_arr = reg.make_static_array(
    reg.integer_type(),
    1,
    10,
    reg.real_type(),
  )
  let open_arr = reg.make_open_array(reg.real_type())
  let dyn_arr = reg.make_dynamic_array(reg.real_type())

  assert_true(reg.is_assignable_from(open_arr, static_arr))
  assert_true(reg.is_assignable_from(open_arr, dyn_arr))
}

///|
test "is_compatible_with numeric types" {
  let reg = TypeRegistry::new()
  let int = reg.integer_type()
  let real = reg.real_type()

  assert_true(reg.is_compatible_with(int, int))
  assert_true(reg.is_compatible_with(int, real))
  assert_true(reg.is_compatible_with(real, int))
}

///|
test "is_compatible_with arrays" {
  let reg = TypeRegistry::new()
  let arr1 = reg.make_static_array(reg.integer_type(), 0, 9, reg.real_type())
  let arr2 = reg.make_static_array(
    reg.integer_type(),
    100,
    200,
    reg.real_type(),
  )

  assert_true(reg.is_compatible_with(arr1, arr2))
}

///|
test "create_subrange validation" {
  let reg = TypeRegistry::new()
  // Valid subrange with ordinal base
  let subrange = reg.create_subrange(reg.integer_type(), 1, 10)
  assert_true(subrange is Some(_))
  // Invalid: base is not ordinal
  let invalid_base = reg.create_subrange(reg.real_type(), 1, 10)
  assert_true(invalid_base is None)
  // Invalid: low > high
  let invalid_bounds = reg.create_subrange(reg.integer_type(), 10, 1)
  assert_true(invalid_bounds is None)
}

///|
test "create_enum validation" {
  let reg = TypeRegistry::new()
  // Valid enum
  let enum1 = reg.create_enum(["A", "B", "C"])
  assert_true(enum1 is Some(_))
  // Invalid: empty names
  let empty_enum = reg.create_enum([])
  assert_true(empty_enum is None)
  // Invalid: duplicate names
  let dup_enum = reg.create_enum(["A", "B", "A"])
  assert_true(dup_enum is None)
}

///|
test "create_static_array validation" {
  let reg = TypeRegistry::new()
  // Valid static array
  let arr = reg.create_static_array(reg.integer_type(), 1, 10, reg.real_type())
  assert_true(arr is Some(_))
  // Invalid: index type not ordinal
  let invalid_idx = reg.create_static_array(
    reg.real_type(),
    1,
    10,
    reg.integer_type(),
  )
  assert_true(invalid_idx is None)
  // Invalid: low > high
  let invalid_bounds = reg.create_static_array(
    reg.integer_type(),
    10,
    1,
    reg.real_type(),
  )
  assert_true(invalid_bounds is None)
}

///|
test "create_open_array validation" {
  let reg = TypeRegistry::new()
  // Valid open array
  let arr = reg.create_open_array(reg.integer_type())
  assert_true(arr is Some(_))
  // Invalid: forward type
  let fwd = reg.make_forward("ForwardType")
  let invalid_forward = reg.create_open_array(fwd)
  assert_true(invalid_forward is None)
}

///|
test "create_dynamic_array validation" {
  let reg = TypeRegistry::new()
  // Valid dynamic array
  let arr = reg.create_dynamic_array(reg.integer_type())
  assert_true(arr is Some(_))
  // Invalid: forward type
  let fwd = reg.make_forward("ForwardType")
  let invalid_forward = reg.create_dynamic_array(fwd)
  assert_true(invalid_forward is None)
}

///|
test "create_set validation" {
  let reg = TypeRegistry::new()
  // Valid set with ordinal element
  let set1 = reg.create_set(reg.integer_type())
  assert_true(set1 is Some(_))
  let set2 = reg.create_set(reg.char_type())
  assert_true(set2 is Some(_))
  // Invalid: element is not ordinal
  let invalid_set = reg.create_set(reg.real_type())
  assert_true(invalid_set is None)
}

///|
test "create_record validation" {
  let reg = TypeRegistry::new()
  // Valid record
  let fields = [
    FieldDef::{ name: "x", ty: reg.integer_type() },
    FieldDef::{ name: "y", ty: reg.integer_type() },
  ]
  let rec = reg.create_record(fields)
  assert_true(rec is Some(_))
  // Invalid: duplicate field names
  let dup_fields = [
    FieldDef::{ name: "x", ty: reg.integer_type() },
    FieldDef::{ name: "x", ty: reg.real_type() },
  ]
  let invalid_rec = reg.create_record(dup_fields)
  assert_true(invalid_rec is None)
}

///|
test "create_pointer validation" {
  let reg = TypeRegistry::new()
  // Valid pointer
  let ptr = reg.create_pointer(reg.integer_type())
  assert_true(ptr is Some(_))
  // Valid: pointer to forward (self-referential)
  let fwd = reg.make_forward("SelfRef")
  let self_ptr = reg.create_pointer(fwd)
  assert_true(self_ptr is Some(_))
}

///|
test "create_proc validation" {
  let reg = TypeRegistry::new()
  // Valid proc
  let params = [reg.integer_type(), reg.real_type()]
  let proc1 = reg.create_proc(params, Some(reg.boolean_type()))
  assert_true(proc1 is Some(_))
  // Valid void proc
  let proc2 = reg.create_proc([], None)
  assert_true(proc2 is Some(_))
  // Invalid: forward type in params
  let fwd = reg.make_forward("ForwardType")
  let invalid_proc = reg.create_proc([fwd], None)
  assert_true(invalid_proc is None)
}
