///|
pub fn ascii_upper(s : StringView) -> String {
  String::from_iter(s.iter().map(Char::to_ascii_uppercase))
}
