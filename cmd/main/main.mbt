///|
/// Love 命令行入口：加载 .lv 程序文件，进入交互式 REPL 或运行单个查询。
///
/// 用法（native 目标）：
///   moon run cmd/main --target native                 # 空库 REPL
///   moon run cmd/main --target native -- prog.lv      # 加载程序进入 REPL
///   moon run cmd/main --target native -- prog.lv "?- happy(X)."
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
  println("Love v0.1.0 — Prolog-style logic programming in MoonBit")
  println("Enter a query (e.g. `happy(X).`); `halt.` to quit; Ctrl-D for EOF.")
  for ;; {
    @stdio.stdout.write("Love> ")
    let line = @stdio.stdin.read_until("\n") catch { _ => None }
    match line {
      None => {
        println("")
        break
      }
      Some(raw) => {
        let t = raw.trim().to_owned()
        if t == "" || t == "halt" || t == "exit" || t == "quit" {
          break
        }
        run_query_line(program, t)
      }
    }
  }
}

///|
/// 处理一行查询输入：逐解显示，输入 `;` 继续。
async fn run_query_line(program : @love.Program, line : String) -> Unit {
  let (q, names) = @love.parse_query_with_names(line) catch {
    err => {
      println("syntax error: \{err}")
      return
    }
  }
  let iter = @love.solve(program, q)
  let mut any = false
  for ;; {
    match iter.next() {
      None => {
        if !any {
          println("false")
        }
        break
      }
      Some(sol) => {
        any = true
        println(@love.format_solution(sol, names))
        @stdio.stdout.write("; ")
        let ans = @stdio.stdin.read_until("\n") catch { _ => None }
        match ans {
          None => break
          Some(a) => {
            let t = a.trim().to_owned()
            if t != ";" && t != "y" && t != "yes" {
              break
            }
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
