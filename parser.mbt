///|
/// 运算符结合性。
pub enum OpSpec {
  /// xfx：两侧都严格高于该优先级
  XFX
  /// xfy：左高右低（右结合）
  XFY
  /// yfx：左低右高（左结合）
  YFX
  /// fx：前缀，操作数优先级严格低于该优先级
  FX
  /// fy：前缀，操作数优先级可等于该优先级
  FY
}

///|
/// 一个符号的运算符定义。
pub struct OpDef {
  infix : (Int, OpSpec)?
  prefix : (Int, OpSpec)?
}

///|
/// 内置运算符表（与 ISO/SWI 兼容的常用子集）。
fn op_table() -> Map[String, OpDef] {
  let m : Map[String, OpDef] = Map([])
  let add_inf = fn(name : String, prec : Int, spec : OpSpec) {
    m[name] = { infix: Some((prec, spec)), prefix: None }
  }
  let add_pre = fn(name : String, prec : Int, spec : OpSpec) {
    m[name] = { infix: None, prefix: Some((prec, spec)) }
  }
  let add_both = fn(name : String, prec : Int, spec : OpSpec, pprec : Int) {
    m[name] = { infix: Some((prec, spec)), prefix: Some((pprec, OpSpec::FY)) }
  }
  add_both(":-", 1200, OpSpec::XFX, 1200)
  add_inf("-->", 1200, OpSpec::XFX)
  add_inf(";", 1100, OpSpec::XFY)
  add_inf("->", 1050, OpSpec::XFY)
  add_inf(",", 1000, OpSpec::XFY)
  add_pre("\\+", 900, OpSpec::FY)
  for
    n in [
      "=", "\\=", "==", "\\==", "@<", "@=<", "@>", "@>=", "is", "=:=", "=\\=", "<",
      "=<", ">", ">=", "=..",
    ] {
    add_inf(n, 700, OpSpec::XFX)
  }
  add_both("+", 500, OpSpec::YFX, 200)
  add_both("-", 500, OpSpec::YFX, 200)
  for n in ["*", "/", "//", "mod", "rem", "div"] {
    add_inf(n, 400, OpSpec::YFX)
  }
  add_inf("^", 200, OpSpec::XFY)
  add_pre("\\", 200, OpSpec::FY)
  m
}

///|
/// 顶层项：子句或指令。
priv enum TopLevel {
  Rule(Clause)
  Directive(LoveTerm)
}

///|
priv struct Parser {
  toks : Array[(Tok, Int)]
  mut i : Int
  mut var_counter : Int
  var_names : Map[Int, String]
  /// 子句/查询作用域内：变量名 -> id（同名变量共享 id）
  mut name_map : Map[String, Int]
  /// 运算符表（op/3 可动态修改；默认内置表）
  ops : Map[String, OpDef]
}

///|
fn Parser::new(src : String) -> Parser raise LoveError {
  Parser::new_with_ops(src, op_table())
}

///|
fn Parser::new_with_ops(
  src : String,
  ops : Map[String, OpDef],
) -> Parser raise LoveError {
  let lexer = Lexer::{ src, pos: 0 }
  let toks : Array[(Tok, Int)] = []
  for ;; {
    let (t, p) = lexer.next_token()
    toks.push((t, p))
    if t is Tok::Eof {
      break
    }
  }
  { toks, i: 0, var_counter: 0, var_names: Map([]), name_map: Map([]), ops }
}

///|
fn Parser::peek(parser : Parser) -> (Tok, Int) {
  if parser.i < parser.toks.length() {
    parser.toks[parser.i]
  } else {
    (Tok::Eof, 0)
  }
}

///|
fn Parser::peek_after(parser : Parser) -> Tok {
  if parser.i + 1 < parser.toks.length() {
    parser.toks[parser.i + 1].0
  } else {
    Tok::Eof
  }
}

///|
fn Parser::bump(parser : Parser) -> Unit {
  if parser.i < parser.toks.length() {
    parser.i += 1
  }
}

///|
fn Parser::expect_sym(parser : Parser, s : String) -> Bool {
  match parser.peek() {
    (Tok::Sym(x), _) if x == s => {
      parser.bump()
      true
    }
    _ => false
  }
}

///|
/// 解析操作数：可包含优先级 <= max_prio 的运算符。
fn Parser::parse_operand(
  parser : Parser,
  max_prio : Int,
) -> LoveTerm raise LoveError {
  let mut lhs = parser.parse_prefix_or_primary()
  for ;; {
    let op = parser.peek_infix_op()
    match op {
      None => break
      Some((name, prec, spec)) => {
        if prec > max_prio {
          break
        }
        parser.bump()
        let rhs_max = match spec {
          OpSpec::XFX => prec - 1
          OpSpec::YFX => prec - 1
          OpSpec::XFY => prec
          OpSpec::FX | OpSpec::FY => prec - 1
        }
        let rhs = parser.parse_operand(rhs_max)
        lhs = LoveTerm::Struct(name, [lhs, rhs])
      }
    }
  }
  lhs
}

