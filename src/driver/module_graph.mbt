///|
fn norm(name : String) -> String {
  @common.ascii_upper(name)
}

///|
pub struct UnitNode {
  name : String
  uses : Array[String]
}

///|
pub struct ModuleGraph {
  nodes : Map[String, UnitNode]
  keys : Array[String]
}

///|
fn unit_name(cu : @ast.Spanned[@ast.CompilationUnit]) -> String {
  match cu.node {
    ProgramUnit(p) => p.name
    UnitModule(u) => u.name
    LibraryUnit(l) => l.name
  }
}

///|
fn unit_uses(cu : @ast.Spanned[@ast.CompilationUnit]) -> Array[String] {
  match cu.node {
    ProgramUnit(p) => p.uses.map(u => u.node.unit_name)
    UnitModule(u) =>
      u.interface_uses.map(x => x.node.unit_name) +
      u.implementation_uses.map(x => x.node.unit_name)
    LibraryUnit(l) => l.uses.map(u => u.node.unit_name)
  }
}

///|
pub fn collect_module_graph(
  units : Array[@ast.Spanned[@ast.CompilationUnit]],
) -> ModuleGraph {
  let nodes = {}
  let keys = []
  for cu in units {
    let name = unit_name(cu)
    let uses = unit_uses(cu)
    let key = norm(name)
    nodes[key] = { name, uses }
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  { nodes, keys }
}

///|
pub fn ModuleGraph::direct_deps(
  self : ModuleGraph,
  name : String,
) -> Array[String] {
  match self.nodes.get(norm(name)) {
    Some(n) => n.uses
    None => []
  }
}

///|
pub fn ModuleGraph::topo_order(self : ModuleGraph) -> Array[String] {
  let indegree : Map[String, Int] = {}
  let reverse_edges : Map[String, Array[String]] = {}

  for k in self.keys {
    indegree[k] = 0
    reverse_edges[k] = []
  }

  for k in self.keys {
    let node = self.nodes[k]
    let seen = Set::new()
    for dep_name in node.uses {
      let dep = norm(dep_name)
      if dep == k || !self.nodes.contains(dep) || seen.contains(dep) {
        continue
      }
      seen.add(dep)
      indegree[k] = indegree.get_or_default(k, 0) + 1
      let outs = reverse_edges.get_or_default(dep, [])
      outs.push(k)
      reverse_edges[dep] = outs
    }
  }

  let queue = @queue.from_iter(
    self.keys.iter().filter(k => indegree.get_or_default(k, 0) == 0),
  )

  let ordered = []
  while queue.pop() is Some(curr) {
    ordered.push(self.nodes[curr].name)
    let outs = reverse_edges.get_or_default(curr, [])
    for next in outs {
      let d = indegree.get_or_default(next, 0) - 1
      indegree[next] = d
      if d == 0 {
        queue.push(next)
      }
    }
  }

  if ordered.length() == self.nodes.length() {
    return ordered
  }

  // Cycle fallback: append unresolved nodes in stable name order.
  let unresolved = indegree
    .keys()
    .filter(k => indegree.get_or_default(k, 0) > 0)
    .collect()
  unresolved.sort()
  unresolved.map(k => self.nodes[k].name)
}
