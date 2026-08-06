///|
/// Love 的错误类型：词法 / 语法 / 算术求值失败统一携带消息。
pub(all) suberror LoveError {
  Msg(String)
}

///|
/// 取错误消息
pub fn LoveError::message(self : LoveError) -> String {
  match self {
    LoveError::Msg(m) => m
  }
}

///|
/// 构造一个 LoveError
fn love_error(msg : String) -> LoveError {
  LoveError::Msg(msg)
}

///|
/// 词法分析器：把源文本切成 token 流。
///
/// 支持的语法元素：
/// - 空白与注释（`%` 行注释、`/* ... */` 块注释）
/// - 标识符（变量 / 原子）、整数、单引号原子
/// - 符号运算符（最长匹配）
pub fn lex(src : String) -> Array[Token] raise LoveError {
  let tokens = []
  let mut pos = 0
  let len = src.length()
  while pos < len {
    let c = src[pos]
    // 空白
    if c is (' ' | '\t' | '\n' | '\r') {
      pos = pos + 1
      continue
    }
    // 注释
    if c is '%' {
      while pos < len && !(src[pos] is '\n') {
        pos = pos + 1
      }
      continue
    }
    if c is '/' && pos + 1 < len && src[pos + 1] is '*' {
      pos = pos + 2
      let mut closed = false
      while pos + 1 < len {
        if src[pos] is '*' && src[pos + 1] is '/' {
          pos = pos + 2
          closed = true
          break
        }
        pos = pos + 1
      }
      if !closed {
        raise love_error("unterminated block comment")
      }
      continue
    }
    // 标识符：变量或原子
    if c is ('a'..='z' | 'A'..='Z' | '_') {
      let start = pos
      while pos < len && src[pos] is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_') {
        pos = pos + 1
      }
      tokens.push(Token::Name(src[start:pos].to_owned()))
      continue
    }
    // 整数
    if c is ('0'..='9') {
      let start = pos
      while pos < len && src[pos] is ('0'..='9') {
        pos = pos + 1
      }
      let text = src[start:pos]
      tokens.push(Token::Int(parse_uint(text)))
      continue
    }
    // 单引号原子
    if c is '\'' {
      let (text, next) = lex_quoted(src, pos)
      tokens.push(Token::Quoted(text))
      pos = next
      continue
    }
    // 符号（最长匹配）
    match lex_symbol(src, pos) {
      Some((sym, next)) => {
        tokens.push(Token::Symbol(sym))
        pos = next
      }
      None => raise love_error("unexpected character at position \{pos}")
    }
  }
  tokens.push(Token::Eof)
  tokens
}

///|
/// 解析无符号十进制整数（token 已保证为纯数字）
fn parse_uint(text : StringView) -> Int {
  let mut n = 0
  for i in 0..<text.length() {
    let d = text[i] - ('0' : UInt16)
    n = n * 10 + d.to_int()
  }
  n
}

///|
/// 读取单引号原子，返回 (内容, 结束位置)
fn lex_quoted(src : String, start : Int) -> (String, Int) raise LoveError {
  let sb = StringBuilder()
  let mut pos = start + 1
  let len = src.length()
  let mut closed = false
  while pos < len {
    let c = src[pos]
    if c is '\'' {
      pos = pos + 1
      closed = true
      break
    }
    if c is '\\' {
      if pos + 1 >= len {
        raise love_error("unterminated quoted atom")
      }
      let e = src[pos + 1]
      match e {
        '\'' => sb.write_char('\'')
        '\\' => sb.write_char('\\')
        'n' => sb.write_char('\n')
        't' => sb.write_char('\t')
        'r' => sb.write_char('\r')
        _ => raise love_error("invalid escape \\\{e} in quoted atom")
      }
      pos = pos + 2
      continue
    }
    sb.write_char(Int::unsafe_to_char(c.to_int()))
    pos = pos + 1
  }
  if !closed {
    raise love_error("unterminated quoted atom")
  }
  (sb.to_string(), pos)
}

///|
/// 多字符符号（按长度降序，保证最长匹配）
let multi_symbols : Array[String] = [
  "?-", ":-", "=:=", "=\\=", "\\==", "\\=", "==", "=<", ">=", "\\+", "//",
]

///|
/// 单字符符号
let single_symbols : Array[String] = [
  ",", ";", "|", "!", "(", ")", "[", "]", ".", "=", "<", ">", "+", "-", "*", "/",
  "\\",
]

///|
/// 在 pos 处尝试匹配符号，返回 (符号, 结束位置)
fn lex_symbol(src : String, pos : Int) -> (String, Int)? {
  for sym in multi_symbols {
    if src[pos:].has_prefix(sym) {
      return Some((sym, pos + sym.length()))
    }
  }
  for sym in single_symbols {
    if src[pos:].has_prefix(sym) {
      return Some((sym, pos + sym.length()))
    }
  }
  None
}
