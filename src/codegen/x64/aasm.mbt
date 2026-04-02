///|
pub(all) enum AsmListKind {
  Procedures
  Globals
  ConstData
  Imports
  Exports
  Rtti
  DwarfInfo
} derive(Show, Eq)

///|
pub(all) enum TaiKind {
  Align
  Section
  Comment
  Instruction
  Label
  Const
  Symbol
  SymbolEnd
  Marker
} derive(Show, Eq)

///|
pub struct Tai {
  kind : TaiKind
  opcode : String
  operands : Array[String]
  mut pos : @diag.Span?
}

///|
pub fn Tai::new(
  kind : TaiKind,
  opcode : String,
  operands : Array[String],
) -> Tai {
  { kind, opcode, operands, pos: None }
}

///|
pub fn Tai::with_span(self : Tai, pos : @diag.Span) -> Tai {
  self.pos = Some(pos)
  self
}

///|
pub struct AsmData {
  name : String
  mut procedures : Array[Tai]
  mut globals : Array[Tai]
  mut const_data : Array[Tai]
  mut imports : Array[Tai]
  mut exports : Array[Tai]
  mut rtti : Array[Tai]
  mut dwarf_info : Array[Tai]
  mut current : AsmListKind
}

///|
pub fn AsmData::new(name : String) -> AsmData {
  {
    name,
    procedures: [],
    globals: [],
    const_data: [],
    imports: [],
    exports: [],
    rtti: [],
    dwarf_info: [],
    current: Procedures,
  }
}

///|
pub fn AsmData::switch(self : AsmData, list : AsmListKind) -> Unit {
  self.current = list
}

///|
fn AsmData::current_list(self : AsmData) -> Array[Tai] {
  match self.current {
    Procedures => self.procedures
    Globals => self.globals
    ConstData => self.const_data
    Imports => self.imports
    Exports => self.exports
    Rtti => self.rtti
    DwarfInfo => self.dwarf_info
  }
}

///|
pub fn AsmData::emit(self : AsmData, instr : Tai) -> Unit {
  self.current_list().push(instr)
}

///|
pub fn AsmData::render(self : AsmData) -> String {
  let out = StringBuilder::new()
  fn emit_list(name : String, list : Array[Tai]) {
    if list.length() > 0 {
      out.write_string("[")
      out.write_string(name)
      out.write_string("]\n")
      for item in list {
        let line = match item.operands.length() {
          0 => item.opcode
          _ => {
            let ops = item.operands.join(", ")
            "\{item.opcode} \{ops}"
          }
        }
        out.write_string(line)
        out.write_string("\n")
      }
    }
  }

  emit_list("procedures", self.procedures)
  emit_list("globals", self.globals)
  emit_list("const", self.const_data)
  emit_list("imports", self.imports)
  emit_list("exports", self.exports)
  emit_list("rtti", self.rtti)
  emit_list("dwarf", self.dwarf_info)
  out.to_string()
}
