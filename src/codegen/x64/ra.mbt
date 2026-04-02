///|
struct LiveInst {
  uses : Array[Int]
  defs : Array[Int]
}

///|
pub fn LiveInst::new(uses : Array[Int], defs : Array[Int]) -> LiveInst {
  { uses, defs }
}

///|
pub struct AllocationPlan {
  colors : Array[Int?]
  adjacency : Array[Array[Int]]
}

///|
pub struct PhysicalAllocation {
  reg_of_vreg : Map[Int, String]
  spill_offset_of_vreg : Map[Int, Int]
  stack_size : Int
}

///|
fn add_unique(xs : Array[Int], x : Int) -> Unit {
  if !xs.contains(x) {
    xs.push(x)
  }
}

///|
fn max_vreg(insts : Array[LiveInst]) -> Int {
  insts
  .iter()
  .flat_map(inst => inst.uses.iter() + inst.defs.iter())
  .maximum()
  .unwrap()
}

///|
fn overlap(a0 : Int, a1 : Int, b0 : Int, b1 : Int) -> Bool {
  a0 <= b1 && b0 <= a1
}

///|
fn build_interference(
  insts : Array[LiveInst],
  count : Int,
) -> Array[Array[Int]] {
  let first = [-1].repeat(count)
  let last = [-1].repeat(count)
  for idx, inst in insts {
    for u in inst.uses {
      if first[u] == -1 {
        first[u] = idx
      }
      last[u] = idx
    }
    for d in inst.defs {
      if first[d] == -1 {
        first[d] = idx
      }
      last[d] = idx
    }
  }

  let adj = [[]].repeat(count)
  for a in 0..<count {
    if first[a] == -1 {
      continue
    }
    for b in (a + 1)..<count {
      if first[b] == -1 {
        continue
      }
      if overlap(first[a], last[a], first[b], last[b]) {
        add_unique(adj[a], b)
        add_unique(adj[b], a)
      }
    }
  }
  adj
}

///|
pub fn allocate_plan(insts : Array[LiveInst], k : Int) -> AllocationPlan {
  let vreg_max = max_vreg(insts)
  if vreg_max < 0 {
    return { colors: [], adjacency: [] }
  }
  let count = vreg_max + 1
  let adjacency = build_interference(insts, count)

  let colors = [None].repeat(count)
  let processed = [false].repeat(count)

  for _ in 0..<count {
    let mut best_v = -1
    let mut best_deg = -1
    for v in 0..<count {
      if processed[v] {
        continue
      }
      let deg = adjacency[v].length()
      if deg > best_deg {
        best_deg = deg
        best_v = v
      }
    }
    if best_v == -1 {
      break
    }

    let used = [false].repeat(k)
    for n in adjacency[best_v] {
      if colors[n] is Some(c) && c >= 0 && c < k {
        used[c] = true
      }
    }

    let picked = (0).until(k).find_first(c => !used[c])
    colors[best_v] = picked
    processed[best_v] = true
  }

  { colors, adjacency }
}

///|
pub fn allocate_physical(
  insts : Array[LiveInst],
  regs : Array[String],
) -> PhysicalAllocation {
  let plan = allocate_plan(insts, regs.length())
  let reg_of_vreg = {}
  let spill_offset_of_vreg = {}
  let mut next_spill = 8

  for v, color in plan.colors {
    match color {
      Some(c) if c >= 0 && c < regs.length() => reg_of_vreg.set(v, regs[c])
      _ => {
        spill_offset_of_vreg.set(v, next_spill)
        next_spill = next_spill + 8
      }
    }
  }

  { reg_of_vreg, spill_offset_of_vreg, stack_size: next_spill - 8 }
}
