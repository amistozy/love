///|
/// Love 的运算符表（不支持动态 op/3 声明，运算符为语言内置）。
///
/// 优先级遵循 ISO Prolog 惯例：**数字越大越松散**。
/// 结合性 spec 决定了操作数的优先级约束：
///
/// - `xfx` 非结合：两侧操作数优先级都严格低于运算符
/// - `xfy` 右结合：左侧严格低于，右侧可等于
/// - `yfx` 左结合：右侧严格低于，左侧可等于
/// - `fx` / `fy` 前缀：`fx` 参数严格低于，`fy` 参数可等于
priv enum Assoc {
  Xfx
  Xfy
  Yfx
  Fy
}

///|
priv struct Op {
  prec : Int
  assoc : Assoc
}

///|
/// 中缀运算符表
fn infix_ops() -> Map[String, Op] {
  {
    ":-": { prec: 1200, assoc: Xfx },
    ";": { prec: 1100, assoc: Xfy },
    ",": { prec: 1000, assoc: Xfy },
    "=": { prec: 700, assoc: Xfx },
    "\\=": { prec: 700, assoc: Xfx },
    "==": { prec: 700, assoc: Xfx },
    "\\==": { prec: 700, assoc: Xfx },
    "<": { prec: 700, assoc: Xfx },
    ">": { prec: 700, assoc: Xfx },
    "=<": { prec: 700, assoc: Xfx },
    ">=": { prec: 700, assoc: Xfx },
    "=:=": { prec: 700, assoc: Xfx },
    "=\\=": { prec: 700, assoc: Xfx },
    "is": { prec: 700, assoc: Xfx },
    ":": { prec: 700, assoc: Xfx },
    "^": { prec: 200, assoc: Xfy },
    "+": { prec: 500, assoc: Yfx },
    "-": { prec: 500, assoc: Yfx },
    "*": { prec: 400, assoc: Yfx },
    "/": { prec: 400, assoc: Yfx },
    "//": { prec: 400, assoc: Yfx },
    "mod": { prec: 400, assoc: Xfx },
  }
}

///|
/// 前缀运算符表。
/// `let`/`del` 优先级（1300）高于 `:-`（1200），因此 `let Head :- Body.`
/// 无需括号即可把整个规则作为参数（REPL 便利，谓词定义中不使用它们）。
fn prefix_ops() -> Map[String, Op] {
  {
    "\\+": { prec: 900, assoc: Fy },
    "-": { prec: 200, assoc: Fy },
    "let": { prec: 1300, assoc: Fy },
    "del": { prec: 1300, assoc: Fy },
  }
}

///|
/// 查询某符号是否为中缀运算符，返回 (优先级, 结合性)
fn infix_op(name : String) -> (Int, Assoc)? {
  match infix_ops().get(name) {
    Some(op) => Some((op.prec, op.assoc))
    None => None
  }
}

///|
/// 查询某符号是否为前缀运算符，返回 (优先级, 结合性)
fn prefix_op(name : String) -> (Int, Assoc)? {
  match prefix_ops().get(name) {
    Some(op) => Some((op.prec, op.assoc))
    None => None
  }
}

///|
/// 取复合项根运算符的优先级；非运算符项为 0
fn root_prec(t : Term) -> Int {
  match t {
    Compound(name, _) =>
      match infix_op(name) {
        Some((prec, _)) => prec
        None => 0
      }
    _ => 0
  }
}