///|
fn Parser::peek_infix_op(parser : Parser) -> (String, Int, OpSpec)? {
  let name = match parser.peek().0 {
    Tok::Ident(n) => Some(n)
    Tok::Sym(n) => Some(n)
    _ => None
  }
  match name {
    None => None
    Some(n) =>
      match parser.ops.get(n) {
        None => None
        Some(od) =>
          match od.infix {
            None => None
            Some((prec, spec)) => Some((n, prec, spec))
          }
      }
  }
}

///|
/// 前缀运算符或基本项；前缀运算符后紧跟 '(' 时按复合项处理。
fn Parser::parse_prefix_or_primary(parser : Parser) -> LoveTerm raise LoveError {
  let name = match parser.peek().0 {
    Tok::Ident(n) => Some(n)
    Tok::Sym(n) => Some(n)
    _ => None
  }
  match name {
    None => parser.parse_primary()
    Some(n) => {
      let pprec = match parser.ops.get(n) {
        Some(od) => od.prefix
        None => None
      }
      match pprec {
        None => parser.parse_primary()
        Some((prec, spec)) =>
          if parser.peek_after() is Tok::Sym("(") {
            parser.parse_functor(n)
          } else {
            parser.bump()
            // fx：操作数优先级严格低于 prec；fy：可等于 prec
            let operand_max = match spec {
              OpSpec::FX => prec - 1
              _ => prec
            }
            let operand = parser.parse_operand(operand_max)
            LoveTerm::Struct(n, [operand])
          }
      }
    }
  }
}

///|
/// 基本项：变量、数值、原子、字符串、括号、列表、复合项。
fn Parser::parse_primary(parser : Parser) -> LoveTerm raise LoveError {
  let (tok, pos) = parser.peek()
  match tok {
    Tok::VarTok(name) => {
      parser.bump()
      if name == "_" {
        // 匿名变量：每次出现都是全新变量
        let id = parser.var_counter
        parser.var_counter += 1
        LoveTerm::Var(id)
      } else {
        // 具名变量：同作用域内共享 id
        match parser.name_map.get(name) {
          Some(id) => LoveTerm::Var(id)
          None => {
            let id = parser.var_counter
            parser.var_counter += 1
            parser.name_map[name] = id
            parser.var_names[id] = name
            LoveTerm::Var(id)
          }
        }
      }
    }
    Tok::IntTok(v) => {
      parser.bump()
      LoveTerm::Int(v)
    }
    Tok::FloatTok(v) => {
      parser.bump()
      LoveTerm::Float(v)
    }
    Tok::StrTok(s) => {
      parser.bump()
      LoveTerm::Str(s)
    }
    Tok::QuotedAtom(s) => {
      parser.bump()
      LoveTerm::Atom(s)
    }
    Tok::Ident(name) =>
      if parser.peek_after() is Tok::Sym("(") {
        parser.parse_functor(name)
      } else {
        parser.bump()
        LoveTerm::Atom(name)
      }
    Tok::Sym("(") => {
      parser.bump()
      let t = parser.parse_operand(1200)
      if !parser.expect_sym(")") {
        raise LoveError::ParseError(pos~, "expected ')'")
      }
      t
    }
    Tok::Sym("{") => {
      // DCG 中的 {Goal}：解析为 Struct("{}", [Goal])
      parser.bump()
      let t = parser.parse_operand(1200)
      if !parser.expect_sym("}") {
        let (_, p2) = parser.peek()
        raise LoveError::ParseError(pos=p2, "expected '}'")
      }
      LoveTerm::Struct("{}", [t])
    }
    Tok::Sym("[") => parser.parse_list()
    Tok::Sym("!") => {
      parser.bump()
      LoveTerm::Atom("!")
    }
    Tok::Sym(name) =>
      if parser.peek_after() is Tok::Sym("(") {
        parser.parse_functor(name)
      } else {
        parser.bump()
        LoveTerm::Atom(name)
      }
    _ => raise LoveError::ParseError(pos~, "unexpected token")
  }
}

///|
/// 复合项 f(args...)。
fn Parser::parse_functor(
  parser : Parser,
  name : String,
) -> LoveTerm raise LoveError {
  parser.bump()
  parser.bump()
  let args : Array[LoveTerm] = []
  if parser.expect_sym(")") {
    return LoveTerm::Struct(name, args)
  }
  for ;; {
    args.push(parser.parse_operand(999))
    match parser.peek() {
      (Tok::Sym(","), _) => parser.bump()
      (Tok::Sym(")"), _) => {
        parser.bump()
        break
      }
      (_, p2) =>
        raise LoveError::ParseError(
          pos=p2,
          "expected ',' or ')' in arguments of \{name}",
        )
    }
  }
  LoveTerm::Struct(name, args)
}

