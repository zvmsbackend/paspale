///|
/// Internal reference to a type in the registry
pub struct TypeRef {
  id : Int
} derive(Show, Eq)

///|
/// Built-in types
pub(all) enum BuiltinType {
  Void
  Integer
  Real
  Boolean
  Char
  String
} derive(Show, Eq)

///|
/// Field definition for record types
pub(all) struct FieldDef {
  name : String
  ty : TypeRef
} derive(Show, Eq)

///|
/// Type definition
pub(all) enum Type {
  /// Built-in types: integer, real, boolean, char, string
  Builtin(BuiltinType)
  /// Pointer type: ^T
  Pointer(TypeRef)
  /// Static array: array[low..high] of T (index_type, low, high, elem_type)
  /// Bounds are fixed at compile time, index can be any ordinal type
  StaticArray(TypeRef, Int, Int, TypeRef)
  /// Open array: array of T (for procedure parameters)
  /// Accepts any size array, index always starts at 0
  OpenArray(TypeRef)
  /// Dynamic array: array of T (heap allocated, resizable)
  /// Index always starts at 0, size determined at runtime
  DynamicArray(TypeRef)
  /// Record type: record fields with field definitions
  Record(Array[FieldDef])
  /// Enum type: (A, B, C)
  Enum(Array[String])
  /// Subrange type: low..high of base type
  Subrange(TypeRef, Int, Int)
  /// Set type: set of T
  Set(TypeRef)
  /// Procedure type: (params...) -> result (None for void)
  Proc(Array[TypeRef], TypeRef?)
  /// Forward declaration (unresolved)
  Forward(String)
  /// Error type (for error recovery)
  Error
} derive(Show, Eq)

///|
/// Registry of all types in a compilation unit
struct TypeRegistry {
  types : Array[Type]
  unresolved_forwards : Map[String, Array[TypeRef]]
  builtin_void : TypeRef
  builtin_integer : TypeRef
  builtin_real : TypeRef
  builtin_boolean : TypeRef
  builtin_char : TypeRef
  builtin_string : TypeRef
}

///|
/// Create a new type registry with built-in types
pub fn TypeRegistry::new() -> TypeRegistry {
  let types = []
  let void_id = types.length()
  types.push(Builtin(Void))
  let integer_id = types.length()
  types.push(Builtin(Integer))
  let real_id = types.length()
  types.push(Builtin(Real))
  let boolean_id = types.length()
  types.push(Builtin(Boolean))
  let char_id = types.length()
  types.push(Builtin(Char))
  let string_id = types.length()
  types.push(Builtin(String))
  {
    types,
    unresolved_forwards: {},
    builtin_void: { id: void_id },
    builtin_integer: { id: integer_id },
    builtin_real: { id: real_id },
    builtin_boolean: { id: boolean_id },
    builtin_char: { id: char_id },
    builtin_string: { id: string_id },
  }
}

///|
/// Register a new type and return its reference
pub fn TypeRegistry::register(self : TypeRegistry, ty : Type) -> TypeRef {
  let id = self.types.length()
  self.types.push(ty)
  { id, }
}

///|
/// Get a type by reference
pub fn TypeRegistry::get(self : TypeRegistry, tref : TypeRef) -> Type {
  if tref.id < 0 || tref.id >= self.types.length() {
    Error
  } else {
    self.types[tref.id]
  }
}

///|
/// Update a type by reference (for forward declarations)
pub fn TypeRegistry::set(
  self : TypeRegistry,
  tref : TypeRef,
  ty : Type,
) -> Unit {
  if tref.id >= 0 && tref.id < self.types.length() {
    self.types[tref.id] = ty
  }
}

///|
/// Create a pointer type
pub fn TypeRegistry::make_pointer(
  self : TypeRegistry,
  base : TypeRef,
) -> TypeRef {
  self.register(Pointer(base))
}

