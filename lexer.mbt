///|
/// 词法记号。
priv enum Tok {
  /// 小写开头的原子名（含 is、mod 等运算符原子）
  Ident(String)
  /// 变量名（大写或 _ 开头）
  VarTok(String)
  /// 整数
  IntTok(Int64)
  /// 浮点数
  FloatTok(Double)
  /// "..." 字符串
  StrTok(String)
  /// '...' 引用原子
  QuotedAtom(String)
  /// 符号串（运算符/标点）
  Sym(String)
  /// 子句结束符 .
  Dot
  /// 输入结束
  Eof
}

///|
priv struct Lexer {
  src : String
  mut pos : Int
}

///|
fn is_lower(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_upper(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_alpha(c : Char) -> Bool {
  is_lower(c) || is_upper(c)
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
fn is_hexdigit(c : Char) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn is_graphic(c : Char) -> Bool {
  match c {
    '#'
    | '$'
    | '&'
    | '*'
    | '+'
    | '-'
    | '.'
    | '/'
    | ':'
    | '<'
    | '='
    | '>'
    | '?'
    | '@'
    | '^'
    | '~'
    | '\\' => true
    _ => false
  }
}

///|
fn is_solo(c : Char) -> Bool {
  match c {
    '!' | '(' | ')' | '[' | ']' | '{' | '}' | '|' | ',' | ';' => true
    _ => false
  }
}

///|
fn Lexer::peek(lexer : Lexer) -> Char? {
  lexer.src.get_char(lexer.pos)
}

///|
fn Lexer::bump(lexer : Lexer) -> Unit {
  match lexer.src.get_char(lexer.pos) {
    None => ()
    Some(c) => lexer.pos += c.utf16_len()
  }
}

///|
/// 跳过空白与注释（% 行注释、/* */ 块注释），并容忍 UTF-8 BOM。
fn Lexer::skip_ws(lexer : Lexer) -> Unit {
  for ;; {
    match lexer.peek() {
      None => break
      Some(c) =>
        if c.is_whitespace() || c == '\u{FEFF}' {
          lexer.bump()
        } else if c == '%' {
          for ;; {
            match lexer.peek() {
              None => break
              Some(c2) => {
                lexer.bump()
                if c2 == '\n' {
                  break
                }
              }
            }
          }
        } else if c == '/' &&
          lexer.pos + 1 < lexer.src.length() &&
          lexer.src[lexer.pos + 1] == '*'.to_int().to_uint16() {
          lexer.bump()
          lexer.bump()
          for ;; {
            match lexer.peek() {
              None => break
              Some(c2) =>
                if c2 == '*' &&
                  lexer.pos + 1 < lexer.src.length() &&
                  lexer.src[lexer.pos + 1] == '/'.to_int().to_uint16() {
                  lexer.bump()
                  lexer.bump()
                  break
                } else {
                  lexer.bump()
                }
            }
          }
        } else {
          break
        }
    }
  }
}

///|
fn Lexer::next_token(lexer : Lexer) -> (Tok, Int) raise LoveError {
  lexer.skip_ws()
  let start = lexer.pos
  match lexer.peek() {
    None => (Tok::Eof, start)
    Some(c) =>
      if c == '\'' {
        lexer.lex_quoted(start)
      } else if c == '"' {
        lexer.lex_string(start)
      } else if is_digit(c) {
        lexer.lex_number(start)
      } else if is_lower(c) {
        lexer.lex_ident(start, c, false)
      } else if is_upper(c) || c == '_' {
        lexer.lex_ident(start, c, true)
      } else if is_solo(c) {
        lexer.bump()
        (Tok::Sym(c.to_string()), start)
      } else if is_graphic(c) {
        lexer.lex_symbol(start)
      } else {
        raise LoveError::LexError(pos=start, "unexpected character: \{c}")
      }
  }
}

///|
/// 标识符：原子名或变量名。
fn Lexer::lex_ident(
  lexer : Lexer,
  start : Int,
  first : Char,
  is_var : Bool,
) -> (Tok, Int) {
  let sb = StringBuilder()
  sb.write_char(first)
  lexer.bump()
  for ;; {
    match lexer.peek() {
      None => break
      Some(c) =>
        if is_alnum(c) || c == '_' {
          sb.write_char(c)
          lexer.bump()
        } else {
          break
        }
    }
  }
  let name = sb.to_string()
  if is_var {
    (Tok::VarTok(name), start)
  } else {
    (Tok::Ident(name), start)
  }
}

///|
/// 数字：整数、十六进制、浮点数（含指数）。
fn Lexer::lex_number(lexer : Lexer, start : Int) -> (Tok, Int) raise LoveError {
  // 十六进制 0x...
  if lexer.peek() == Some('0') && lexer.pos + 1 < lexer.src.length() {
    let next = lexer.src.get_char(lexer.pos + 1)
    if next == Some('x') || next == Some('X') {
      lexer.bump()
      lexer.bump()
      let sb = StringBuilder()
      for ;; {
        match lexer.peek() {
          Some(c) if is_hexdigit(c) => {
            sb.write_char(c)
            lexer.bump()
          }
          _ => break
        }
      }
      if sb.is_empty() {
        raise LoveError::LexError(pos=start, "invalid hexadecimal literal")
      }
      let mut acc = 0L
      for c in sb.to_string() {
        let d = if is_digit(c) {
          c.to_int() - '0'.to_int()
        } else if c >= 'a' && c <= 'f' {
          c.to_int() - 'a'.to_int() + 10
        } else {
          c.to_int() - 'A'.to_int() + 10
        }
        acc = acc * 16L + d.to_int64()
      }
      return (Tok::IntTok(acc), start)
    }
  }
  let sb = StringBuilder()
  for ;; {
    match lexer.peek() {
      Some(c) if is_digit(c) => {
        sb.write_char(c)
        lexer.bump()
      }
      _ => break
    }
  }
  let mut is_float = false
  // 小数部分：'.' 后必须跟数字
  if lexer.peek() == Some('.') {
    let after = lexer.src.get_char(lexer.pos + 1)
    if after is Some(c2) && is_digit(c2) {
      is_float = true
      sb.write_char('.')
      lexer.bump()
      for ;; {
        match lexer.peek() {
          Some(c) if is_digit(c) => {
            sb.write_char(c)
            lexer.bump()
          }
          _ => break
        }
      }
    }
  }
  // 指数部分
  if lexer.peek() == Some('e') || lexer.peek() == Some('E') {
    is_float = true
    sb.write_char('e')
    lexer.bump()
    if lexer.peek() == Some('+') || lexer.peek() == Some('-') {
      match lexer.peek() {
        Some(c) => {
          sb.write_char(c)
          lexer.bump()
        }
        None => ()
      }
    }
    let mut has_digit = false
    for ;; {
      match lexer.peek() {
        Some(c) if is_digit(c) => {
          has_digit = true
          sb.write_char(c)
          lexer.bump()
        }
        _ => break
      }
    }
    if !has_digit {
      raise LoveError::LexError(pos=start, "invalid float literal")
    }
  }
  let text = sb.to_string()
  if is_float {
    let v : Double = @string.from_str(text) catch {
      _ =>
        raise LoveError::LexError(pos=start, "invalid float literal: \{text}")
    }
    (Tok::FloatTok(v), start)
  } else {
    let mut acc = 0L
    for c in text {
      acc = acc * 10L + (c.to_int() - '0'.to_int()).to_int64()
    }
    (Tok::IntTok(acc), start)
  }
}

///|
/// 引用原子 '...'（'' 转义）。
fn Lexer::lex_quoted(lexer : Lexer, start : Int) -> (Tok, Int) raise LoveError {
  lexer.bump()
  let sb = StringBuilder()
  for ;; {
    match lexer.peek() {
      None => raise LoveError::LexError(pos=start, "unterminated quoted atom")
      Some(c) =>
        if c == '\'' {
          lexer.bump()
          if lexer.peek() == Some('\'') {
            sb.write_char('\'')
            lexer.bump()
          } else {
            break
          }
        } else {
          sb.write_char(c)
          lexer.bump()
        }
    }
  }
  (Tok::QuotedAtom(sb.to_string()), start)
}

///|
/// 字符串 "..."（\n \t \r \\ \" 转义）。
fn Lexer::lex_string(lexer : Lexer, start : Int) -> (Tok, Int) raise LoveError {
  lexer.bump()
  let sb = StringBuilder()
  for ;; {
    match lexer.peek() {
      None => raise LoveError::LexError(pos=start, "unterminated string")
      Some(c) =>
        if c == '"' {
          lexer.bump()
          break
        } else if c == '\\' {
          lexer.bump()
          match lexer.peek() {
            None => raise LoveError::LexError(pos=start, "unterminated string")
            Some(e) => {
              lexer.bump()
              match e {
                'n' => sb.write_char('\n')
                't' => sb.write_char('\t')
                'r' => sb.write_char('\r')
                '\\' => sb.write_char('\\')
                '"' => sb.write_char('"')
                _ =>
                  raise LoveError::LexError(
                    pos=start,
                    "unknown escape sequence: \\\{e}",
                  )
              }
            }
          }
        } else {
          sb.write_char(c)
          lexer.bump()
        }
    }
  }
  (Tok::StrTok(sb.to_string()), start)
}

///|
/// 符号串（最大吞噬 graphic 字符）；单独的 '.' 后跟空白/EOF/% 作为子句结束符。
fn Lexer::lex_symbol(lexer : Lexer, start : Int) -> (Tok, Int) {
  let sb = StringBuilder()
  for ;; {
    match lexer.peek() {
      Some(c) if is_graphic(c) && !is_solo(c) => {
        sb.write_char(c)
        lexer.bump()
      }
      _ => break
    }
  }
  let sym = sb.to_string()
  if sym == "." {
    match lexer.peek() {
      None => (Tok::Dot, start)
      Some(c) =>
        if c.is_whitespace() || c == '%' {
          (Tok::Dot, start)
        } else {
          (Tok::Sym("."), start)
        }
    }
  } else {
    (Tok::Sym(sym), start)
  }
}
