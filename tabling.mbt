///|
/// 表驱动（tabling）支持：变体记忆化 + 全局 naive fixpoint。
///
/// 语义参考 trealla 的 `bif_tabling.c` 与 `library/tabling.pl`：
/// 以 `:- table p/1.` 标记谓词后，对 p 的每次调用按**变体**（变量重命名等价）
/// 建立表项。变体首次出现时，对**全部**表项反复批量求解直到一轮没有新增答案
/// （naive 求值 / 全局不动点），因此相互递归的变体也能同时到达完备状态；
/// 之后调用直接回放答案。答案以规范形式存储（变量按首次出现编号为
/// 0,1,2,...），回放时重命名为全新变量，每次解都是新鲜的。
///
/// Love 的表在**每个查询开始时清空**（见 love.mbt 的 solve），因此
/// assert/retract 对后续查询立即可见，不存在 trealla 那种"表未感知子句变化"
/// 的陈旧问题；abolish_table/1 等内置仅用于当前查询求解过程中的手动清除。
///
/// 限制：
/// - 表按谓词**名**生效（不区分元数）；`p//N` 视同 `p/(N+2)`（DCG 翻译后）；
/// - 变体/答案可无限增殖时（如 `p(X) :- p(f(X)).`、`p(X) :- q(Y).` 且 q 有
///   无限多答案）可能不终止；达到 `max_table_variants` / `max_table_answers`
///   上限时整个查询失败（抛 resource_error 球）。

///|
/// 变体表项：变体键 + 答案列表（答案以规范形式存储）。
/// 属于表驱动运行时内部结构，外部代码一般无需直接使用。
pub struct TableEntry {
  key : LoveTerm
  answers : Array[LoveTerm]
}

///|
/// 单谓词变体表项数上限（防止变体无限增殖挂起 REPL）。
let max_table_variants = 10000

///|
/// 单变体答案数上限（防止答案无限增殖挂起 REPL）。
let max_table_answers = 65536

///|
/// 变体规范化：把项中变量按首次出现顺序替换为 Var(0), Var(1), ...
/// 变体等价的项（如 p(X,X) 与 p(Y,Y)）得到相同的规范形式。
fn canonicalize(t : LoveTerm) -> LoveTerm {
  let m : Map[Int, Int] = Map([])
  let (out, _) = canon_go(t, m, 0)
  out
}

///|
/// 规范化遍历（返回新项与下一个变量编号）。
fn canon_go(t : LoveTerm, m : Map[Int, Int], next : Int) -> (LoveTerm, Int) {
  match t {
    LoveTerm::Var(id) =>
      match m.get(id) {
        Some(n) => (LoveTerm::Var(n), next)
        None => {
          m[id] = next
          (LoveTerm::Var(next), next + 1)
        }
      }
    LoveTerm::Struct(n, args) => {
      let new_args : Array[LoveTerm] = []
      let mut cur = next
      for a in args {
        let (na, n2) = canon_go(a, m, cur)
        new_args.push(na)
        cur = n2
      }
      (LoveTerm::Struct(n, new_args), cur)
    }
    LoveTerm::ListCons(h, tl) => {
      let (nh, n2) = canon_go(h, m, next)
      let (nt, n3) = canon_go(tl, m, n2)
      (LoveTerm::ListCons(nh, nt), n3)
    }
    other => (other, next)
  }
}

///|
/// 规范形式的结构相等（不涉及任何绑定环境）。
fn canon_equal(a : LoveTerm, b : LoveTerm) -> Bool {
  match (a, b) {
    (LoveTerm::Var(x), LoveTerm::Var(y)) => x == y
    (LoveTerm::Int(x), LoveTerm::Int(y)) => x == y
    (LoveTerm::Float(x), LoveTerm::Float(y)) => x == y
    (LoveTerm::Atom(x), LoveTerm::Atom(y)) => x == y
    (LoveTerm::Str(x), LoveTerm::Str(y)) => x == y
    (LoveTerm::Struct(n1, a1), LoveTerm::Struct(n2, a2)) => {
      if n1 != n2 || a1.length() != a2.length() {
        return false
      }
      for i in 0..<a1.length() {
        if !canon_equal(a1[i], a2[i]) {
          return false
        }
      }
      true
    }
    (LoveTerm::ListCons(h1, t1), LoveTerm::ListCons(h2, t2)) =>
      if canon_equal(h1, h2) {
        canon_equal(t1, t2)
      } else {
        false
      }
    (LoveTerm::ListNil, LoveTerm::ListNil) => true
    _ => false
  }
}

///|
/// 把规范形式的项（变量编号 0,1,2,...）重命名为引擎的全新变量。
/// 既用于回放答案，也用于从变体键重建批量求解目标。
fn rename_answer(engine : Engine, ans : LoveTerm) -> LoveTerm {
  let ids : Array[Int] = []
  collect_var_ids(ans, ids)
  let m : Map[Int, Int] = Map([])
  for i in 0..<ids.length() {
    m[ids[i]] = engine.var_counter + i
  }
  engine.var_counter += ids.length()
  replace_vars(ans, m)
}

