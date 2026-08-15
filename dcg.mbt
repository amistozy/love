///|
/// DCG（定子句文法）：把 `Head --> Body.` 展开为普通子句。
///
/// 差表（difference list）threading：S0 是输入列表，S 是输出列表。
/// 展开规则（与 ISO/SWI 一致的常用子集）：
///   - `[t1, ..., tn]`（终端列表）→ `S0 = [t1, ..., tn | S]`
///   - `[]` → `S0 = S`
///   - `{G}` → `G`（普通目标，不 threading）
///   - `!` → `!`
///   - `(A, B)` → `(A', B')`，A 用 (S0, S1)，B 用 (S1, S)
///   - `(A ; B)` → `(A' ; B')`，都保持 (S0, S)
///   - `(A -> B)` → `(A' -> B')`，条件用 (S0, S1)，then 用 (S1, S)
///   - `\+ G` → `(\+ G', S0 = S)`，G' 用 (S0, S1)（S1 全新）
///   - 非终结符 `p(A1..An)` → `p(A1..An, S0, S)`

///|
/// 翻译一条 DCG 规则为普通子句。
fn dcg_translate(
  parser : Parser,
  head : LoveTerm,
  body : LoveTerm,
) -> Clause raise LoveError {
  let s0 = LoveTerm::Var(parser.dcg_fresh())
  let s = LoveTerm::Var(parser.dcg_fresh())
  let head2 = dcg_head(head, s0, s)
  let body2 = dcg_body(parser, body, s0, s)
  { head: head2, body: body2 }
}

///|
/// 头部翻译：`p(A1..An)` → `p(A1..An, S0, S)`；原子 `p` → `p(S0, S)`。
fn dcg_head(
  head : LoveTerm,
  s0 : LoveTerm,
  s : LoveTerm,
) -> LoveTerm raise LoveError {
  match head {
    LoveTerm::Atom(nm) => LoveTerm::Struct(nm, [s0, s])
    LoveTerm::Struct(nm, args) => {
      let all = args.map(fn(a) { a })
      all.push(s0)
      all.push(s)
      LoveTerm::Struct(nm, all)
    }
    _ =>
      raise LoveError::ParseError(
        pos=0,
        "invalid DCG head: expected a callable term",
      )
  }
}

///|
/// 体翻译：差表 threading。
fn dcg_body(
  parser : Parser,
  t : LoveTerm,
  s0 : LoveTerm,
  s : LoveTerm,
) -> LoveTerm raise LoveError {
  match t {
    LoveTerm::Atom("!") => LoveTerm::Atom("!")
    LoveTerm::Atom("true") => LoveTerm::Struct("=", [s0, s])
    LoveTerm::Atom("fail") => LoveTerm::Atom("fail")
    LoveTerm::Atom(name) => LoveTerm::Struct(name, [s0, s])
    LoveTerm::ListNil => LoveTerm::Struct("=", [s0, s])
    LoveTerm::ListCons(_, _) => dcg_terminals(parser, t, s0, s)
    LoveTerm::Var(_) => LoveTerm::Struct("call", [t, s0, s])
    LoveTerm::Struct("{}", [g]) =>
      LoveTerm::Struct(",", [g, LoveTerm::Struct("=", [s0, s])])
    LoveTerm::Struct(",", [a, b]) => {
      let s1 = LoveTerm::Var(parser.dcg_fresh())
      LoveTerm::Struct(",", [
        dcg_body(parser, a, s0, s1),
        dcg_body(parser, b, s1, s),
      ])
    }
    LoveTerm::Struct(";", [Struct("->", [cond, then]), alt]) => {
      // (A -> B ; C)：条件 threading
      let s1 = LoveTerm::Var(parser.dcg_fresh())
      LoveTerm::Struct(";", [
        LoveTerm::Struct("->", [
          dcg_body(parser, cond, s0, s1),
          dcg_body(parser, then, s1, s),
        ]),
        dcg_body(parser, alt, s0, s),
      ])
    }
    LoveTerm::Struct(";", [a, b]) =>
      LoveTerm::Struct(";", [
        dcg_body(parser, a, s0, s),
        dcg_body(parser, b, s0, s),
      ])
    LoveTerm::Struct("->", [a, b]) => {
      let s1 = LoveTerm::Var(parser.dcg_fresh())
      LoveTerm::Struct("->", [
        dcg_body(parser, a, s0, s1),
        dcg_body(parser, b, s1, s),
      ])
    }
    LoveTerm::Struct("\\+", [g]) => {
      let s1 = LoveTerm::Var(parser.dcg_fresh())
      LoveTerm::Struct(",", [
        LoveTerm::Struct("\\+", [dcg_body(parser, g, s0, s1)]),
        LoveTerm::Struct("=", [s0, s]),
      ])
    }
    LoveTerm::Struct("call", [g]) => dcg_call(g, s0, s)
    LoveTerm::Struct("once", [g]) =>
      LoveTerm::Struct("once", [dcg_body(parser, g, s0, s)])
    LoveTerm::Struct(name, args) => {
      let all = args.map(fn(a) { a })
      all.push(s0)
      all.push(s)
      LoveTerm::Struct(name, all)
    }
    _ =>
      raise LoveError::ParseError(pos=0, "invalid DCG goal: \{format_term(t)}")
  }
}

///|
/// `call(G)` 作为 DCG 目标：G 可调用则追加 (S0, S)，否则元调用。
fn dcg_call(g : LoveTerm, s0 : LoveTerm, s : LoveTerm) -> LoveTerm {
  match g {
    LoveTerm::Atom(nm) => LoveTerm::Struct(nm, [s0, s])
    LoveTerm::Struct(nm, args) => {
      let all = args.map(fn(a) { a })
      all.push(s0)
      all.push(s)
      LoveTerm::Struct(nm, all)
    }
    _ => LoveTerm::Struct("call", [g, s0, s])
  }
}

///|
/// 终端列表：`[t1, ..., tn]` → `S0 = [t1, ..., tn | S]`；
/// 非规范列表 `[t1, ..., tn | T]` → `(S0 = [t1, ..., tn | S1], T'(S1, S))`。
fn dcg_terminals(
  parser : Parser,
  t : LoveTerm,
  s0 : LoveTerm,
  s : LoveTerm,
) -> LoveTerm raise LoveError {
  let elems : Array[LoveTerm] = []
  let mut cur = t
  let mut tail : LoveTerm? = None
  for ;; {
    match cur {
      LoveTerm::ListCons(h, tl) => {
        elems.push(h)
        cur = tl
      }
      LoveTerm::ListNil => break
      other => {
        tail = Some(other)
        break
      }
    }
  }
  match tail {
    None => LoveTerm::Struct("=", [s0, list_of_with_tail(elems, s)])
    Some(tl) => {
      let s1 = LoveTerm::Var(parser.dcg_fresh())
      LoveTerm::Struct(",", [
        LoveTerm::Struct("=", [s0, list_of_with_tail(elems, s1)]),
        dcg_body(parser, tl, s1, s),
      ])
    }
  }
}