///|
/// Create a static array type: array[low..high] of elem_type
/// index_type should be an ordinal type (integer, char, enum, subrange)
pub fn TypeRegistry::make_static_array(
  self : TypeRegistry,
  index_type : TypeRef,
  low : Int,
  high : Int,
  elem_type : TypeRef,
) -> TypeRef {
  self.register(StaticArray(index_type, low, high, elem_type))
}

///|
/// Create an open array type (for procedure parameters)
pub fn TypeRegistry::make_open_array(
  self : TypeRegistry,
  elem_type : TypeRef,
) -> TypeRef {
  self.register(OpenArray(elem_type))
}

///|
/// Create a dynamic array type
pub fn TypeRegistry::make_dynamic_array(
  self : TypeRegistry,
  elem_type : TypeRef,
) -> TypeRef {
  self.register(DynamicArray(elem_type))
}

///|
/// Create an enum type
pub fn TypeRegistry::make_enum(
  self : TypeRegistry,
  names : Array[String],
) -> TypeRef {
  self.register(Enum(names))
}

///|
/// Create a record type with fields
pub fn TypeRegistry::make_record(
  self : TypeRegistry,
  fields : Array[FieldDef],
) -> TypeRef {
  self.register(Record(fields))
}

///|
/// Create a subrange type
pub fn TypeRegistry::make_subrange(
  self : TypeRegistry,
  base : TypeRef,
  low : Int,
  high : Int,
) -> TypeRef {
  self.register(Subrange(base, low, high))
}

///|
/// Create a set type
pub fn TypeRegistry::make_set(self : TypeRegistry, elem : TypeRef) -> TypeRef {
  self.register(Set(elem))
}

///|
/// Create a procedure type
pub fn TypeRegistry::make_proc(
  self : TypeRegistry,
  params : Array[TypeRef],
  result : TypeRef?,
) -> TypeRef {
  self.register(Proc(params, result))
}

///|
/// Check if a type reference is valid (resolved and not error)
pub fn TypeRegistry::is_valid(self : TypeRegistry, tref : TypeRef) -> Bool {
  !(self.get(tref) is (Error | Forward(_)))
}

///|
/// Check if an array has unique names
fn has_unique_names(names : Array[String]) -> Bool {
  let seen = Set::new()
  for name in names {
    if seen.contains(name) {
      return false
    }
    seen.add(name)
  }
  true
}

///|
/// Check if field names are unique
fn has_unique_field_names(fields : Array[FieldDef]) -> Bool {
  let seen = Set::new()
  for field in fields {
    if seen.contains(field.name) {
      return false
    }
    seen.add(field.name)
  }
  true
}

///|
/// Create a subrange type with validation
/// Returns None if: base is not ordinal, or low > high
pub fn TypeRegistry::create_subrange(
  self : TypeRegistry,
  base : TypeRef,
  low : Int,
  high : Int,
) -> TypeRef? {
  if !self.is_ordinal(base) {
    return None
  }
  if low > high {
    return None
  }
  Some(self.register(Subrange(base, low, high)))
}

///|
/// Create an enum type with validation
/// Returns None if: names is empty, or names are not unique
pub fn TypeRegistry::create_enum(
  self : TypeRegistry,
  names : Array[String],
) -> TypeRef? {
  if names.length() == 0 {
    return None
  }
  if !has_unique_names(names) {
    return None
  }
  Some(self.register(Enum(names)))
}

///|
/// Create a static array type with validation
/// Returns None if: index_type is not ordinal, low > high, elem_type is invalid
pub fn TypeRegistry::create_static_array(
  self : TypeRegistry,
  index_type : TypeRef,
  low : Int,
  high : Int,
  elem_type : TypeRef,
) -> TypeRef? {
  if !self.is_ordinal(index_type) {
    return None
  }
  if low > high {
    return None
  }
  if !self.is_valid(elem_type) {
    return None
  }
  Some(self.register(StaticArray(index_type, low, high, elem_type)))
}

