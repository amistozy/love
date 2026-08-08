///|
/// Love 的语法分析器：递归下降 + 运算符优先级爬升。
///
/// 核心函数 `parse_term(max_prec)` 解析一个项，只允许根运算符
/// 优先级 <= max_prec 的组合。结合性通过操作数优先级约束实现：
///
/// - `yfx`（左结合）：右侧操作数优先级 < p（即解析时用 p-1）
/// - `xfy`（右结合）：右侧操作数优先级 <= p
/// - `xfx`（非结合）：左右操作数优先级 < p；同优先级再次出现时停止
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int
  mut anon : Int
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.tokens[self.pos]
}

///|
fn Parser::advance(self : Parser) -> Token {
  let t = self.tokens[self.pos]
  self.pos = self.pos + 1
  t
}

///|
/// 解析完整程序：一个或多个以 `.` 结尾的子句
pub fn parse_program_text(src : String) -> Array[Clause] raise LoveError {
  let tokens = lex(src)
  let p = { tokens, pos: 0, anon: 0 }
  let clauses = []
  for ;; {
    match p.peek() {
      Token::Eof => break
      _ => {
        let clause = p.parse_clause()
        clauses.push(clause)
      }
    }
  }
  clauses
}

///|
/// 解析单个子句：`Head :- Body.` 或 `Fact.`
pub fn parse_clause_text(src : String) -> Clause raise LoveError {
  let tokens = lex(src)
  let p = { tokens, pos: 0, anon: 0 }
  let clause = p.parse_clause()
  p.expect_eof()
  clause
}

///|
/// 解析查询：`?- Goal.`（`?-` 与结尾 `.` 均可省略）
pub fn parse_query_text(src : String) -> @list.List[Term] raise LoveError {
  let tokens = lex(src)
  let p = { tokens, pos: 0, anon: 0 }
  let t = p.parse_term(1300)
  let goals = flatten_list(t)
  match p.peek() {
    Token::Symbol(".") => {
      let _ = p.advance()
    }
    _ => ()
  }
  p.expect_eof()
  goals
}

///|
/// 解析一个子句（假设 token 流已就绪）
fn Parser::parse_clause(self : Parser) -> Clause raise LoveError {
  let head = self.parse_term(1199)
  let mut body : @list.List[Term] = @list.empty()
  match self.peek() {
    Token::Symbol(":-") => {
      let _ = self.advance()
      let t = self.parse_term(1199)
      body = flatten_list(t)
    }
    _ => ()
  }
  match self.peek() {
    Token::Symbol(".") => {
      let _ = self.advance()
    }
    _ => raise love_error("expected '.' at end of clause")
  }
  { head, body }
}

///|
/// 把 `,` 复合项扁平化为目标迭代器（惰性展平：递归直接 `flat_map(flatten)`，
/// 全程不构造中间 List，只有最终物化一次）。
fn flatten(t : Term) -> Iter[Term] {
  match t {
    Compound(",", args) => args.iter().flat_map(flatten)
    _ => Iter::singleton(t)
  }
}

///|
/// 物化为目标列表（调用方都需要完整 goals 队列）
fn flatten_list(t : Term) -> @list.List[Term] {
  @list.List::from_iter(flatten(t))
}

///|
/// 取当前 token 作为中缀运算符：返回 (符号, 优先级, 结合性)
fn peek_infix(p : Parser) -> (String, Int, Assoc)? {
  let name = match p.peek() {
    Token::Symbol(s) => Some(s)
    Token::Name(s) => Some(s)
    _ => None
  }
  match name {
    Some(s) =>
      match infix_op(s) {
        Some((prec, assoc)) => Some((s, prec, assoc))
        None => None
      }
    None => None
  }
}

///|
/// 取当前 token 作为前缀运算符：返回 (符号, 优先级, 结合性)
fn peek_prefix(p : Parser) -> (String, Int, Assoc)? {
  let name = match p.peek() {
    Token::Symbol(s) => Some(s)
    Token::Name(s) => Some(s)
    _ => None
  }
  match name {
    Some(s) =>
      match prefix_op(s) {
        Some((prec, assoc)) => Some((s, prec, assoc))
        None => None
      }
    None => None
  }
}

///|
/// 解析项：`max_prec` 为该位置允许的最大运算符优先级
fn Parser::parse_term(self : Parser, max_prec : Int) -> Term raise LoveError {
  self.parse_term_marked(max_prec).0
}

///|
/// 解析项并返回是否括号包裹。括号项优先级最高，后续中缀结合检查跳过它
/// （ISO：括号隔离优先级，如 `(A ; B), C` 中 `;` 不受 `,` 结合约束）。
fn Parser::parse_term_marked(
  self : Parser,
  max_prec : Int,
) -> (Term, Bool) raise LoveError {
  let (l0, b0) = self.parse_prefix_marked(max_prec)
  let mut left = l0
  let mut bracketed = b0
  for ;; {
    match peek_infix(self) {
      None => break (left, bracketed)
      Some((name, prec, assoc)) => {
        if prec > max_prec {
          break (left, bracketed)
        }
        // 括号项可被任何运算符吸收；否则按左操作数优先级检查
        let left_ok = bracketed ||
          (match assoc {
            Yfx => root_prec(left) <= prec
            _ => root_prec(left) < prec
          })
        if !left_ok {
          break (left, bracketed)
        }
        let _ = self.advance()
        let right_max = match assoc {
          Xfy => prec
          _ => prec - 1
        }
        let (right, _) = self.parse_term_marked(right_max)
        left = Compound(name, [left, right])
        bracketed = false
      }
    }
  }
}

