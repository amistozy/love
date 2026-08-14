///|
/// Love 命令行入口：加载 .lv 程序文件，进入交互式 REPL 或运行单个查询。
///
/// REPL 交互参考 Scryer Prolog 的 toplevel：
///   - 提示符 `?- `，多行输入续行提示 `|  `
///   - 答案后跟 `;` 表示还有解、`.` 表示确定解（无剩余 choice point）
///   - `;`/空格/`n` 下一个，`a` 全部，`f` 五个，`h` 帮助，Enter/`.` 停止
///
/// 用法：
///   moon run cmd/main                 # 空库 REPL
///   moon run cmd/main -- prog.lv      # 加载程序进入 REPL
///   moon run cmd/main -- prog.lv "?- happy(X)."
async fn main {
  let args = @env.args()
  let mut file : String? = None
  let mut query : String? = None
  for a in args[1:] {
    if a == "-h" || a == "--help" {
      usage()
      return
    } else if a.has_prefix("?-") {
      if query is None {
        query = Some(a)
      }
    } else if file is None {
      file = Some(a)
    } else if query is None {
      query = Some(a)
    } else {
      println("warning: ignoring extra argument: \{a}")
    }
  }
  let program = match file {
    None => @love.Program::new()
    Some(path) => load_program(path)
  }
  @love.load_directives(program)
  match query {
    None => repl(program)
    Some(qs) => {
      let (q, names) = @love.parse_query_with_names(qs) catch {
        err => abort("error: \{err}")
      }
      batch_query(program, q, names)
    }
  }
}

///|
/// 读取并解析程序文件；出错时打印信息并终止。
fn load_program(path : String) -> @love.Program {
  let bytes = @fs.read_file_to_bytes(path) catch {
    _ => abort("error: cannot read '\{path}'")
  }
  let src = @utf8.decode(bytes[:]) catch {
    _ => abort("error: '\{path}' is not valid UTF-8")
  }
  @love.parse_program(src) catch {
    err => abort("error: \{err}")
  }
}

///|
fn usage() -> Unit {
  println("Love — a Prolog-style logic programming language (MoonBit)")
  println("usage: love [file.lv] [\"?- query.\"]")
  println("  love                     start REPL with empty program")
  println("  love prog.lv             load program and start REPL")
  println("  love prog.lv \"?- q.\"     run one query and print all solutions")
}

///|
/// 交互式 REPL。
async fn repl(program : @love.Program) -> Unit {
  print_banner()
  for ;; {
    let qs = match read_query_text() {
      None => {
        repl_println("")
        break
      }
      Some(s) => s
    }
    let t = qs.trim().to_owned()
    if t == "" {
      continue
    }
    if t == "halt" ||
      t == "halt." ||
      t == "exit" ||
      t == "exit." ||
      t == "quit" ||
      t == "quit." {
      break
    }
    if t == "help" || t == "help." {
      print_repl_help()
      continue
    }
    run_query_line(program, qs)
    // 答案与下一个查询提示符之间空一行
    repl_println("")
  }
}

///|
/// 读取一条完整查询：支持多行输入，直到以 '.' 结尾。
async fn read_query_text() -> String? {
  let sb = StringBuilder()
  for ;; {
    if sb.is_empty() {
      @stdio.stdout.write("?- ")
    } else {
      @stdio.stdout.write("|  ")
    }
    let line = @stdio.stdin.read_until("\n") catch { _ => None }
    match line {
      None => return None
      Some(l) => {
        sb.write_string(l)
        if ends_with_dot(l) {
          return Some(sb.to_string())
        }
      }
    }
  }
}

///|
/// 一行是否以 '.' 结尾（忽略尾部空白）。
fn ends_with_dot(line : String) -> Bool {
  let t = line.trim()
  t.length() > 0 && t[t.length() - 1] == '.'.to_int().to_uint16()
}

