///|
/// Love 命令行入口：加载 .lv 程序文件，进入交互式 REPL 或运行单个查询。
///
/// REPL 交互参考 Scryer Prolog 的 toplevel：
///   - 提示符 `?- `，多行输入续行提示 `|  `
///   - 答案独占一行，后续答案以 `;  ` 开头，确定解以 `.` 结尾
///   - `;`/空格/`n` 下一个，`a` 全部，`f` 五个，`h` 帮助，Enter/`.` 停止
///   - 交互终端中：Ctrl-L 清屏，Ctrl-D 退出，Backspace 删除，Ctrl-C 取消当前行
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
/// 答案后的按键。
priv enum ReplKey {
  /// 下一个解
  Next
  /// 枚举全部
  All
  /// 再显示 5 个
  Five
  /// Ctrl-D：退出整个 REPL
  Quit
  /// 停止枚举
  Stop
}

///|
/// 交互式 REPL。
async fn repl(program : @love.Program) -> Unit {
  tty_init()
  // 会话内历史（上/下箭头召回；参考 Scryer 的 ~/.scryer_history）
  let history : Array[String] = []
  print_banner()
  for ;; {
    let qs = match read_query_text(history) {
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
    if run_query_line(program, qs) {
      // Ctrl-D：退出 REPL
      break
    }
    // 答案与下一个查询提示符之间空一行
    repl_println("")
  }
}

///|
/// 读取一条完整查询（支持多行，直到以 '.' 结尾）。
/// 交互终端：逐字符原始模式（Backspace/Ctrl-L/Ctrl-D/Ctrl-C 生效）；
/// 管道/重定向：按行读取。
async fn read_query_text(history : Array[String]) -> String? {
  if stdin_is_tty() {
    read_query_chars(history)
  } else {
    read_query_lines()
  }
}

///|
/// 逐字符读取查询（原始模式，无需回车）。
/// 行编辑参考 Scryer 所用的 rustyline：方向键移动光标、Home/End、Delete、历史（上下箭头）。
async fn read_query_chars(history : Array[String]) -> String? {
  if !tty_begin() {
    return read_query_lines()
  }
  @stdio.stdout.write("?- ")
  let r = read_query_chars_core(
    fn() { tty_read_byte() },
    bytes => @stdio.stdout.write(bytes),
    history,
  )
  tty_end()
  r
}

///|
/// 逐字符读取核心（I/O 注入，可测试）：
/// next_byte 提供按键字节（-1 表示 EOF），emit 输出字节到终端，history 为会话历史。
async fn read_query_chars_core(
  next_byte : () -> Int,
  emit : async (Bytes) -> Unit,
  history : Array[String],
) -> String? {
  let mut buf : Array[Byte] = []
  // 光标位置（字节下标，0..len）
  let mut cursor = 0
  // 自上次回车以来是否有新输入：吞掉 CRLF 遗留的 '\n' 与空回车
  let mut new_input = false
  // 是否处于续行状态（决定重绘提示符）
  let mut continuation = false
  // 历史导航位置：history.length() 表示"新输入"
  let mut history_index = history.length()
  for ;; {
    let b = next_byte()
    if b < 0 {
      // EOF：空缓冲退出，否则提交已有内容
      if buf.is_empty() {
        return None
      } else {
        return Some(decode_bytes(buf))
      }
    }
    let c = match b.to_char() {
      Some(c) => c
      None => continue
    }
    match c {
      '\r' | '\n' => {
        if !new_input {
          // 空回车或 CRLF 遗留的 '\n'：无操作（提示符已显示，等待真实输入）
          continue
        }
        new_input = false
        // Enter：提交当前行；未以 '.' 结尾则续行
        emit(@utf8.encode("\n"))
        let text = decode_bytes(buf)
        if ends_with_dot(text) {
          // 记录历史（非空且不与最后一条重复）
          if text.trim() != "" &&
            (history.is_empty() || history[history.length() - 1] != text) {
            history.push(text)
          }
          return Some(text)
        }
        continuation = true
        emit(@utf8.encode("|  "))
      }
      '\u{0008}' | '\u{007F}' => {
        // Backspace / DEL：删除光标前的一个 UTF-8 字符
        if cursor <= 0 {
          continue
        }
        let removed = utf8_len_before(buf, cursor)
        for _ in 0..<removed {
          let _ = buf.remove(cursor - 1)
        }
        cursor -= removed
        new_input = true
        // 重绘：左移一格，写尾部，清残留，光标移回
        emit(@utf8.encode("\u{001B}[D"))
        emit(@utf8.encode(buf_tail_str(buf, cursor)))
        emit(@utf8.encode(" "))
        emit(@utf8.encode("\u{001B}[\{chars_after(buf, cursor) + 1}D"))
      }
      '\u{000C}' => {
        // Ctrl-L：清屏并重绘提示符与已输入内容
        emit(@utf8.encode("\u{001B}[2J\u{001B}[H"))
        emit(@utf8.encode(if continuation { "|  " } else { "?- " }))
        if !buf.is_empty() {
          emit(@utf8.encode(decode_bytes(buf)))
        }
      }
      '\u{0004}' | '\u{001A}' =>
        // Ctrl-D / Ctrl-Z（EOF）：空缓冲退出，非空忽略
        if buf.is_empty() {
          emit(@utf8.encode("\n"))
          return None
        }
      '\u{0003}' => {
        // Ctrl-C：取消当前行，重新提示
        buf = []
        cursor = 0
        new_input = false
        continuation = false
        emit(@utf8.encode("\n?- "))
      }
      '\u{001B}' => {
        // 转义序列：方向键/Home/End/Delete（VT 序列或 Windows 传统扫描码）
        let mut action = 0 // 0=无 1=上 2=下 3=右 4=左 5=Home 6=End 7=Delete
        let b2 = next_byte()
        if b2 < 0 {
          continue
        }
        if b2 == '['.to_int() {
          let b3 = next_byte()
          if b3 < 0 {
            continue
          }
          match b3 {
            0x41 => action = 1
            0x42 => action = 2
            0x43 => action = 3
            0x44 => action = 4
            0x48 => action = 5
            0x46 => action = 6
            0x31 => {
              let _ = next_byte()
              action = 5
            }
            0x33 => {
              let _ = next_byte()
              action = 7
            }
            0x34 => {
              let _ = next_byte()
              action = 6
            }
            _ => ()
          }
        } else if b2 == 0xE0 {
          let b3 = next_byte()
          if b3 < 0 {
            continue
          }
          match b3 {
            0x48 => action = 1
            0x50 => action = 2
            0x4D => action = 3
            0x4B => action = 4
            0x53 => action = 7
            _ => ()
          }
        }
        // 执行动作
        if action == 1 {
          // 上：历史向前
          if history.length() > 0 && history_index > 0 {
            history_index -= 1
            let text = history[history_index]
            buf = bytes_of_string(text)
            cursor = buf.length()
            new_input = true
            emit(@utf8.encode("\r\u{001B}[2K"))
            emit(@utf8.encode(if continuation { "|  " } else { "?- " }))
            if !buf.is_empty() {
              emit(@utf8.encode(text))
            }
          }
        } else if action == 2 {
          // 下：历史向后
          if history_index < history.length() {
            history_index += 1
            let text = if history_index == history.length() {
              ""
            } else {
              history[history_index]
            }
            buf = bytes_of_string(text)
            cursor = buf.length()
            new_input = true
            emit(@utf8.encode("\r\u{001B}[2K"))
            emit(@utf8.encode(if continuation { "|  " } else { "?- " }))
            if !buf.is_empty() {
              emit(@utf8.encode(text))
            }
          }
        } else if action == 3 {
          // 右：光标右移一个字符
          if cursor < buf.length() {
            let n = utf8_len_at(buf[cursor])
            cursor += n
            emit(@utf8.encode("\u{001B}[C"))
          }
        } else if action == 4 {
          // 左：光标左移一个字符
          if cursor > 0 {
            let n = utf8_len_before(buf, cursor)
            cursor -= n
            emit(@utf8.encode("\u{001B}[D"))
          }
        } else if action == 5 {
          // Home：光标到行首
          if cursor > 0 {
            emit(@utf8.encode("\u{001B}[\{chars_before(buf, cursor)}D"))
            cursor = 0
          }
        } else if action == 6 {
          // End：光标到行尾
          if cursor < buf.length() {
            emit(@utf8.encode("\u{001B}[\{chars_after(buf, cursor)}C"))
            cursor = buf.length()
          }
        } else if action == 7 {
          // Delete：删除光标处字符
          if cursor < buf.length() {
            let n = utf8_len_at(buf[cursor])
            for _ in 0..<n {
              let _ = buf.remove(cursor)
            }
            new_input = true
            emit(@utf8.encode(buf_tail_str(buf, cursor)))
            emit(@utf8.encode(" "))
            emit(@utf8.encode("\u{001B}[\{chars_after(buf, cursor) + 1}D"))
          }
        }
      }
      _ => {
        // 可打印字符：收集完整 UTF-8 字符后插入光标处
        let byte = b.to_byte()
        let char_len = utf8_len_at(byte)
        let char_bytes : Array[Byte] = [byte]
        for _ in 1..<char_len {
          let nb = next_byte()
          if nb < 0 {
            break
          }
          char_bytes.push(nb.to_byte())
        }
        for i in 0..<char_bytes.length() {
          buf.insert(cursor + i, char_bytes[i])
        }
        cursor += char_bytes.length()
        new_input = true
        // 回显：写字符，重绘尾部，光标移回
        emit(@utf8.encode(decode_bytes(char_bytes)))
        if cursor < buf.length() {
          emit(@utf8.encode(buf_tail_str(buf, cursor)))
          emit(@utf8.encode("\u{001B}[\{chars_after(buf, cursor)}D"))
        }
      }
    }
  }
}

///|
/// buf[from..] 的字符串。
fn buf_tail_str(buf : Array[Byte], from : Int) -> String {
  @utf8.decode_lossy(Bytes::from_array(buf[from:].to_owned()))
}

///|
/// 一个 UTF-8 引导字节对应的字符字节数。
fn utf8_len_at(lead : Byte) -> Int {
  let l = lead.to_int()
  if l < 0x80 {
    1
  } else if l >= 0xF0 {
    4
  } else if l >= 0xE0 {
    3
  } else if l >= 0xC0 {
    2
  } else {
    // 续字节单独出现：占 1
    1
  }
}

///|
/// pos 之前一个 UTF-8 字符的字节数。
fn utf8_len_before(buf : Array[Byte], pos : Int) -> Int {
  let mut i = pos - 1
  while i >= 0 {
    let x = buf[i].to_int()
    if x >= 0x80 && x < 0xC0 {
      i -= 1
    } else {
      break
    }
  }
  pos - i
}

///|
/// pos 之前的字符数（按字符计，非字节）。
fn chars_before(buf : Array[Byte], pos : Int) -> Int {
  let mut count = 0
  let mut i = 0
  while i < pos {
    let n = utf8_len_at(buf[i])
    i += n
    count += 1
  }
  count
}

///|
/// pos 之后的字符数。
fn chars_after(buf : Array[Byte], pos : Int) -> Int {
  chars_before(buf, buf.length()) - chars_before(buf, pos)
}

///|
/// 字符串转字节数组（历史召回用）。
fn bytes_of_string(s : String) -> Array[Byte] {
  let bs = @utf8.encode(s)
  let out : Array[Byte] = []
  for x in bs {
    out.push(x)
  }
  out
}

///|
/// 按行读取查询（管道/重定向路径）。
async fn read_query_lines() -> String? {
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
/// 字节缓冲解码为 UTF-8 字符串。
fn decode_bytes(buf : Array[Byte]) -> String {
  @utf8.decode_lossy(Bytes::from_array(buf))
}

///|
/// 清屏（ANSI；Windows 需启用 VT 处理，见 love_tty_init）。
async fn clear_screen() -> Unit {
  @stdio.stdout.write("\u{001B}[2J\u{001B}[H")
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
/// 返回 true 表示用户按 Ctrl-D 退出整个 REPL。
async fn run_query_line(program : @love.Program, line : String) -> Bool {
  let (q, names) = @love.parse_query_with_names(line) catch {
    err => {
      repl_println("syntax error: \{err}")
      return false
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
      match read_repl_key() {
        ReplKey::Next => need_ask = false
        ReplKey::All => {
          all = true
          need_ask = false
        }
        ReplKey::Five => {
          n_more = 5
          need_ask = false
        }
        ReplKey::Quit => {
          repl_println("")
          return true
        }
        ReplKey::Stop => {
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
  false
}

///|
/// 读取用户按键；`h` 帮助、Ctrl-L 清屏后重新读取。
/// 交互终端：原始模式单字符（无需回车，参考 Scryer 的 get_single_char/1）；
/// 管道/重定向：退回按行读取。
async fn read_repl_key() -> ReplKey {
  if stdin_is_tty() {
    for ;; {
      match read_tty_char() {
        None => return ReplKey::Stop
        Some(c) => {
          let k = c.to_ascii_lowercase()
          if k == 'h' {
            print_repl_help()
          } else if k == '\u{000C}' {
            // Ctrl-L：清屏
            clear_screen()
          } else if k == '\u{0004}' {
            // Ctrl-D：退出
            return ReplKey::Quit
          } else if k == ';' || k == 'n' || k == ' ' || k == 'y' {
            return ReplKey::Next
          } else if k == 'a' {
            return ReplKey::All
          } else if k == 'f' {
            return ReplKey::Five
          } else {
            return ReplKey::Stop
          }
        }
      }
    }
  } else {
    for ;; {
      let ans = @stdio.stdin.read_until("\n") catch { _ => None }
      match ans {
        None => return ReplKey::Stop
        Some(a) => {
          let c = a.trim().to_owned()
          if c == "h" {
            print_repl_help()
          } else if c == ";" || c == "n" || c == " " || c == "y" || c == "yes" {
            return ReplKey::Next
          } else if c == "a" {
            return ReplKey::All
          } else if c == "f" {
            return ReplKey::Five
          } else {
            return ReplKey::Stop
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
    "Type a query (e.g. `happy(X).`); `halt.` to quit; Ctrl-D to exit; Ctrl-L to clear.",
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
  repl_println("While typing a query: Backspace delete, Ctrl-L clear screen,")
  repl_println("Ctrl-D exit, Ctrl-C cancel the current line.")
  repl_println("")
}

///|
/// REPL 输出统一走异步 stdout（保证与提示符同缓冲、顺序正确）。
async fn repl_println(s : String) -> Unit {
  @stdio.stdout.write("\{s}\n")
}