///|
/// 列表 [a, b | T]。
fn Parser::parse_list(parser : Parser) -> LoveTerm raise LoveError {
  parser.bump()
  if parser.expect_sym("]") {
    return LoveTerm::ListNil
  }
  let els : Array[LoveTerm] = []
  for ;; {
    els.push(parser.parse_operand(999))
    match parser.peek() {
      (Tok::Sym(","), _) => parser.bump()
      (Tok::Sym("|"), _) => {
        parser.bump()
        let tail = parser.parse_operand(1200)
        if !parser.expect_sym("]") {
          let (_, p2) = parser.peek()
          raise LoveError::ParseError(pos=p2, "expected ']' after list tail")
        }
        return list_of_with_tail(els, tail)
      }
      (Tok::Sym("]"), _) => {
        parser.bump()
        break
      }
      (_, p2) =>
        raise LoveError::ParseError(pos=p2, "expected ',' or ']' in list")
    }
  }
  list_of(els)
}

///|
/// 解析整个程序并写入 program。
fn parse_program_into(program : Program, src : String) -> Unit raise LoveError {
  let parser = Parser::new(src)
  parser.parse_program_into(program)
}

///|
fn Parser::parse_program_into(
  parser : Parser,
  program : Program,
) -> Unit raise LoveError {
  for ;; {
    match parser.peek() {
      (Tok::Eof, _) => break
      _ => {
        let top = parser.parse_top_level()
        match top {
          TopLevel::Rule(clause) => program.add_source_clause(clause)
          TopLevel::Directive(g) => program.directives.push(g)
        }
      }
    }
  }
}

///|
/// 分配一个 DCG 翻译用的全新变量 id（不进入 name_map）。
fn Parser::dcg_fresh(parser : Parser) -> Int {
  let id = parser.var_counter
  parser.var_counter += 1
  id
}

///|
/// 解析一个顶层项（子句或指令），要求以 '.' 结束。
fn Parser::parse_top_level(parser : Parser) -> TopLevel raise LoveError {
  parser.name_map = Map([])
  let term = parser.parse_operand(1200)
  match parser.peek() {
    (Tok::Dot, _) => parser.bump()
    (_, pos) =>
      raise LoveError::ParseError(pos~, "expected '.' at end of clause")
  }
  match term {
    LoveTerm::Struct(":-", [h, b]) => TopLevel::Rule({ head: h, body: b })
    LoveTerm::Struct(":-", [b]) => TopLevel::Directive(b)
    LoveTerm::Struct("-->", [h, b]) =>
      TopLevel::Rule(dcg_translate(parser, h, b))
    other => TopLevel::Rule({ head: other, body: LoveTerm::Atom("true") })
  }
}

///|
/// 解析程序源码（自动注入内置库子句）。
pub fn parse_program(src : String) -> Program raise LoveError {
  let program = Program::empty()
  parse_program_into(program, src)
  program.seed_libraries()
  program
}

///|
/// 解析查询目标。可带可选的 `?-` 前缀，结尾 '.' 可省略。
pub fn parse_query(src : String) -> LoveTerm raise LoveError {
  let (t, _) = parse_query_with_names(src)
  t
}

///|
/// 解析查询目标（使用自定义运算符表 op/3 修改后）。
pub fn parse_query_with_ops(
  src : String,
  ops : Map[String, OpDef],
) -> LoveTerm raise LoveError {
  let (t, _) = parse_query_with_names_ops(src, ops)
  t
}

///|
/// 解析查询目标并返回查询中具名变量的 (id -> 名字) 表。
pub fn parse_query_with_names(
  src : String,
) -> (LoveTerm, Map[Int, String]) raise LoveError {
  parse_query_with_names_ops(src, op_table())
}

///|
/// 解析查询目标并返回具名变量表（使用自定义运算符表）。
pub fn parse_query_with_names_ops(
  src : String,
  ops : Map[String, OpDef],
) -> (LoveTerm, Map[Int, String]) raise LoveError {
  let parser = Parser::new_with_ops(src, ops)
  if parser.peek() is (Tok::Sym("?-"), _) {
    parser.bump()
  }
  parser.name_map = Map([])
  let term = parser.parse_operand(1200)
  match parser.peek() {
    (Tok::Dot, _) => parser.bump()
    (Tok::Eof, _) => ()
    (_, pos) => raise LoveError::ParseError(pos~, "trailing tokens after query")
  }
  (term, parser.var_names)
}

///|
/// 解析单个子句源码。
pub fn parse_clause(src : String) -> Clause raise LoveError {
  let parser = Parser::new(src)
  match parser.parse_top_level() {
    TopLevel::Rule(c) => c
    TopLevel::Directive(_) => {
      let (_, pos) = parser.peek()
      raise LoveError::ParseError(pos~, "expected a clause, got a directive")
    }
  }
}