///|
/// 运行查询并交互式枚举解。
/// 显示格式参考 Scryer：首个答案缩进 3 空格，后续答案以 `;  ` 开头（分号在行首），
/// 最后一个确定解以 `.` 结尾，无解/耗尽时输出 `false.`。
async fn run_query_line(program : @love.Program, line : String) -> Unit {
  let (q, names) = @love.parse_query_with_names(line) catch {
    err => {
      repl_println("syntax error: \{err}")
      return
    }
  }
  let iter = @love.solve(program, q)
  // 状态机：need_ask 在打印下一个解之前询问（Scryer 的 read_input 语义）
  let mut first = true
  let mut need_ask = false
  let mut all = false
  let mut n_more = 0
  for ;; {
    if need_ask {
      let action = read_repl_key()
      match action {
        None => break
        Some(c) =>
          if c == ";" || c == "n" || c == " " || c == "y" || c == "yes" {
            need_ask = false
          } else if c == "a" {
            all = true
            need_ask = false
          } else if c == "f" {
            n_more = 5
            need_ask = false
          } else {
            // '.' / Enter / 其他：停止枚举
            repl_println(";  ... .")
            break
          }
      }
    }
    match iter.next() {
      None => {
        // 无解或枚举耗尽（Scryer 的 tail false）
        if first {
          repl_println("   false.")
        } else {
          repl_println(";  false.")
        }
        break
      }
      Some(sol) => {
        let prefix = if first { "   " } else { ";  " }
        first = false
        let text = @love.format_solution(sol, names)
        if sol.more {
          repl_println("\{prefix}\{text}")
          need_ask = true
          if all {
            need_ask = false
          }
          if n_more > 0 {
            n_more -= 1
            need_ask = n_more == 0
          }
        } else {
          repl_println("\{prefix}\{text}.")
          break
        }
      }
    }
  }
}

///|
/// 读取用户按键；`h` 显示帮助后重新读取。
/// 交互终端：原始模式单字符（无需回车，参考 Scryer 的 get_single_char/1）；
/// 管道/重定向：退回按行读取。
async fn read_repl_key() -> String? {
  if stdin_is_tty() {
    for ;; {
      match read_tty_char() {
        None => return None
        Some(c) => {
          let k = c.to_ascii_lowercase()
          if k == 'h' {
            print_repl_help()
          } else {
            return Some(k.to_string())
          }
        }
      }
    }
  } else {
    for ;; {
      let ans = @stdio.stdin.read_until("\n") catch { _ => None }
      match ans {
        None => return None
        Some(a) => {
          let c = a.trim().to_owned()
          if c == "h" {
            print_repl_help()
          } else {
            return Some(c)
          }
        }
      }
    }
  }
}

///|
/// 批处理：打印全部解。
fn batch_query(
  program : @love.Program,
  q : @love.LoveTerm,
  names : Map[Int, String],
) -> Unit {
  let sols = @love.solve_all(program, q)
  if sols.is_empty() {
    println("false")
  } else {
    for sol in sols {
      println(@love.format_solution(sol, names))
    }
  }
}

///|
async fn print_banner() -> Unit {
  repl_println("Love v0.1.0 — Prolog-style logic programming in MoonBit")
  repl_println(
    "Type a query (e.g. `happy(X).`); `halt.` to quit; Ctrl-D for EOF.",
  )
  repl_println(
    "After an answer: `;` next, `.` stop, `a` all, `f` five, `h` help.",
  )
}

///|
async fn print_repl_help() -> Unit {
  repl_println("")
  repl_println("SPACE, \"n\" or \";\": next solution, if any")
  repl_println("RETURN or \".\": stop enumeration")
  repl_println("\"a\": enumerate all solutions")
  repl_println("\"f\": enumerate the next 5 solutions")
  repl_println("\"h\": display this help message")
  repl_println("")
}

///|
/// REPL 输出统一走异步 stdout（保证与提示符同缓冲、顺序正确）。
async fn repl_println(s : String) -> Unit {
  @stdio.stdout.write("\{s}\n")
}