///|
/// Create an open array type with validation
/// Returns None if: elem_type is invalid (unresolved or error)
pub fn TypeRegistry::create_open_array(
  self : TypeRegistry,
  elem_type : TypeRef,
) -> TypeRef? {
  if !self.is_valid(elem_type) {
    return None
  }
  Some(self.register(OpenArray(elem_type)))
}

///|
/// Create a dynamic array type with validation
/// Returns None if: elem_type is invalid (unresolved or error)
pub fn TypeRegistry::create_dynamic_array(
  self : TypeRegistry,
  elem_type : TypeRef,
) -> TypeRef? {
  if !self.is_valid(elem_type) {
    return None
  }
  Some(self.register(DynamicArray(elem_type)))
}

///|
/// Create a set type with validation
/// Returns None if: elem_type is not ordinal
pub fn TypeRegistry::create_set(
  self : TypeRegistry,
  elem : TypeRef,
) -> TypeRef? {
  if !self.is_ordinal(elem) {
    return None
  }
  Some(self.register(Set(elem)))
}

///|
/// Create a record type with validation
/// Returns None if: field names are not unique, or any field type is invalid
pub fn TypeRegistry::create_record(
  self : TypeRegistry,
  fields : Array[FieldDef],
) -> TypeRef? {
  if !has_unique_field_names(fields) {
    return None
  }
  for field in fields {
    if !self.is_valid(field.ty) {
      return None
    }
  }
  Some(self.register(Record(fields)))
}

///|
/// Create a pointer type with validation
/// Returns None if: base type is invalid
/// Note: forward types are allowed for self-referential types
pub fn TypeRegistry::create_pointer(
  self : TypeRegistry,
  base : TypeRef,
) -> TypeRef? {
  let ty = self.get(base)
  match ty {
    Error => None
    _ => Some(self.register(Pointer(base)))
  }
}

///|
/// Create a procedure type with validation
/// Returns None if: any param type or result type is invalid
pub fn TypeRegistry::create_proc(
  self : TypeRegistry,
  params : Array[TypeRef],
  result : TypeRef?,
) -> TypeRef? {
  for param in params {
    if !self.is_valid(param) {
      return None
    }
  }
  if result is Some(r) && !self.is_valid(r) {
    return None
  }
  Some(self.register(Proc(params, result)))
}

///|
/// Create a forward declaration placeholder
pub fn TypeRegistry::make_forward(
  self : TypeRegistry,
  name : String,
) -> TypeRef {
  let tref = self.register(Forward(name))
  if self.unresolved_forwards.get(name) is Some(refs) {
    refs.push(tref)
  } else {
    self.unresolved_forwards.set(name, [tref])
  }
  tref
}

///|
/// Check if a type is resolved (not Forward)
pub fn TypeRegistry::is_resolved(self : TypeRegistry, tref : TypeRef) -> Bool {
  !(self.get(tref) is Forward(_))
}

///|
/// Resolve all forward declarations with the given name
/// Returns the number of declarations resolved
pub fn TypeRegistry::resolve_forward(
  self : TypeRegistry,
  name : String,
  ty : Type,
) -> Int {
  let mut count = 0
  for i, ty_ in self.types {
    match ty_ {
      Forward(n) if n == name => {
        self.types[i] = ty
        count = count + 1
      }
      _ => ()
    }
  }
  self.unresolved_forwards.remove(name)
  count
}

///|
/// Check if there are any unresolved forward declarations
pub fn TypeRegistry::has_unresolved(self : TypeRegistry) -> Bool {
  self.unresolved_forwards.length() > 0
}

///|
/// Get all unresolved forward declaration names
pub fn TypeRegistry::unresolved_names(self : TypeRegistry) -> Array[String] {
  self.unresolved_forwards.keys().to_array()
}

///|
/// Check if two type refs are equal (by id)
pub fn TypeRef::eq(self : TypeRef, other : TypeRef) -> Bool {
  self.id == other.id
}

