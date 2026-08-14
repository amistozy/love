///|
/// 目标帧：待求解目标 + 子句游标 + cut 屏障。
priv struct Frame {
  term : LoveTerm
  ci : Int
  barrier : Int
}

///|
/// choice point 种类。
priv enum CPKind {
  /// 谓词调用：回溯时尝试下一条子句
  NextClause(LoveTerm, Int, Int)
  /// 控制结构：回溯时压入指定目标
  PushTerm(LoveTerm, Int)
  /// clause/2：扫描子句列表
  ClauseScan(Int, LoveTerm, LoveTerm, Array[Clause])
  /// between/3：枚举整数
  EnumInt(Int64, Int64, LoveTerm)
}

///|
priv struct ChoicePoint {
  trail_len : Int
  /// 创建时的完整目标栈快照（回溯时整体恢复，保证被控制结构消费的帧可复原）
  goals_snapshot : Array[Frame]
  kind : CPKind
}

///|
/// 拷贝目标栈。
fn snapshot_goals(goals : Array[Frame]) -> Array[Frame] {
  let out : Array[Frame] = []
  for f in goals {
    out.push(f)
  }
  out
}

///|
/// 变量重命名（两遍、无闭包可变捕获）：
/// 1. 收集子句中所有不同变量 id（首次出现顺序）
/// 2. 建立 old->new 映射（new 从 engine.var_counter 起递增）
/// 3. 纯函数替换头与体中的变量
fn fresh_clause_vars(engine : Engine, clause : Clause) -> (LoveTerm, LoveTerm) {
  let ids : Array[Int] = []
  collect_var_ids(clause.head, ids)
  collect_var_ids(clause.body, ids)
  let m : Map[Int, Int] = Map([])
  for i in 0..<ids.length() {
    m[ids[i]] = engine.var_counter + i
  }
  engine.var_counter += ids.length()
  (replace_vars(clause.head, m), replace_vars(clause.body, m))
}

///|
/// 按映射纯替换变量。
fn replace_vars(t : LoveTerm, m : Map[Int, Int]) -> LoveTerm {
  match t {
    LoveTerm::Var(id) =>
      match m.get(id) {
        Some(n) => LoveTerm::Var(n)
        None => t
      }
    LoveTerm::Struct(n, args) =>
      LoveTerm::Struct(n, args.map(fn(a) { replace_vars(a, m) }))
    LoveTerm::ListCons(h, tl) =>
      LoveTerm::ListCons(replace_vars(h, m), replace_vars(tl, m))
    other => other
  }
}

///|
/// SLD 求解引擎。
priv struct Engine {
  program : Program
  subst : Subst
  mut goals : Array[Frame]
  cps : Array[ChoicePoint]
  mut var_counter : Int
  mut found : Bool
  query : LoveTerm
}

///|
fn Engine::new(
  program : Program,
  start_counter : Int,
  query : LoveTerm,
) -> Engine {
  {
    program,
    subst: Subst::new(),
    goals: [{ term: query, ci: 0, barrier: 0 }],
    cps: [],
    var_counter: start_counter,
    found: false,
    query,
  }
}

///|
/// 分配一个全新变量 id。
fn Engine::fresh_var(engine : Engine) -> Int {
  let id = engine.var_counter
  engine.var_counter += 1
  id
}

///|
/// 惰性求解：每次调用推进到下一个解，返回解引用后的查询项。
fn Engine::solve_next(engine : Engine) -> LoveTerm? {
  if engine.found {
    if !engine.backtrack() {
      return None
    }
  }
  for ;; {
    if engine.goals.is_empty() {
      engine.found = true
      return Some(engine.subst.deref(engine.query))
    }
    let f = match engine.goals.pop() {
      Some(f) => f
      None => return None
    }
    if !engine.process(f) {
      if !engine.backtrack() {
        return None
      }
    }
  }
}

