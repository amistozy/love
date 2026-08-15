///|
/// Love 语言的公开 API 门面。
///
/// 快速上手：
/// ```mbt nocheck
/// let program = parse_program("likes(alice, bob). likes(bob, carol).")
/// let q = parse_query("likes(alice, X).")
/// for sol in solve_all(program, q) {
///   println(format_term(sol.query))
/// }
/// ```

///|
/// 一个解：解引用后的查询项 + 查询变量的绑定 + 是否还有未耗尽的 choice point。
pub struct Solution {
  query : LoveTerm
  bindings : Map[Int, LoveTerm]
  /// 是否可能还有更多解（供 REPL 判断答案后跟 `;` 还是 `.`）
  more : Bool
}

///|
/// 惰性求解：每次迭代推进到下一个解。
pub fn solve(program : Program, query : LoveTerm) -> Iter[Solution] {
  // 每个查询开始时清空表驱动运行时表：assert/retract 对后续查询立即可见，
  // 且本查询的全局不动点求解总是从干净状态开始。
  for k in program.tables.keys() {
    program.tables.remove(k)
  }
  let var_ids = query_var_ids(query)
  let start = max_var_id(query) + 1
  let engine = Engine::new(program, start, query)
  Iter::new(fn() {
    match engine.solve_next() {
      None => None
      Some(q) => {
        let bindings : Map[Int, LoveTerm] = Map([])
        for id in var_ids {
          bindings[id] = engine.subst.deref(LoveTerm::Var(id))
        }
        Some({ query: q, bindings, more: engine.has_pending() })
      }
    }
  })
}

///|
/// 收集全部解。
pub fn solve_all(program : Program, query : LoveTerm) -> Array[Solution] {
  Array::from_iter(solve(program, query))
}

///|
/// 收集全部解（仅解引用后的查询项，便于测试断言）。
pub fn solve_terms(program : Program, query : LoveTerm) -> Array[LoveTerm] {
  let out : Array[LoveTerm] = []
  for sol in solve(program, query) {
    out.push(sol.query)
  }
  out
}

///|
/// 查询中出现的变量 id（按首次出现顺序、去重）。
pub fn query_var_ids(query : LoveTerm) -> Array[Int] {
  let out : Array[Int] = []
  collect_var_ids(query, out)
  out
}

///|
fn collect_var_ids(t : LoveTerm, out : Array[Int]) -> Unit {
  match t {
    LoveTerm::Var(id) => {
      for existing in out {
        if existing == id {
          return
        }
      }
      out.push(id)
    }
    LoveTerm::Struct(_, args) =>
      for a in args {
        collect_var_ids(a, out)
      }
    LoveTerm::ListCons(h, tl) => {
      collect_var_ids(h, out)
      collect_var_ids(tl, out)
    }
    _ => ()
  }
}

///|
/// 查询中最大的变量 id（求解器变量计数器起点用）。
fn max_var_id(t : LoveTerm) -> Int {
  match t {
    LoveTerm::Var(id) => id
    LoveTerm::Struct(_, args) => {
      let mut m = -1
      for a in args {
        let v = max_var_id(a)
        if v > m {
          m = v
        }
      }
      m
    }
    LoveTerm::ListCons(h, tl) => {
      let a = max_var_id(h)
      let b = max_var_id(tl)
      if a > b {
        a
      } else {
        b
      }
    }
    _ => -1
  }
}

///|
/// 解析查询并运行，返回全部解（便捷函数）。
pub fn run_query(
  program : Program,
  query_src : String,
) -> Array[Solution] raise LoveError {
  let q = parse_query(query_src)
  solve_all(program, q)
}

///|
/// 加载程序并执行其中的指令（:- Goal.），指令失败打印警告。
pub fn load_directives(program : Program) -> Unit {
  for d in program.directives {
    if solve_terms(program, d).is_empty() {
      println("warning: directive failed: \{format_term(d)}")
    }
  }
}

///|
/// 显示一个解：`X = value`，无变量且成功时显示 true。
pub fn format_solution(sol : Solution, names : Map[Int, String]) -> String {
  if sol.bindings.is_empty() {
    return "true"
  }
  let parts : Array[String] = []
  for id, v in sol.bindings {
    let nm = match names.get(id) {
      None => "_\{id}"
      Some(n) => n
    }
    parts.push("\{nm} = \{format_term(v)}")
  }
  parts.join(", ")
}
