///|
pub(all) enum IrStage {
  Parsed
  Resolved
  FirstPassed
  SecondPassed
} derive(Show, Eq)

///|
pub struct ProcInfo {
  proc_sym : Int
  parent_proc : Int?
  entry_pos : @diag.Span
  exit_pos : @diag.Span
  flags : Int
  para_stack_size : Int
  temp_start : Int
  curr_break_label : String?
  curr_continue_label : String?
  curr_exit_label : String
}

///|
pub fn ProcInfo::new(
  proc_sym : Int,
  entry_pos : @diag.Span,
  exit_pos : @diag.Span,
) -> ProcInfo {
  {
    proc_sym,
    parent_proc: None,
    entry_pos,
    exit_pos,
    flags: 0,
    para_stack_size: 0,
    temp_start: 0,
    curr_break_label: None,
    curr_continue_label: None,
    curr_exit_label: "L.exit",
  }
}

///|
pub struct OptInfo {
  index : Int
  def_set : Set[Int]
  use_set : Set[Int]
  life_set : Set[Int]
  defsum_set : Set[Int]
}

///|
pub fn OptInfo::new(index : Int) -> OptInfo {
  {
    index,
    def_set: Set::new(),
    use_set: Set::new(),
    life_set: Set::new(),
    defsum_set: Set::new(),
  }
}

///|
pub struct ModuleIr {
  stages : Array[IrStage]
  procs : Array[ProcInfo]
  opts : Array[OptInfo]
  mut first_pass : FirstPassReport?
}

///|
pub fn ModuleIr::new() -> ModuleIr {
  { stages: [], procs: [], opts: [], first_pass: None }
}

///|
pub fn ModuleIr::mark_stage(self : ModuleIr, stage : IrStage) -> Unit {
  if !self.stages.iter().any(s => s == stage) {
    self.stages.push(stage)
  }
}

///|
pub fn ModuleIr::reached(self : ModuleIr, stage : IrStage) -> Bool {
  self.stages.iter().any(s => s == stage)
}

///|
pub fn ModuleIr::add_proc(self : ModuleIr, proc_info : ProcInfo) -> Unit {
  self.procs.push(proc_info)
}

///|
pub fn ModuleIr::add_opt(self : ModuleIr, opt_info : OptInfo) -> Unit {
  self.opts.push(opt_info)
}

///|
pub struct FirstPassReport {
  mut folded_unary : Int
  mut folded_binary : Int
}

///|
pub fn FirstPassReport::new() -> FirstPassReport {
  { folded_unary: 0, folded_binary: 0 }
}

///|
pub fn ModuleIr::set_first_pass_report(
  self : ModuleIr,
  report : FirstPassReport,
) -> Unit {
  self.first_pass = Some(report)
}
