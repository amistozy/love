///|
/// 将项格式化为 Love 源码字符串。
pub fn format_term(t : LoveTerm) -> String {
  fmt(t, {})
}

///|
/// 带变量名表格式化（显示查询变量名）。
pub fn format_term_with_names(t : LoveTerm, names : Map[Int, String]) -> String {
  fmt(t, names)
}

///|
/// fmt(t, names)：把 t 当作"允许包含优先级 <= 自身"的完整项打印。
/// 仅当 t 的顶层运算符优先级高于上下文要求时才加括号。
fn fmt(t : LoveTerm, names : Map[Int, String]) -> String {
  match t {
    LoveTerm::Var(id) =>
      match names.get(id) {
        None => "_\{id}"
        Some(n) => n
      }
    LoveTerm::Atom(name) => format_atom(name)
    LoveTerm::Int(x) => x.to_string()
    LoveTerm::Float(x) => format_float(x)
    LoveTerm::Str(s) => format_string(s)
    LoveTerm::ListNil => "[]"
    LoveTerm::ListCons(_, _) => format_list(t, names)
    LoveTerm::Struct(name, args) => format_struct(name, args, names)
  }
}

///|
/// 运算符优先级：复合项中 name 为运算符且元数匹配时返回优先级，否则 0。
fn op_priority(name : String, arity : Int) -> Int {
  match op_table().get(name) {
    None => 0
    Some(od) =>
      if arity == 2 {
        match od.infix {
          Some((p, _)) => p
          None => 0
        }
      } else if arity == 1 {
        match od.prefix {
          Some(p) => p
          None => 0
        }
      } else {
        0
      }
  }
}

///|
fn format_struct(
  name : String,
  args : Array[LoveTerm],
  names : Map[Int, String],
) -> String {
  match args {
    [a, b] =>
      match op_table().get(name) {
        Some(od) =>
          match od.infix {
            Some((prec, spec)) => {
              let (lctx, rctx) = match spec {
                OpSpec::XFX => (prec - 1, prec - 1)
                OpSpec::YFX => (prec, prec - 1)
                OpSpec::XFY => (prec - 1, prec)
              }
              let ls = fmt_operand(a, names, lctx)
              let rs = fmt_operand(b, names, rctx)
              if name == "," {
                "\{ls}, \{rs}"
              } else if name == ";" {
                "\{ls} ; \{rs}"
              } else {
                "\{ls} \{name} \{rs}"
              }
            }
            None => "\{format_atom(name)}(\{join_args(args, names)})"
          }
        None => "\{format_atom(name)}(\{join_args(args, names)})"
      }
    [a] =>
      match op_table().get(name) {
        Some(od) =>
          match od.prefix {
            Some(prec) => {
              let operand = fmt_operand(a, names, prec)
              if name == "-" || name == "+" {
                "\{name}\{operand}"
              } else {
                "\{name} \{operand}"
              }
            }
            None => "\{format_atom(name)}(\{join_args(args, names)})"
          }
        None => "\{format_atom(name)}(\{join_args(args, names)})"
      }
    _ => "\{format_atom(name)}(\{join_args(args, names)})"
  }
}

///|
fn join_args(args : Array[LoveTerm], names : Map[Int, String]) -> String {
  let parts : Array[String] = []
  for a in args {
    parts.push(fmt_operand(a, names, 999))
  }
  parts.join(", ")
}

///|
/// 以操作数上下文（最大允许优先级 ctx）打印项，必要时加括号。
fn fmt_operand(t : LoveTerm, names : Map[Int, String], ctx : Int) -> String {
  match t {
    LoveTerm::Struct(name, args) => {
      let p = op_priority(name, args.length())
      let inner = format_struct(name, args, names)
      if p > 0 && p > ctx {
        "(\{inner})"
      } else {
        inner
      }
    }
    _ => fmt(t, names)
  }
}

///|
fn format_list(t : LoveTerm, names : Map[Int, String]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  let mut cur = t
  let mut first = true
  for ;; {
    match cur {
      LoveTerm::ListNil => break
      LoveTerm::ListCons(h, tl) => {
        if !first {
          sb.write_string(", ")
        }
        first = false
        sb.write_string(fmt_operand(h, names, 999))
        cur = tl
      }
      other => {
        sb.write_string(" | ")
        sb.write_string(fmt(other, names))
        break
      }
    }
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn format_atom(name : String) -> String {
  // 运算符原子与特殊原子原样打印
  if op_table().contains(name) || name == "!" || name == "[]" || name == "." {
    return name
  }
  // 需要引号：非小写开头的字母数字串
  let needs_quote = if name.is_empty() {
    true
  } else {
    let c = name[0]
    let first_ok = c >= 'a'.to_int().to_uint16() &&
      c <= 'z'.to_int().to_uint16()
    let mut rest_ok = true
    if first_ok {
      for i in 1..<name.length() {
        let u = name[i]
        let ok = (
            u >= 'a'.to_int().to_uint16() && u <= 'z'.to_int().to_uint16()
          ) ||
          (u >= 'A'.to_int().to_uint16() && u <= 'Z'.to_int().to_uint16()) ||
          (u >= '0'.to_int().to_uint16() && u <= '9'.to_int().to_uint16()) ||
          u == '_'.to_int().to_uint16()
        if !ok {
          rest_ok = false
          break
        }
      }
    }
    !(first_ok && rest_ok)
  }
  if needs_quote {
    let sb = StringBuilder()
    sb.write_char('\'')
    for c in name {
      if c == '\'' {
        sb.write_char('\'')
      }
      sb.write_char(c)
    }
    sb.write_char('\'')
    sb.to_string()
  } else {
    name
  }
}

///|
fn format_string(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// 浮点数显示：整数浮点补 ".0"。
fn format_float(x : Double) -> String {
  let s = x.to_string()
  if s.contains(".") ||
    s.contains("e") ||
    s.contains("E") ||
    s.contains("inf") ||
    s.contains("nan") {
    s
  } else {
    "\{s}.0"
  }
}

///|
/// 格式化子句：`head :- body.` 或 `head.`。
pub fn format_clause(c : Clause) -> String {
  let head = format_term(c.head)
  match c.body {
    LoveTerm::Atom("true") => "\{head}."
    body => "\{head} :- \{format_term(body)}."
  }
}