///|
/// Check if a type is a numeric type (integer or real)
pub fn TypeRegistry::is_numeric(self : TypeRegistry, tref : TypeRef) -> Bool {
  self.get(tref) is Builtin(Integer | Real)
}

///|
/// Check if a type is an ordinal type (integer, boolean, char, enum, subrange)
pub fn TypeRegistry::is_ordinal(self : TypeRegistry, tref : TypeRef) -> Bool {
  self.get(tref) is (Builtin(Integer | Boolean | Char) | Enum(_) | Subrange(_))
}

///|
/// Check if a type is a boolean type
pub fn TypeRegistry::is_boolean(self : TypeRegistry, tref : TypeRef) -> Bool {
  self.get(tref) is Builtin(Boolean)
}

///|
/// Check if a type is a string type
pub fn TypeRegistry::is_string(self : TypeRegistry, tref : TypeRef) -> Bool {
  self.get(tref) is Builtin(String)
}

///|
/// Check if a type is an array type (any kind)
pub fn TypeRegistry::is_array(self : TypeRegistry, tref : TypeRef) -> Bool {
  self.get(tref) is (StaticArray(_, _, _, _) | OpenArray(_) | DynamicArray(_))
}

///|
/// Check if a type is a static array type
pub fn TypeRegistry::is_static_array(
  self : TypeRegistry,
  tref : TypeRef,
) -> Bool {
  self.get(tref) is StaticArray(_)
}

///|
/// Check if a type is an open array type
pub fn TypeRegistry::is_open_array(self : TypeRegistry, tref : TypeRef) -> Bool {
  self.get(tref) is OpenArray(_)
}

///|
/// Check if a type is a dynamic array type
pub fn TypeRegistry::is_dynamic_array(
  self : TypeRegistry,
  tref : TypeRef,
) -> Bool {
  self.get(tref) is DynamicArray(_)
}

///|
/// Check if a type is a record type
pub fn TypeRegistry::is_record(self : TypeRegistry, tref : TypeRef) -> Bool {
  self.get(tref) is Record(_)
}

///|
/// Get the element type of an array type
/// Returns None if not an array type
pub fn TypeRegistry::array_element_type(
  self : TypeRegistry,
  tref : TypeRef,
) -> TypeRef? {
  match self.get(tref) {
    StaticArray(_, _, _, elem) => Some(elem)
    OpenArray(elem) => Some(elem)
    DynamicArray(elem) => Some(elem)
    _ => None
  }
}

///|
/// Get the bounds of a static array type
/// Returns None if not a static array
pub fn TypeRegistry::static_array_bounds(
  self : TypeRegistry,
  tref : TypeRef,
) -> (Int, Int)? {
  match self.get(tref) {
    StaticArray(_, low, high, _) => Some((low, high))
    _ => None
  }
}

///|
/// Get the fields of a record type
/// Returns None if not a record type
pub fn TypeRegistry::record_fields(
  self : TypeRegistry,
  tref : TypeRef,
) -> Array[FieldDef]? {
  match self.get(tref) {
    Record(fields) => Some(fields)
    _ => None
  }
}

