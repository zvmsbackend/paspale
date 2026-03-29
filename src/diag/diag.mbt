///|
pub struct Span {
  file_id : Int
  start : Int
  end_ : Int
}

///|
pub fn Span::new(file_id : Int, start : Int, end_ : Int) -> Span {
  { file_id, start, end_ }
}

///|
pub fn Span::len(self : Span) -> Int {
  if self.end_ > self.start {
    self.end_ - self.start
  } else {
    0
  }
}

///|
pub(all) enum Severity {
  Error
  Warning
  Note
}

///|
pub impl Show for Severity with output(self, logger) {
  logger.write_string(
    match self {
      Error => "error"
      Warning => "warning"
      Note => "note"
    },
  )
}

///|
pub(all) struct Label {
  span : Span
  message : String
  is_primary : Bool
}

///|
pub fn Label::primary(span : Span, message : String) -> Label {
  { span, message, is_primary: true }
}

///|
pub fn Label::secondary(span : Span, message : String) -> Label {
  { span, message, is_primary: false }
}

///|
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  message : String
  labels : Array[Label]
  notes : Array[String]
  helps : Array[String]
}

///|
pub fn Diagnostic::new(
  severity : Severity,
  code : String,
  message : String,
) -> Diagnostic {
  { severity, code, message, labels: [], notes: [], helps: [] }
}

///|
pub fn Diagnostic::with_label(self : Diagnostic, label : Label) -> Diagnostic {
  self.labels.push(label)
  self
}

///|
pub fn Diagnostic::with_note(self : Diagnostic, note : String) -> Diagnostic {
  self.notes.push(note)
  self
}

///|
pub fn Diagnostic::with_help(self : Diagnostic, help : String) -> Diagnostic {
  self.helps.push(help)
  self
}

///|
priv struct SourceFile {
  path : String
  line_starts : Array[Int]
  lines : Array[String]
  char_len : Int
}

///|
fn split_lines(content : String) -> (Array[Int], Array[String], Int) {
  let starts = [0]
  let lines = []
  let current = StringBuilder::new()
  for c in content; offset = 0 {
    if c == '\n' {
      lines.push(current.to_string())
      current.reset()
      starts.push(offset + 1)
    } else {
      current.write_char(c)
    }
    continue offset + 1
  } nobreak {
    lines.push(current.to_string())
    (starts, lines, offset)
  }
}

///|
struct SourceMap {
  files : Array[SourceFile]
}

///|
pub fn new_source_map() -> SourceMap {
  { files: [] }
}

///|
pub fn SourceMap::add_file(
  self : SourceMap,
  path : String,
  content : String,
) -> Int {
  let id = self.files.length()
  let (line_starts, lines, char_len) = split_lines(content)
  self.files.push({ path, line_starts, lines, char_len })
  id
}

///|
pub fn SourceMap::path(self : SourceMap, file_id : Int) -> String {
  self.files[file_id].path
}

///|
pub fn SourceMap::line_col(
  self : SourceMap,
  file_id : Int,
  offset : Int,
) -> (Int, Int) {
  let f = self.files[file_id]
  let clamped = offset.clamp(min=0, max=f.char_len)
  let starts = f.line_starts
  let mut line_idx = 0
  while line_idx + 1 < starts.length() && starts[line_idx + 1] <= clamped {
    line_idx = line_idx + 1
  }
  let line_start = starts[line_idx]
  let line_no = line_idx + 1
  let column_no = clamped - line_start + 1
  (line_no, column_no)
}

///|
pub fn SourceMap::line_text(
  self : SourceMap,
  file_id : Int,
  line_no : Int,
) -> String {
  if line_no <= 0 {
    ""
  } else {
    let idx = line_no - 1
    let lines = self.files[file_id].lines
    if idx >= lines.length() {
      ""
    } else {
      lines[idx]
    }
  }
}

///|
struct DiagSink {
  diagnostics : Array[Diagnostic]
}

///|
pub fn new_sink() -> DiagSink {
  { diagnostics: [] }
}

///|
pub fn DiagSink::push(self : DiagSink, d : Diagnostic) -> Unit {
  self.diagnostics.push(d)
}

///|
pub fn DiagSink::len(self : DiagSink) -> Int {
  self.diagnostics.length()
}

///|
pub fn DiagSink::has_error(self : DiagSink) -> Bool {
  for d in self.diagnostics {
    match d.severity {
      Error => return true
      _ => ()
    }
  }
  false
}

///|
pub fn DiagSink::all(self : DiagSink) -> Array[Diagnostic] {
  self.diagnostics
}

///|
fn Diagnostic::primary_label(self : Diagnostic) -> Label {
  if self.labels.length() == 0 {
    Label::primary(Span::new(0, 0, 0), "")
  } else {
    self.labels
    .iter()
    .find_first(lbl => lbl.is_primary)
    .unwrap_or(self.labels[0])
  }
}

///|
pub fn Diagnostic::render(self : Diagnostic, source_map : SourceMap) -> String {
  if self.labels.length() == 0 {
    if self.code == "" {
      return "\{self.severity}: \{self.message}"
    } else {
      return "\{self.severity}[\{self.code}]: \{self.message}"
    }
  }

  let out = StringBuilder::new()
  let lbl = self.primary_label()
  let (line_no, column_no) = source_map.line_col(
    lbl.span.file_id,
    lbl.span.start,
  )
  let path = source_map.path(lbl.span.file_id)
  if self.code == "" {
    out.write_string(
      "\{path}:\{line_no}:\{column_no}: \{self.severity}: \{self.message}",
    )
  } else {
    out.write_string(
      "\{path}:\{line_no}:\{column_no}: \{self.severity}[\{self.code}]: \{self.message}",
    )
  }

  let src = source_map.line_text(lbl.span.file_id, line_no)
  out.write_char('\n')
  out.write_string(src)

  let mut mark_len = lbl.span.len()
  if mark_len <= 0 {
    mark_len = 1
  }
  let marker = " ".repeat(column_no - 1) + "^" + "~".repeat(mark_len - 1)
  out.write_char('\n')
  out.write_string(marker)
  if lbl.message != "" {
    out.write_char(' ')
    out.write_string(lbl.message)
  }

  for note in self.notes {
    out.write_string("\nnote: ")
    out.write_string(note)
  }
  for help in self.helps {
    out.write_string("\nhelp: ")
    out.write_string(help)
  }
  out.to_string()
}

///|
pub fn render_all(source_map : SourceMap, sink : DiagSink) -> String {
  let out = StringBuilder::new()
  let ds = sink.all()
  for i in 0..<ds.length() {
    if i > 0 {
      out.write_object("\n\n")
    }
    out.write_string(ds[i].render(source_map))
  }
  out.to_string()
}
