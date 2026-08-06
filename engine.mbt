///|
/// 子句：事实（body 为空）或规则 `Head :- Body.`
pub struct Clause {
  head : Term
  body : Array[Term]
}

///|
/// 谓词数据库：子句序列 + (name/arity) 索引。
/// 抽象类型：外部只能通过 `new`/`add_clause`/`lookup` 等公开方法交互，
/// 内部表示（子句列表与索引）完全隐藏。
struct Database {
  clauses : Array[Clause]
  mut index : Map[String, Array[Int]]
}

///|
pub fn Database::new() -> Database {
  { clauses: [], index: {} }
}

///|
/// 谓词键：`name/arity`
fn pred_key(t : Term) -> String {
  match t {
    Atom(name) => "\{name}/0"
    Compound(name, args) => "\{name}/\{args.length()}"
    _ => abort("invalid predicate head")
  }
}

///|
/// 追加一个子句到数据库
pub fn Database::add_clause(
  self : Database,
  head : Term,
  body : Array[Term],
) -> Unit {
  let key = pred_key(head)
  self.clauses.push({ head, body })
  let id = self.clauses.length() - 1
  match self.index.get(key) {
    Some(arr) => arr.push(id)
    None => self.index[key] = [id]
  }
}

///|
/// 按谓词键查询匹配子句的索引
pub fn Database::lookup(self : Database, key : String) -> Array[Int] {
  match self.index.get(key) {
    Some(arr) => arr
    None => []
  }
}

///|
/// 删除第一个与 `head`/`body` 合一的子句（`del` 内建）。
/// 找到并删除后重建索引；找不到返回 `false`。
pub fn Database::retract(
  self : Database,
  head : Term,
  body : Array[Term],
) -> Bool {
  for i in 0..<self.clauses.length() {
    let c = self.clauses[i]
    match unify(head, c.head, @hashmap.HashMap::new()) {
      None => continue
      Some(env) =>
        if body.length() == c.body.length() {
          let mut ok = true
          for j in 0..<body.length() {
            if unify(body[j], c.body[j], env) is None {
              ok = false
              break
            }
          }
          if ok {
            let _ = self.clauses.remove(i)
            self.index = {}
            for k in 0..<self.clauses.length() {
              let key = pred_key(self.clauses[k].head)
              match self.index.get(key) {
                Some(arr) => arr.push(k)
                None => self.index[key] = [k]
              }
            }
            return true
          }
        }
    }
  }
  false
}

///|
/// 会话：数据库、变量重命名计数器、输出缓冲（write 内建写入）。
/// 嵌套求解（findall / \+）共享会话，因此输出与命名保持一致。
/// 抽象类型：外部通过 `new`/`drain_output` 等公开方法交互。
struct Session {
  db : Database
  counter : Ref[Int]
  output : StringBuilder
}

///|
pub fn Session::new(db : Database) -> Session {
  { db, counter: Ref(0), output: StringBuilder() }
}

///|
/// 取走会话中的输出缓冲内容并清空
pub fn Session::drain_output(self : Session) -> String {
  let s = self.output.to_string()
  self.output.reset()
  s
}

///|
/// 生成一个全新的变量名（全局递增，保证不与任何现有变量冲突）
fn fresh_var_name(e : Engine, prefix : String) -> String {
  e.session.counter.val = e.session.counter.val + 1
  "\{prefix}#\{e.session.counter.val}"
}

///|
/// 候选：数据库子句，或内联展开（`;` 析取、member/length/append 的展开子句）。
/// 仅作为 ChoicePoint 的内部字段类型使用。
priv enum Candidate {
  Db(Int)
  Inline(Array[(Term, Term)], Array[Term])
}

///|
/// 选择点：记录回溯时恢复的状态
priv struct ChoicePoint {
  goals : Array[Term]
  env : Env
  candidates : Array[Candidate]
  mut ci : Int
  /// 该调用压栈前的栈长度：子句内 `!` 截断到此处
  marker : Int
  /// 压栈时的 cut 上下文（恢复时还原）
  cut_ctx : Int
}