///|
/// 处理一个目标帧，返回该目标是否成功。
fn Engine::process(engine : Engine, f : Frame) -> Bool {
  match engine.subst.deref(f.term) {
    LoveTerm::Atom("true") => true
    LoveTerm::Atom("fail") => false
    LoveTerm::Atom("!") => {
      engine.cps.truncate(f.barrier)
      true
    }
    LoveTerm::Atom(name) => engine.call_predicate(name, [], f)
    LoveTerm::Var(_) => false
    LoveTerm::Int(_) | LoveTerm::Float(_) | LoveTerm::Str(_) => false
    LoveTerm::ListCons(_, _) | LoveTerm::ListNil => false
    LoveTerm::Struct(name, args) => engine.call_predicate(name, args, f)
  }
}

///|
/// 调用谓词：内置优先，否则查找子句。
fn Engine::call_predicate(
  engine : Engine,
  name : String,
  args : Array[LoveTerm],
  f : Frame,
) -> Bool {
  match engine.try_builtin(name, args, f) {
    Some(ok) => ok
    None => engine.clause_call(f.term, f)
  }
}

///|
/// 基于子句的调用：选择下一条子句、记录 choice point、合一头部、压入体目标。
fn Engine::clause_call(engine : Engine, goal : LoveTerm, f : Frame) -> Bool {
  let name = match goal {
    LoveTerm::Atom(n) => n
    LoveTerm::Struct(n, _) => n
    _ => return false
  }
  let clauses = engine.program.clauses_of(name)
  if f.ci >= clauses.length() {
    return false
  }
  let c = clauses[f.ci]
  engine.cps.push({
    trail_len: engine.subst.trail.length(),
    goals_snapshot: snapshot_goals(engine.goals),
    kind: CPKind::NextClause(f.term, f.ci + 1, f.barrier),
  })
  let (head, body) = fresh_clause_vars(engine, c)
  if !unify(engine.subst, goal, head) {
    return false
  }
  // 体目标屏障 = 调用帧的屏障：cut 提交本子句的选择
  engine.push_body(body, f.barrier)
  true
}

///|
/// 压入子句体目标（展开逗号连接）。
fn Engine::push_body(engine : Engine, body : LoveTerm, barrier : Int) -> Unit {
  match engine.subst.deref(body) {
    LoveTerm::Atom("true") => ()
    LoveTerm::Struct(",", [a, b]) => {
      engine.push_body(b, barrier)
      engine.push_body(a, barrier)
    }
    other => engine.goals.push({ term: other, ci: 0, barrier })
  }
}

///|
/// 回溯：弹出 choice point 并恢复状态；没有可回溯点时返回 false。
fn Engine::backtrack(engine : Engine) -> Bool {
  for ;; {
    if engine.cps.is_empty() {
      return false
    }
    let cp = match engine.cps.pop() {
      Some(cp) => cp
      None => return false
    }
    engine.subst.unbind_to(cp.trail_len)
    engine.goals = cp.goals_snapshot
    match cp.kind {
      CPKind::NextClause(term, ci, barrier) => {
        engine.goals.push({ term, ci, barrier })
        return true
      }
      CPKind::PushTerm(term, barrier) => {
        engine.goals.push({ term, ci: 0, barrier })
        return true
      }
      CPKind::ClauseScan(ci, h, b, all) => {
        let mut idx = ci
        let mut ok = false
        while idx < all.length() {
          let c = all[idx]
          let (head, body) = fresh_clause_vars(engine, c)
          if unify(engine.subst, h, head) && unify(engine.subst, b, body) {
            // 重推 cp：撤销基线保持为 cp.trail_len（本次尝试之前的长度）
            engine.cps.push({
              trail_len: cp.trail_len,
              goals_snapshot: snapshot_goals(engine.goals),
              kind: CPKind::ClauseScan(idx + 1, h, b, all),
            })
            ok = true
            break
          }
          engine.subst.unbind_to(cp.trail_len)
          idx += 1
        }
        if ok {
          return true
        }
      }
      CPKind::EnumInt(lo, hi, x) =>
        if lo <= hi {
          let before = engine.subst.trail.length()
          if unify(engine.subst, x, LoveTerm::Int(lo)) {
            engine.cps.push({
              trail_len: before,
              goals_snapshot: snapshot_goals(engine.goals),
              kind: CPKind::EnumInt(lo + 1L, hi, x),
            })
            return true
          }
        }
    }
  }
}
