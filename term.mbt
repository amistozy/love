///|
/// Love 语言中的项（term）——与 Prolog 相同，语言中所有数据都是项：
/// 整数、原子、变量、复合项（functor + 参数）。
pub(all) enum Term {
  /// 整数常量
  Int(Int)
  /// 原子：小写标识符、`'引号原子'`、`[]`、运算符符号、`!` 等
  Atom(String)
  /// 变量：大写字母或 `_` 开头
  Var(String)
  /// 复合项：`f(a, b)`，或运算符项 `a + b`（functor 为运算符符号）
  Compound(String, Array[Term])
}

///|
/// 环境（substitution）：变量名 -> 项的映射。
/// 采用**持久化不可变 HashMap**（`@immut/hashmap`）：每次绑定返回新环境，
/// 结构共享、回溯分支天然相互独立，因此引擎无需 trail。
pub type Env = @hashmap.HashMap[String, Term]

///|
/// 收集项中出现的变量名（去重，保持出现顺序）
pub fn collect_vars(t : Term, out : Array[String]) -> Unit {
  match t {
    Var(name) =>
      if !name.has_prefix("_#") && !out.contains(name) {
        out.push(name)
      }
    Compound(_, args) =>
      for a in args {
        collect_vars(a, out)
      }
    _ => ()
  }
}

///|
/// 判断原子是否需要引号才能正确回读：
/// 合法裸原子为小写字母开头的标识符，且非运算符名（`is`/`mod`/`not` 等
/// 在参数位置可能产生歧义，统一加引号保证回读正确）。
fn atom_needs_quote(s : String) -> Bool {
  if s.is_empty() {
    return true
  }
  if s is "[]" {
    // 空列表是合法的裸原子
    return false
  }
  if !(s[0] is ('a'..='z')) {
    return true
  }
  for i in 0..<s.length() {
    let c = s[i]
    if !(c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_')) {
      return true
    }
  }
  if infix_op(s) is Some(_) || prefix_op(s) is Some(_) {
    return true
  }
  false
}

///|
/// 写出原子（必要时加单引号并转义）
fn write_atom(s : String, sb : StringBuilder, quote : Bool) -> Unit {
  if !quote || !atom_needs_quote(s) {
    sb.write_string(s)
    return
  }
  sb.write_char('\'')
  for c in s {
    match c {
      '\'' => sb.write_string("\\'")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('\'')
}

///|
/// 写列表 `[a, b, c]` 或 `[a, b | t]`。调用前 t 已 walk 且为 `.`/`[]` 链。
fn write_list(t : Term, env : Env, sb : StringBuilder, quote : Bool) -> Unit {
  sb.write_char('[')
  let mut cur = t
  let mut first = true
  for ;; {
    let w = walk(cur, env)
    match w {
      Atom("[]") => break
      Compound(".", [h, tl]) => {
        if !first {
          sb.write_string(",")
        }
        first = false
        write_term(h, env, sb, 1001, quote)
        let wl = walk(tl, env)
        match wl {
          Atom("[]") => cur = wl
          Compound(".", _) => cur = wl
          _ => {
            sb.write_string("|")
            write_term(wl, env, sb, 1001, quote)
            break
          }
        }
      }
      _ => {
        // 非列表结构（如 .(a, b)）：打印为 | tail
        if !first {
          sb.write_string("|")
        }
        write_term(w, env, sb, 1001, quote)
        break
      }
    }
  }
  sb.write_char(']')
}

///|
/// 以 Prolog 风格写出项（在环境上展开变量绑定）。
/// `min_prec` 是父上下文允许的最大优先级；根运算符更松（优先级更大）时加括号。
pub fn write_term(
  t : Term,
  env : Env,
  sb : StringBuilder,
  min_prec : Int,
  quote : Bool,
) -> Unit {
  let w = walk(t, env)
  match w {
    Int(n) => sb.write_string(n.to_string())
    Atom(a) => write_atom(a, sb, quote)
    Var(n) =>
      if n.has_prefix("_#") {
        sb.write_string("_")
      } else {
        sb.write_string(n)
      }
    Compound(".", [_, _]) => write_list(w, env, sb, quote)
    Compound(name, args) =>
      match infix_op(name) {
        Some((_, _)) if args.length() == 2 =>
          write_infix(w, env, sb, min_prec, quote)
        _ =>
          match prefix_op(name) {
            Some((_, _)) if args.length() == 1 =>
              write_prefix(w, env, sb, min_prec, quote)
            _ => {
              sb.write_string(name)
              if args.length() > 0 {
                sb.write_char('(')
                for i in 0..<args.length() {
                  if i > 0 {
                    sb.write_string(",")
                  }
                  write_term(args[i], env, sb, 999, quote)
                }
                sb.write_char(')')
              }
            }
          }
      }
  }
}

///|
/// 中缀运算符项的写出
fn write_infix(
  w : Term,
  env : Env,
  sb : StringBuilder,
  min_prec : Int,
  quote : Bool,
) -> Unit {
  match w {
    Compound(name, [l, r]) =>
      match infix_op(name) {
        Some((prec, assoc)) => {
          let paren = prec > min_prec
          if paren {
            sb.write_char('(')
          }
          let left_prec = if assoc is Yfx { prec } else { prec - 1 }
          let right_prec = if assoc is Xfy { prec } else { prec - 1 }
          write_term(l, env, sb, left_prec, quote)
          sb.write_string(name)
          write_term(r, env, sb, right_prec, quote)
          if paren {
            sb.write_char(')')
          }
        }
        None => abort("not infix")
      }
    _ => abort("unreachable")
  }
}

///|
/// 前缀运算符项的写出
fn write_prefix(
  w : Term,
  env : Env,
  sb : StringBuilder,
  min_prec : Int,
  quote : Bool,
) -> Unit {
  match w {
    Compound(name, [a]) =>
      match prefix_op(name) {
        Some((prec, _)) => {
          let paren = prec > min_prec
          if paren {
            sb.write_char('(')
          }
          sb.write_string(name)
          sb.write_string(" ")
          write_term(a, env, sb, prec - 1, quote)
          if paren {
            sb.write_char(')')
          }
        }
        None => abort("not prefix")
      }
    _ => abort("unreachable")
  }
}

///|
/// 把项渲染为字符串（在环境上展开）
pub fn term_to_string(t : Term, env : Env) -> String {
  let sb = StringBuilder()
  write_term(t, env, sb, 1200, true)
  sb.to_string()
}

///|
/// 把项渲染为字符串（write 内建语义：原子不加引号，变量按绑定展开）
pub fn term_to_string_plain(t : Term, env : Env) -> String {
  let sb = StringBuilder()
  write_term(t, env, sb, 1200, false)
  sb.to_string()
}

///|
/// 写出一个子句：`Head :- Body.` 或 `Head.`（不展开变量，用于调试）
pub fn clause_to_string(head : Term, body : Array[Term]) -> String {
  let sb = StringBuilder()
  write_term(head, @hashmap.HashMap::new(), sb, 1200, true)
  if body.length() > 0 {
    sb.write_string(" :- ")
    for i in 0..<body.length() {
      if i > 0 {
        sb.write_string(",")
      }
      write_term(body[i], @hashmap.HashMap::new(), sb, 1000, true)
    }
  }
  sb.write_string(".")
  sb.to_string()
}
