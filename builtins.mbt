///|
/// 内建谓词执行结果
priv enum BuiltinResult {
  /// 目标失败（触发回溯）
  Fail
  /// 目标成功，环境不变，推进到下一个目标
  Succeed
  /// 目标成功并更新环境
  SucceedEnv(Env)
  /// 目标成功，更新环境并前置额外目标
  /// 目标产生多个候选（析取 / member / length / append）：压入选择点，
  /// 立即尝试第一个候选
  Choice(Env, Array[Candidate])
}

///|
/// 算术求值：把项在环境中求值为整数
/// 支持 `+ - * / // mod` 及一元 `-`
fn eval_arith(t : Term, env : Env) -> Int raise LoveError {
  match walk(t, env) {
    Int(n) => n
    Var(_) => raise love_error("arithmetic: unbound variable")
    Atom(_) => raise love_error("arithmetic: not a number")
    Compound(op, args) =>
      match (op, args) {
        ("+", [a, b]) => eval_arith(a, env) + eval_arith(b, env)
        ("-", [a, b]) => eval_arith(a, env) - eval_arith(b, env)
        ("-", [a]) => -eval_arith(a, env)
        ("*", [a, b]) => eval_arith(a, env) * eval_arith(b, env)
        ("/", [a, b]) => int_div(eval_arith(a, env), eval_arith(b, env))
        ("//", [a, b]) => int_div(eval_arith(a, env), eval_arith(b, env))
        ("mod", [a, b]) => {
          let d = eval_arith(b, env)
          if d == 0 {
            raise love_error("arithmetic: division by zero")
          }
          eval_arith(a, env) % d
        }
        _ => raise love_error("arithmetic: unsupported operation '\{op}'")
      }
  }
}

///|
fn int_div(a : Int, b : Int) -> Int raise LoveError {
  if b == 0 {
    raise love_error("arithmetic: division by zero")
  }
  a / b
}

///|
/// 子会话求解是否有解（用于 `\+`，只求第一个解）
fn sub_has_solution(e : Engine, goals : Array[Term], env : Env) -> Bool {
  let sub = Engine::new(e.session, goals, env)
  sub.next_solution() is Some(_)
}

///|
/// 把项数组构造成 `.`/`[]` 链列表
fn make_list(terms : Array[Term]) -> Term {
  for acc = Atom("[]"), i = terms.length() - 1; i >= 0; {
    continue Compound(".", [terms[i], acc]), i - 1
  } nobreak {
    acc
  }
}

///|
/// 判断项是否为闭合列表（`[]` 或 `.` 链且尾为 `[]`）
fn is_closed_list(t : Term, env : Env) -> Bool {
  match walk(t, env) {
    Atom("[]") => true
    Compound(".", [_, tl]) => is_closed_list(tl, env)
    _ => false
  }
}

///|
/// 数闭合列表的元素个数
fn list_length(t : Term, env : Env) -> Int {
  match walk(t, env) {
    Atom("[]") => 0
    Compound(".", [_, tl]) => 1 + list_length(tl, env)
    _ => abort("not a closed list")
  }
}

///|
/// 生成长度为 `len` 的匿名变量列表。
/// 内部名用 `_#gN`（以 `_#` 开头，显示为 `_`），
/// 避免与解析器匿名变量 `_#N` 重名导致跨查询状态污染。
fn fresh_list(e : Engine, len : Int) -> Term {
  let mut acc : Term = Atom("[]")
  for _i in 0..<len {
    let v = Var(fresh_var_name(e, "_#g"))
    acc = Compound(".", [v, acc])
  }
  acc
}