///|
/// 解析前缀运算符或基本项。
/// 仅在 `prec <= max_prec` 时吸收（ISO：`X = \+ 1` 中 `\+` 900 超过
/// `=` 右操作数 699 的允许范围，报语法错误；顶层 max_prec 1300 允许 let）。

///|
fn Parser::parse_prefix_marked(
  self : Parser,
  max_prec : Int,
) -> (Term, Bool) raise LoveError {
  match peek_prefix(self) {
    Some((name, prec, assoc)) =>
      if prec <= max_prec {
        let _ = self.advance()
        let arg_max = match assoc {
          Fy => prec
          _ => prec - 1
        }
        let (arg, _) = self.parse_term_marked(arg_max)
        (Compound(name, [arg]), false)
      } else {
        self.parse_primary_marked()
      }
    None => self.parse_primary_marked()
  }
}

///|
/// 解析基本项：原子 / 变量 / 整数 / 括号 / 列表 / `!`

///|
fn Parser::parse_primary_marked(self : Parser) -> (Term, Bool) raise LoveError {
  match self.peek() {
    Token::Name(s) => {
      let _ = self.advance()
      if is_var_name(s) {
        if s is "_" {
          self.anon = self.anon + 1
          return (Var("_#\{self.anon}"), false)
        }
        (Var(s), false)
      } else {
        match self.peek() {
          Token::OpenCT => (Compound(s, self.parse_args()), false)
          _ => (Atom(s), false)
        }
      }
    }
    Token::Quoted(s) => {
      let _ = self.advance()
      match self.peek() {
        Token::OpenCT => (Compound(s, self.parse_args()), false)
        _ => (Atom(s), false)
      }
    }
    Token::Int(n) => {
      let _ = self.advance()
      (Int(n), false)
    }
    Token::OpenCT | Token::Symbol("(") => {
      let _ = self.advance()
      // 括号内允许任意项（含 let 1300）
      let (t, _) = self.parse_term_marked(1300)
      self.expect(")")
      // 括号项标记：后续中缀结合检查跳过它（优先级隔离）
      (t, true)
    }
    Token::Symbol("[") => (self.parse_list(), false)
    Token::Symbol("!") => {
      let _ = self.advance()
      (Atom("!"), false)
    }
    Token::Symbol(s) if is_op_name(s) => {
      // 函数记法：运算符名作复合项 functor，如 `+(2,3)`、`=(X, Y)`
      let _ = self.advance()
      match self.peek() {
        Token::OpenCT => (Compound(s, self.parse_args()), false)
        _ => raise love_error("expected a term")
      }
    }
    _ => raise love_error("expected a term")
  }
}

///|
/// 判断标识符是否为变量名（大写字母或 `_` 开头）
fn is_var_name(s : String) -> Bool {
  let c = s[0]
  (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// 判断符号是否为运算符名（函数记法 `+(2,3)` 需要）
fn is_op_name(s : String) -> Bool {
  infix_op(s) is Some(_) || prefix_op(s) is Some(_)
}

///|
/// 解析列表 `[a, b, c]` / `[a, b | t]` / `[]`，构造 `.`/`[]` 链
fn Parser::parse_list(self : Parser) -> Term raise LoveError {
  self.expect("[")
  if self.peek() is Token::Symbol("]") {
    let _ = self.advance()
    return Atom("[]")
  }
  let elems = []
  for ;; {
    elems.push(self.parse_term(999))
    match self.peek() {
      Token::Symbol(",") => {
        let _ = self.advance()
      }
      _ => break
    }
  }
  let mut tail : Term = Atom("[]")
  match self.peek() {
    Token::Symbol("|") => {
      let _ = self.advance()
      tail = self.parse_term(999)
    }
    _ => ()
  }
  self.expect("]")
  for acc = tail, i = elems.length() - 1; i >= 0; {
    continue Compound(".", [elems[i], acc]), i - 1
  } nobreak {
    acc
  }
}

///|
/// 解析函数参数：`(a, b, c)`。`(` 必须紧凑（OpenCT）——调用方只有
/// `Token::OpenCT => Compound(s, parse_args())` 一个入口，`foo (a)` 不经过这里
fn Parser::parse_args(self : Parser) -> Array[Term] raise LoveError {
  match self.peek() {
    Token::OpenCT => {
      let _ = self.advance()
    }
    _ => raise love_error("expected '('")
  }
  let args = []
  for ;; {
    args.push(self.parse_term(999))
    match self.peek() {
      Token::Symbol(",") => {
        let _ = self.advance()
      }
      _ => break
    }
  }
  self.expect(")")
  args
}

///|
/// 断言下一个 token 是指定符号并消费
fn Parser::expect(self : Parser, sym : String) -> Unit raise LoveError {
  match self.peek() {
    Token::Symbol(s) if s == sym => {
      let _ = self.advance()
    }
    _ => raise love_error("expected '\{sym}'")
  }
}

///|
/// 断言到达 token 流末尾
fn Parser::expect_eof(self : Parser) -> Unit raise LoveError {
  match self.peek() {
    Token::Eof => ()
    _ => raise love_error("unexpected trailing input")
  }
}