///|
/// Check if source type can be assigned to target type
pub fn TypeRegistry::is_assignable_from(
  self : TypeRegistry,
  target : TypeRef,
  source : TypeRef,
) -> Bool {
  let target_ty = self.get(target)
  let source_ty = self.get(source)

  // Same type (nominal equality)
  if target.id == source.id {
    return true
  }

  match (target_ty, source_ty) {
    // Integer compatibility: integer can be assigned to subrange
    (Builtin(Integer), Builtin(Integer)) => true
    (Builtin(Integer), Subrange(base, _, _)) =>
      self.get(base) is Builtin(Integer)
    (Subrange(base, _, _), Builtin(Integer)) =>
      self.get(base) is Builtin(Integer)
    (Subrange(t_base, _, _), Subrange(s_base, _, _)) => t_base.id == s_base.id

    // Real compatibility: integer can be assigned to real
    (Builtin(Real), Builtin(Integer | Real)) => true
    (Builtin(Real), Subrange(base, _, _)) => self.get(base) is Builtin(Integer)

    // String compatibility
    (Builtin(String), Builtin(String)) => true

    // Boolean compatibility
    (Builtin(Boolean), Builtin(Boolean)) => true

    // Char compatibility
    (Builtin(Char), Builtin(Char)) => true

    // Pointer compatibility
    (Pointer(t), Pointer(s)) => self.is_assignable_from(t, s)

    // Static array to open array (parameter passing)
    (OpenArray(t_elem), StaticArray(_, _, _, s_elem)) =>
      self.is_assignable_from(t_elem, s_elem)
    (OpenArray(t_elem), DynamicArray(s_elem)) =>
      self.is_assignable_from(t_elem, s_elem)
    (OpenArray(t_elem), OpenArray(s_elem)) =>
      self.is_assignable_from(t_elem, s_elem)

    // Dynamic array to dynamic array (same element type)
    (DynamicArray(t_elem), DynamicArray(s_elem)) => t_elem.id == s_elem.id

    // Static array to static array (same type)
    (
      StaticArray(t_idx, t_low, t_high, t_elem),
      StaticArray(s_idx, s_low, s_high, s_elem),
    ) =>
      t_idx.id == s_idx.id &&
      t_low == s_low &&
      t_high == s_high &&
      t_elem.id == s_elem.id

    // Error type accepts anything (error recovery)
    (Error, _) => true
    (_, Error) => true
    _ => false
  }
}

///|
/// Check if two types are compatible for comparison
pub fn TypeRegistry::is_compatible_with(
  self : TypeRegistry,
  t1 : TypeRef,
  t2 : TypeRef,
) -> Bool {
  let ty1 = self.get(t1)
  let ty2 = self.get(t2)

  // Same type
  if t1.id == t2.id {
    return true
  }

  match (ty1, ty2) {
    // Numeric types are compatible
    (Builtin(Integer | Real), Builtin(Integer | Real)) => true

    // Ordinal types of same base
    (Builtin(Integer), Subrange(base, _, _)) =>
      self.get(base) is Builtin(Integer)
    (Subrange(base, _, _), Builtin(Integer)) =>
      self.get(base) is Builtin(Integer)

    // String types
    (Builtin(String), Builtin(String)) => true

    // Boolean types
    (Builtin(Boolean), Builtin(Boolean)) => true

    // Char types
    (Builtin(Char), Builtin(Char)) => true

    // Pointer types
    (Pointer(a), Pointer(b)) => self.is_compatible_with(a, b)

    // Array types
    (StaticArray(_, _, _, e1), StaticArray(_, _, _, e2)) =>
      self.is_compatible_with(e1, e2)
    (OpenArray(e1), OpenArray(e2)) => self.is_compatible_with(e1, e2)
    (DynamicArray(e1), DynamicArray(e2)) => self.is_compatible_with(e1, e2)

    // Error recovery
    (Error, _) => true
    (_, Error) => true
    _ => false
  }
}

///|
/// Get built-in type refs
pub fn TypeRegistry::void_type(self : TypeRegistry) -> TypeRef {
  self.builtin_void
}

///|
pub fn TypeRegistry::integer_type(self : TypeRegistry) -> TypeRef {
  self.builtin_integer
}

///|
pub fn TypeRegistry::real_type(self : TypeRegistry) -> TypeRef {
  self.builtin_real
}

///|
pub fn TypeRegistry::boolean_type(self : TypeRegistry) -> TypeRef {
  self.builtin_boolean
}

///|
pub fn TypeRegistry::char_type(self : TypeRegistry) -> TypeRef {
  self.builtin_char
}

///|
pub fn TypeRegistry::string_type(self : TypeRegistry) -> TypeRef {
  self.builtin_string
}