///|
/// 内建谓词表：谓词键 -> 实现（接收参数数组）
fn builtin_table() -> Map[String, (Array[Term], Engine) -> BuiltinResult] {
  let table : Map[String, (Array[Term], Engine) -> BuiltinResult] = {
    "true/0": (_args, _e) => Succeed,
    "fail/0": (_args, _e) => Fail,
    "=/2": (args, e) => {
      guard args is [a, b] else { Fail }
      match unify(a, b, e.env) {
        Some(env) => SucceedEnv(env)
        None => Fail
      }
    },
    "\\=/2": (args, e) => {
      guard args is [a, b] else { Fail }
      match unify(a, b, e.env) {
        Some(_) => Fail
        None => Succeed
      }
    },
    "==/2": (args, e) => {
      guard args is [a, b] else { Fail }
      if term_identical(a, b, e.env) {
        Succeed
      } else {
        Fail
      }
    },
    "\\==/2": (args, e) => {
      guard args is [a, b] else { Fail }
      if term_identical(a, b, e.env) {
        Fail
      } else {
        Succeed
      }
    },
    "var/1": (args, e) => {
      guard args is [a] else { Fail }
      match walk(a, e.env) {
        Var(_) => Succeed
        _ => Fail
      }
    },
    "nonvar/1": (args, e) => {
      guard args is [a] else { Fail }
      match walk(a, e.env) {
        Var(_) => Fail
        _ => Succeed
      }
    },
    "atom/1": (args, e) => {
      guard args is [a] else { Fail }
      match walk(a, e.env) {
        Atom(_) => Succeed
        _ => Fail
      }
    },
    "integer/1": (args, e) => {
      guard args is [a] else { Fail }
      match walk(a, e.env) {
        Int(_) => Succeed
        _ => Fail
      }
    },
    "atomic/1": (args, e) => {
      guard args is [a] else { Fail }
      match walk(a, e.env) {
        Atom(_) | Int(_) => Succeed
        _ => Fail
      }
    },
    "compound/1": (args, e) => {
      guard args is [a] else { Fail }
      match walk(a, e.env) {
        Compound(_, _) => Succeed
        _ => Fail
      }
    },
    "ground/1": (args, e) => {
      guard args is [a] else { Fail }
      if is_ground(a, e.env) {
        Succeed
      } else {
        Fail
      }
    },
    "is/2": (args, e) => {
      guard args is [target, expr] else { Fail }
      try eval_arith(expr, e.env) catch {
        _ => Fail
      } noraise {
        n =>
          match unify(target, Int(n), e.env) {
            Some(env) => SucceedEnv(env)
            None => Fail
          }
      }
    },
    "=:=/2": (args, e) => arith_cmp(args, e, (x, y) => x == y),
    "=\\=/2": (args, e) => arith_cmp(args, e, (x, y) => x != y),
    "</2": (args, e) => arith_cmp(args, e, (x, y) => x < y),
    ">/2": (args, e) => arith_cmp(args, e, (x, y) => x > y),
    "=</2": (args, e) => arith_cmp(args, e, (x, y) => x <= y),
    ">=/2": (args, e) => arith_cmp(args, e, (x, y) => x >= y),
    "\\+/1": (args, e) => {
      guard args is [a] else { Fail }
      // 复用 call/1 执行任意目标（含 `,` 复合），
      // 等价于 Scryer 的 `\+ G :- call(G), !, '$fail'.`
      if sub_has_solution(e, [Compound("call", [a])], e.env) {
        Fail
      } else {
        Succeed
      }
    },
    ":/2": (args, e) => {
      // `X : [1,2,3]`：X 属于列表（member 的中缀运算符形式）
      guard args is [x, l] else { Fail }
      let h = Var(fresh_var_name(e, "H"))
      let t = Var(fresh_var_name(e, "T"))
      Choice(e.env, [
        Inline([(l, Compound(".", [x, t]))], []),
        Inline([(l, Compound(".", [h, t]))], [Compound(":", [x, t])]),
      ])
    },
    "length/2": (args, e) => {
      guard args is [l, n] else { Fail }
      let wl = walk(l, e.env)
      let wn = walk(n, e.env)
      if is_closed_list(wl, e.env) {
        // L 已闭合：直接计数
        let len = list_length(wl, e.env)
        match unify(n, Int(len), e.env) {
          Some(env) => SucceedEnv(env)
          None => Fail
        }
      } else {
        match wn {
          Int(len) if len >= 0
          // N 已绑定：生成长度为 len 的变量列表
          => {
            let list = fresh_list(e, len)
            match unify(l, list, e.env) {
              Some(env) => SucceedEnv(env)
              None => Fail
            }
          }
          // 通用递归展开（L 未闭合或 N 未绑定；可能无限枚举）
          _ => {
            let h = Var(fresh_var_name(e, "H"))
            let t = Var(fresh_var_name(e, "T"))
            let n1 = Var(fresh_var_name(e, "N"))
            Choice(e.env, [
              Inline([(l, Atom("[]")), (n, Int(0))], []),
              Inline([(l, Compound(".", [h, t]))], [
                Compound("length", [t, n1]),
                Compound("is", [n, Compound("+", [n1, Int(1)])]),
              ]),
            ])
          }
        }
      }
    },
    "append/3": (args, e) => {
      guard args is [a, b, c] else { Fail }
      let h = Var(fresh_var_name(e, "H"))
      let t1 = Var(fresh_var_name(e, "T1"))
      let r1 = Var(fresh_var_name(e, "R1"))
      Choice(e.env, [
        Inline([(a, Atom("[]")), (c, b)], []),
        Inline([(a, Compound(".", [h, t1])), (c, Compound(".", [h, r1]))], [
          Compound("append", [t1, b, r1]),
        ]),
      ])
    },
    "call/1": (args, e) => {
      // call(Goal) = 把 Goal 作为目标执行（`,` 复合展开为目标序列）
      guard args is [g] else { Fail }
      Choice(e.env, [Candidate::Inline([], flatten(g))])
    },
    "findall/3": (args, e) => {
      guard args is [t, goal, l] else { Fail }
      // 复用 call/1 执行任意目标（含 `,` 复合），
      // 等价于 Scryer 的 `'$iterate_find_all'` 里的 `call(Goal)`
      let envs = sub_solve_all(e, [Compound("call", [goal])], e.env)
      let terms = envs.map(env => walk_deep(t, env))
      let list = make_list(terms)
      match unify(l, list, e.env) {
        Some(env) => SucceedEnv(env)
        None => Fail
      }
    },
    "write/1": (args, e) => {
      guard args is [a] else { Fail }
      e.session.output.write_string(term_to_string_plain(a, e.env))
      Succeed
    },
    "writeln/1": (args, e) => {
      guard args is [a] else { Fail }
      e.session.output.write_string(term_to_string_plain(a, e.env))
      e.session.output.write_string("\n")
      Succeed
    },
    "nl/0": (_g, e) => {
      e.session.output.write_string("\n")
      Succeed
    },
    "atom_length/2": (args, e) => {
      guard args is [a, n] else { Fail }
      match walk(a, e.env) {
        Atom(s) =>
          match unify(n, Int(s.length()), e.env) {
            Some(env) => SucceedEnv(env)
            None => Fail
          }
        _ => Fail
      }
    },
    "char_code/2": (args, e) => {
      guard args is [c, code] else { Fail }
      let wc = walk(c, e.env)
      let wcode = walk(code, e.env)
      match (wc, wcode) {
        (Atom(s), _) if s.length() == 1 =>
          match unify(code, Int(s[0].to_int()), e.env) {
            Some(env) => SucceedEnv(env)
            None => Fail
          }
        (_, Int(n)) if n >= 0 && n <= 0x10FFFF => {
          let ch : Char = Int::unsafe_to_char(n)
          match unify(c, Atom(ch.to_string()), e.env) {
            Some(env) => SucceedEnv(env)
            None => Fail
          }
        }
        _ => Fail
      }
    },
    "let/1": (args, e) => {
      guard args is [t] else { Fail }
      let (head, body) = clause_parts(t)
      e.session.db.add_clause(head, body)
      Succeed
    },
    "del/1": (args, e) => {
      // 删除谓词指示符 `Name/Arity` 对应的全部子句（如 `del foo/2.`）
      guard args is [t] else { Fail }
      match walk_deep(t, @hashmap.HashMap::new()) {
        Compound("/", [Atom(name), Int(arity)]) =>
          if arity >= 0 && e.session.db.remove_predicate(name, arity) {
            Succeed
          } else {
            Fail
          }
        _ => Fail
      }
    },
    "cls/0": (_args, _e) => {
      // ANSI 清屏 + 光标归位（写入会话输出缓冲，REPL drain 时输出）。
      // 设置 quiet 标志，REPL 据此不显示 `true.`
      _e.session.output.write_string("\u{1b}[2J\u{1b}[H")
      _e.session.quiet = true
      Succeed
    },
    "halt/0": (_args, _e) => {
      // 请求退出（REPL 检查 Session::halt_requested）
      _e.session.halt = true
      Succeed
    },
    "consult/1": (args, e) => {
      guard args is [t] else { Fail }
      match walk(t, e.env) {
        Atom(name) => consult_load(e, name)
        _ => Fail
      }
    },
  }
  table
}