///|
/// 求解引擎：当前目标列表 + 环境 + 选择点栈。
/// 抽象类型：外部通过 `new`/`next_solution` 等公开方法交互，
/// 求解状态（目标、环境、选择点栈）完全隐藏。
struct Engine {
  session : Session
  mut goals : Array[Term]
  mut env : Env
  stack : Array[ChoicePoint]
  mut cut_marker : Int
  mut exhausted : Bool
}

///|
/// 从查询目标创建引擎
pub fn Engine::new(session : Session, goals : Array[Term], env : Env) -> Engine {
  { session, goals, env, stack: [], cut_marker: 0, exhausted: false }
}

///|
/// 子句实例化：重命名其中的变量为全新变量
fn rename_clause(e : Engine, clause : Clause) -> (Term, Array[Term]) {
  let (head, map) = rename_term(e, clause.head, @hashmap.HashMap::new())
  let body = []
  let mut m = map
  for t in clause.body {
    let (nt, m2) = rename_term(e, t, m)
    body.push(nt)
    m = m2
  }
  (head, body)
}

///|
/// 重命名项中的变量，返回 (新项, 更新后的重命名表)
fn rename_term(
  e : Engine,
  t : Term,
  map : @hashmap.HashMap[String, String],
) -> (Term, @hashmap.HashMap[String, String]) {
  match t {
    Var(name) =>
      match map.get(name) {
        Some(new) => (Var(new), map)
        None => {
          let new = fresh_var_name(e, name)
          (Var(new), map.add(name, new))
        }
      }
    Compound(f, args) => {
      let new_args = []
      let mut m = map
      for a in args {
        let (na, m2) = rename_term(e, a, m)
        new_args.push(na)
        m = m2
      }
      (Compound(f, new_args), m)
    }
    _ => (t, map)
  }
}

///|
/// 求解进度
priv enum StepResult {
  SolutionFound
  NoMore
}

///|
/// 推进一步求解；返回是否需要继续 / 找到解 / 彻底失败
fn Engine::step_once(self : Engine) -> StepResult {
  for ;; {
    if self.goals.is_empty() {
      return SolutionFound
    }
    let g = self.goals[0]
    if g is Atom("!") {
      // cut：截断选择点栈到当前子句进入时的高度
      self.stack.truncate(self.cut_marker)
      self.goals = self.goals[1:].to_owned()
      continue
    }
    if self.solve_goal(g) {
      continue
    } else {
      if !self.backtrack() {
        return NoMore
      }
      continue
    }
  }
}

///|
/// 取下一个解（环境）；无解返回 None。
///
/// 找到解后立即通过回溯推进到下一个选择点（或标记耗尽），
/// 保证后续调用不会重复返回同一个解。
pub fn Engine::next_solution(self : Engine) -> Env? {
  if self.exhausted {
    return None
  }
  for ;; {
    match self.step_once() {
      SolutionFound => {
        let env = self.env
        if self.backtrack() {
          return Some(env)
        } else {
          self.exhausted = true
          return Some(env)
        }
      }
      NoMore => {
        self.exhausted = true
        return None
      }
    }
  }
}

///|
/// 求解当前目标 `g`（goals[0]）。成功时推进 goals，返回 true；
/// 失败时返回 false（调用方负责回溯）。
fn Engine::solve_goal(self : Engine, g : Term) -> Bool {
  // 析取 (A ; B)：展开为两个内联候选，先 A 后 B（回溯时尝试 B）
  match g {
    Compound(";", [a, b]) => {
      let cands = [
        Candidate::Inline([], flatten(a)),
        Candidate::Inline([], flatten(b)),
      ]
      self.push_choice(cands)
      return self.try_candidate(g)
    }
    _ => ()
  }
  match exec_builtin(g, self) {
    Some(result) =>
      match result {
        Fail => false
        Succeed => {
          self.goals = self.goals[1:].to_owned()
          true
        }
        SucceedEnv(env) => {
          self.env = env
          self.goals = self.goals[1:].to_owned()
          true
        }
        Choice(env, cands) => {
          self.env = env
          self.push_choice(cands)
          self.try_candidate(g)
        }
      }
    None => {
      let key = pred_key(g)
      let cands = self.session.db.lookup(key).map(i => Candidate::Db(i))
      if cands.is_empty() {
        false
      } else {
        self.push_choice(cands)
        self.try_candidate(g)
      }
    }
  }
}

