///|
/// Love 解释器的顶层 API。
///
/// 用法：
/// ```
/// let db = program_from_text("parent(tom, bob). parent(bob, ann). grandparent(X, Y) :- parent(X, Z), parent(Z, Y).")
/// let session = Session::new(db)
/// inspect(answers_string(session, "?- grandparent(tom, Who)."))
/// ```
pub fn program_from_text(src : String) -> Database raise LoveError {
  let clauses = parse_program_text(src)
  let db = Database::new()
  for c in clauses {
    db.add_clause(c.head, c.body)
  }
  db
}

///|
/// 把子句文本加载进已有数据库
pub fn load_program(db : Database, src : String) -> Database raise LoveError {
  let clauses = parse_program_text(src)
  for c in clauses {
    db.add_clause(c.head, c.body)
  }
  db
}

///|
/// 从查询文本创建求解引擎
pub fn query(session : Session, query_text : String) -> Engine raise LoveError {
  let goals = parse_query_text(query_text)
  Engine::new(session, goals, @hashmap.HashMap::new())
}

///|
/// 解析并断言一个子句到会话的数据库（REPL 用）
pub fn assert_text(session : Session, src : String) -> Unit raise LoveError {
  let clause = parse_clause_text(src)
  session.db.add_clause(clause.head, clause.body)
}

///|
/// 收集引擎查询中的顶层变量名（按出现顺序，去重）
pub fn engine_vars(e : Engine) -> Array[String] {
  let vars = []
  for g in e.goals {
    collect_vars(g, vars)
  }
  vars
}

///|
/// 生成查询答案的字符串：
/// 每个解一行，形如 `X = ..., Y = ...`；无解时输出 `false`。
/// 求解过程中 write/1 产生的输出会先被收集进 `out` 参数。
pub fn answers_string(
  session : Session,
  query_text : String,
  out : StringBuilder,
) -> String raise LoveError {
  let e = query(session, query_text)
  let vars = []
  for g in e.goals {
    collect_vars(g, vars)
  }
  let sb = StringBuilder()
  let mut count = 0
  for ;; {
    let opt = e.next_solution()
    if opt is Some(env) {
      out.write_string(session.drain_output())
      if count > 0 {
        sb.write_string("; ")
      }
      // 只显示已绑定的查询变量（未绑定变量跳过，如 findall 的模板变量）
      let mut shown = 0
      for i in 0..<vars.length() {
        if walk(Var(vars[i]), env) is Var(_) {
          continue
        }
        if shown > 0 {
          sb.write_string(", ")
        }
        sb.write_string(vars[i])
        sb.write_string(" = ")
        sb.write_string(term_to_string(walk_deep(Var(vars[i]), env), env))
        shown = shown + 1
      }
      if shown == 0 {
        sb.write_string("true")
      }
      count = count + 1
    } else {
      break
    }
  }
  out.write_string(session.drain_output())
  if count == 0 {
    sb.write_string("false")
  }
  sb.to_string()
}