///|
/// `consult/1` 的实现：读取 `name.love` 并把子句加载进数据库
fn consult_load(e : Engine, name : String) -> BuiltinResult {
  let path = name + ".love"
  match read_file_safe(path) {
    Some(content) =>
      if load_program_safe(e.session.db, content) {
        Succeed
      } else {
        Fail
      }
    None => Fail
  }
}

///|
/// 读取文件，失败返回 `None`（文件不存在等）
fn read_file_safe(path : String) -> String? {
  try Some(@fs.read_file_to_string(path)) catch {
    _ => None
  } noraise {
    s => s
  }
}

///|
/// 解析并加载程序文本，失败返回 `false`（语法错误等）
fn load_program_safe(db : Database, src : String) -> Bool {
  try {
    load_program(db, src)
    true
  } catch {
    _ => false
  } noraise {
    r => r
  }
}

///|
/// 拆分 `(Head :- Body)` 或普通项为 (head, body 目标列表)。
/// 用于 `let` 内建（对应标准 Prolog 的 assert）。
fn clause_parts(t : Term) -> (Term, Array[Term]) {
  match walk_deep(t, @hashmap.HashMap::new()) {
    Compound(":-", [h, b]) => (h, flatten(b))
    other => (other, [])
  }
}

///|
/// 算术比较内建（=:= =\= < > =< >=）
fn arith_cmp(
  args : Array[Term],
  e : Engine,
  cmp : (Int, Int) -> Bool,
) -> BuiltinResult {
  match args {
    [a, b] => {
      let result = try {
        let x = eval_arith(a, e.env)
        let y = eval_arith(b, e.env)
        if cmp(x, y) {
          Succeed
        } else {
          Fail
        }
      } catch {
        _ => Fail
      } noraise {
        r => r
      }
      result
    }
    _ => Fail
  }
}

///|
/// 查找内建谓词：命中返回实现，未命中返回 None（走用户子句）。
/// Compound 解包统一在此完成，实现只接收参数数组。
fn exec_builtin(g : Term, e : Engine) -> BuiltinResult? {
  let key = pred_key(g)
  match builtin_table().get(key) {
    Some(f) =>
      match g {
        Compound(_, args) => Some(f(args, e))
        _ => Some(f([], e))
      }
    None => None
  }
}
