///|
/// Love REPL：交互式解释器入口。
///
/// - 提示符 `?- ` 后直接输入查询目标，如 `member(X, [1, 2, 3]).`
/// - 用 `let Head.` / `let Head :- Body.` 断言子句，`del` 删除
/// - 查询答案后输入 `;` 查看下一个解，`.` 或回车结束
/// - 输入 `halt.` 退出
async fn main {
  let db = @love.Database::new()
  let session = @love.Session::new(db)
  @stdio.stdout.write(
    "Love 1.0 - a little Prolog. Enter a query directly (end with '.').\n",
  )
  @stdio.stdout.write("  query:   member(X, [1, 2, 3]).\n")
  @stdio.stdout.write("  define:  let parent(tom, bob).\n")
  @stdio.stdout.write("  remove:  del parent(tom, bob).\n")
  @stdio.stdout.write("  quit:    halt.\n")
  for ;; {
    @stdio.stdout.write("?- ")
    let line = @stdio.stdin.read_until("\n")
    match line {
      None => break
      Some(text) => {
        let t = text.trim().to_owned()
        if t.is_empty() || t == "." {
          // 空行或上一查询结束的残留 `.`
          continue
        }
        if t == "halt." {
          break
        }
        // 查询（含 add/del 内建）可能抛出 LoveError，统一在此捕获
        try run_query(session, t) catch {
          @love.LoveError::Msg(m) => @stdio.stdout.write("error: \{m}\n")
          _ => @stdio.stdout.write("error: unexpected failure\n")
        } noraise {
          _ => ()
        }
      }
    }
  }
}

///|
/// 执行查询：SWI-Prolog 风格逐解显示。
///
/// 每个解文本后打印一个空格并等待用户输入：用户输入 `;` 回车看下一个解、
/// `.` 或回车结束（`;`/`.` 由终端回显，程序不再输出）；无更多解时打印 `false.`。
async fn run_query(session : @love.Session, src : String) -> Unit {
  let e = @love.query(session, src)
  let vars = @love.engine_vars(e)
  for ;; {
    let opt = e.next_solution()
    if opt is Some(env) {
      @stdio.stdout.write(session.drain_output())
      // 打印解：`X = 1`
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
      // 无绑定变量的解（如 add/del 断言成功）：`true.` 直接结束，不等待后缀
      if shown == 0 {
        @stdio.stdout.write("true.\n")
        break
      }
      // 留一个空格，等待用户输入 `;` 或 `.`。
      // 用户按回车后终端已回显换行，程序不再输出换行（避免空行）。
      @stdio.stdout.write(" ")
      let more = @stdio.stdin.read_until("\n")
      match more {
        None => {
          @stdio.stdout.write("\n")
          break
        }
        Some(ans) => if ans.trim() == ";" { continue } else { break }
      }
    } else {
      // 无更多解（write 内建输出最后 flush）
      @stdio.stdout.write(session.drain_output())
      @stdio.stdout.write("false.\n")
      break
    }
  }
  // 查询结束：空行分隔下一个 `?- ` 提示符
  @stdio.stdout.write("\n")
}