///|
/// 压入选择点并立即尝试第一个候选
fn Engine::push_choice(self : Engine, cands : Array[Candidate]) -> Unit {
  let marker = self.stack.length()
  self.stack.push({
    goals: self.goals,
    env: self.env,
    candidates: cands,
    ci: 0,
    marker,
    cut_ctx: self.cut_marker,
  })
}

///|
/// 尝试当前选择点的下一个候选；成功返回 true，失败时回溯到栈顶
/// 的其他选择点或返回 false
fn Engine::try_candidate(self : Engine, g : Term) -> Bool {
  for ;; {
    if self.stack.is_empty() {
      return false
    }
    let idx = self.stack.length() - 1
    if self.stack[idx].ci >= self.stack[idx].candidates.length() {
      let _ = self.stack.pop()
      return false
    }
    let cand = self.stack[idx].candidates[self.stack[idx].ci]
    self.stack[idx].ci = self.stack[idx].ci + 1
    let cp_marker = self.stack[idx].marker
    let ok = match cand {
      Candidate::Db(i) => {
        let clause = self.session.db.clauses[i]
        let (head, body) = rename_clause(self, clause)
        match unify(g, head, self.env) {
          None => false
          Some(env2) => {
            self.env = env2
            if body.is_empty() {
              self.goals = self.goals[1:].to_owned()
            } else {
              self.cut_marker = cp_marker
              self.goals = body + self.goals[1:].to_owned()
            }
            true
          }
        }
      }
      Candidate::Inline(pairs, body) => {
        let mut env = self.env
        let mut failed = false
        for p in pairs {
          let (a, b) = p
          match unify(a, b, env) {
            Some(env2) => env = env2
            None => {
              failed = true
              break
            }
          }
        }
        if failed {
          false
        } else {
          self.env = env
          if body.is_empty() {
            self.goals = self.goals[1:].to_owned()
          } else {
            self.cut_marker = cp_marker
            self.goals = body + self.goals[1:].to_owned()
          }
          true
        }
      }
    }
    if ok {
      return true
    }
  }
}

///|
/// 回溯：恢复最近的选择点并尝试其下一个候选；
/// 无可恢复时返回 false（求解结束）
fn Engine::backtrack(self : Engine) -> Bool {
  for ;; {
    if self.stack.is_empty() {
      return false
    }
    let idx = self.stack.length() - 1
    if self.stack[idx].ci < self.stack[idx].candidates.length() {
      let cp = self.stack[idx]
      self.goals = cp.goals
      self.env = cp.env
      self.cut_marker = cp.cut_ctx
      if self.try_candidate(self.goals[0]) {
        return true
      }
      // try_candidate 已耗尽并弹出该选择点，继续回溯更早的选择点
      continue
    }
    let _ = self.stack.pop()
  }
}

///|
/// 收集当前查询的所有解
pub fn solve_all(e : Engine) -> Array[Env] {
  let out = []
  for ;; {
    match e.next_solution() {
      Some(env) => out.push(env)
      None => break
    }
  }
  out
}

///|
/// 在子会话中求解：返回所有解的环境
fn sub_solve_all(e : Engine, goals : Array[Term], env : Env) -> Array[Env] {
  let sub = Engine::new(e.session, goals, env)
  solve_all(sub)
}