///|
/// 表驱动调用：查找变体表项，新变体触发全局不动点求解，然后回放答案。
fn Engine::tabled_call(engine : Engine, goal : LoveTerm, f : Frame) -> Bool {
  let dgoal = engine.subst.deref(goal)
  let key = canonicalize(dgoal)
  let name = match dgoal {
    LoveTerm::Atom(n) => n
    LoveTerm::Struct(n, _) => n
    _ => return false
  }
  let arr = match engine.program.tables.get(name) {
    None => {
      let a : Array[TableEntry] = []
      engine.program.tables[name] = a
      a
    }
    Some(a) => a
  }
  let mut found : TableEntry? = None
  for e in arr {
    if canon_equal(e.key, key) {
      found = Some(e)
      break
    }
  }
  let mut created = false
  let entry = match found {
    Some(e) => e
    None => {
      if arr.length() >= max_table_variants {
        engine.uncaught = Some(
          LoveTerm::Struct("resource_error", [
            LoveTerm::Atom("table_variant_limit"),
          ]),
        )
        return false
      }
      let ne = { key, answers: [] }
      arr.push(ne)
      created = true
      ne
    }
  }
  if created {
    // 新变体：全局不动点求解（覆盖本查询内所有表项）
    if !engine.complete_all() {
      return false
    }
  }
  // 回放答案
  if entry.answers.is_empty() {
    return false
  }
  let base = engine.subst.trail.length()
  if !unify(engine.subst, dgoal, rename_answer(engine, entry.answers[0])) {
    if entry.answers.length() > 1 {
      engine.cps.push({
        trail_len: base,
        goals_snapshot: snapshot_goals(engine.goals),
        kind: CPKind::TableAnswer(1, entry.answers, dgoal, f.barrier),
      })
    }
    return false
  }
  if entry.answers.length() > 1 {
    engine.cps.push({
      trail_len: base,
      goals_snapshot: snapshot_goals(engine.goals),
      kind: CPKind::TableAnswer(1, entry.answers, dgoal, f.barrier),
    })
  }
  true
}

///|
/// 全局不动点：对所有表项反复批量求解，直到一轮没有新增答案。
/// 相互递归的变体在同一轮迭代中逐步补全，保证结束时所有表项完备。
/// 返回 false 表示某次批量求解遇到未捕获异常（已传播到外层）。
/// 用 Program.passing 作重入锁：批量求解的子引擎中创建的新变体不再嵌套
/// 触发新的不动点，而是由外层的不动点轮次统一补全。
fn Engine::complete_all(engine : Engine) -> Bool {
  if engine.program.passing[0] {
    return true
  }
  engine.program.passing[0] = true
  for ;; {
    let all : Array[TableEntry] = []
    for _, arr in engine.program.tables {
      for e in arr {
        all.push(e)
      }
    }
    let mut changed = false
    for e in all {
      match engine.batch_eval(e) {
        None => {
          engine.program.passing[0] = false
          return false
        }
        Some(added) => if added > 0 { changed = true }
      }
    }
    // 轮次中新增了表项（新变体尚未被本轮的收集覆盖）也算作变化，
    // 继续下一轮直到没有新答案也没有新表项
    if !changed {
      let mut total = 0
      for _, arr in engine.program.tables {
        total += arr.length()
      }
      if total <= all.length() {
        break
      }
    }
  }
  engine.program.passing[0] = false
  true
}

///|
/// 批量求解一个变体：用子引擎从变体键重建目标并求值，把新答案（规范形式、
/// 去重后）追加到表项。返回本次新增答案数；None 表示子引擎未捕获异常。
fn Engine::batch_eval(engine : Engine, entry : TableEntry) -> Int? {
  let goal = rename_answer(engine, entry.key)
  let sub = Engine::new(engine.program, engine.var_counter, goal)
  // 批量求解的目标帧就是变体目标本身：绕过表驱动拦截，直接按子句求值，
  // 否则会被表驱动回放拦截而永不求值子句。该标志随帧在回溯重推时保留。
  sub.goals[0] = { term: goal, ci: 0, barrier: 0, bypass: true }
  let mut added = 0
  for ;; {
    match sub.solve_next() {
      None => break
      Some(_) => {
        let inst = sub.subst.deref(goal)
        let can = canonicalize(inst)
        let mut dup = false
        for a in entry.answers {
          if canon_equal(a, can) {
            dup = true
            break
          }
        }
        if !dup {
          if entry.answers.length() >= max_table_answers {
            engine.uncaught = Some(
              LoveTerm::Struct("resource_error", [
                LoveTerm::Atom("table_answer_limit"),
              ]),
            )
            return None
          }
          entry.answers.push(can)
          added += 1
        }
      }
    }
  }
  engine.var_counter = if engine.var_counter > sub.var_counter {
    engine.var_counter
  } else {
    sub.var_counter
  }
  if sub.uncaught is Some(b) {
    engine.uncaught = Some(b)
    return None
  }
  Some(added)
}

///|
/// 提取 table 规格中的谓词名：`p/1`、`p//1`（DCG，按 p/(N+2) 处理）、
/// `(p/1, q/2)`、`[p/1, q/2]`。返回 false 表示规格非法。
fn collect_table_names(t : LoveTerm, out : Array[String]) -> Bool {
  match t {
    LoveTerm::Struct("/", [LoveTerm::Atom(nm), LoveTerm::Int(a)]) if a >= 0L => {
      out.push(nm)
      true
    }
    LoveTerm::Struct("//", [LoveTerm::Atom(nm), LoveTerm::Int(a)]) if a >= 0L => {
      out.push(nm)
      true
    }
    LoveTerm::Struct(",", [a, b]) =>
      collect_table_names(a, out) && collect_table_names(b, out)
    LoveTerm::ListNil => true
    LoveTerm::ListCons(h, tl) =>
      collect_table_names(h, out) && collect_table_names(tl, out)
    _ => false
  }
}
