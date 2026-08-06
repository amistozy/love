///|
/// Love REPL：交互式解释器入口。
///
/// - 输入 `?- goal.` 发起查询
/// - 输入 `fact.` / `head :- body.` 向数据库断言子句
/// - 输入 `halt.` 退出
/// - 求解答案后可输入 `;` 查看下一个解，`.` 或回车结束
async fn main {
  let db = @love.Database::new()
  let session = @love.Session::new(db)
  @stdio.stdout.write(
    "Love 1.0 - a little Prolog. Enter clauses or queries (end with '.').\n",
  )
  @stdio.stdout.write(
    "  e.g.  parent(tom, bob).   or   ?- parent(X, bob).   or   halt.\n",
  )
  for ;; {
    @stdio.stdout.write("?- ")
    let line = @stdio.stdin.read_until("\n")
    match line {
      None => break
      Some(text) => {
        let t = text.trim().to_string()
        if t.is_empty() || t == "." {
          // 空行或上一查询结束的残留 `.`
          continue
        }
        if t == "halt." {
          break
        }
        if t.has_prefix("?-") || t.has_prefix("?-") {
          run_query(session, t)
        } else {
          assert_clause(session, t)
        }
      }
    }
  }
}

///|
/// 断言子句到数据库
async fn assert_clause(session : @love.Session, src : String) -> Unit {
  try {
    @love.assert_text(session, src)
    @stdio.stdout.write("true.\n")
  } catch {
    @love.LoveError::Msg(m) => @stdio.stdout.write("error: \{m}\n")
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
/// 执行查询：逐解显示，支持 `;` 继续、`.`/回车 停止
async fn run_query(session : @love.Session, src : String) -> Unit {
  let e = try @love.query(session, src) catch {
    @love.LoveError::Msg(m) => {
      @stdio.stdout.write("error: \{m}\n")
      return
    }
    _ => return
  } noraise {
    e => e
  }
  let vars = []
  for g in e.goals {
    @love.collect_vars(g, vars)
  }
  let mut count = 0
  for ;; {
    let opt = e.next_solution()
    if opt is Some(env) {
      @stdio.stdout.write(session.drain_output())
      if count > 0 {
        @stdio.stdout.write("; ")
      }
      let mut shown = 0
      for i in 0..<vars.length() {
        if @love.walk(Var(vars[i]), env) is Var(_) {
          continue
        }
        if shown > 0 {
          @stdio.stdout.write(", ")
        }
        @stdio.stdout.write("\{vars[i]} = ")
        @stdio.stdout.write(
          @love.term_to_string(@love.walk_deep(Var(vars[i]), env), env),
        )
        shown = shown + 1
      }
      if shown == 0 {
        @stdio.stdout.write("true")
      }
      count = count + 1
      // 询问是否继续
      @stdio.stdout.write("\n")
      let more = @stdio.stdin.read_until("\n")
      match more {
        None => break
        Some(ans) => if ans.trim() != ";" { break }
      }
    } else {
      @stdio.stdout.write(session.drain_output())
      if count == 0 {
        @stdio.stdout.write("false.\n")
      } else {
        @stdio.stdout.write("\n")
      }
      break
    }
  }
}
