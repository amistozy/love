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
/// 生成长度为 `len` 的匿名变量列表
fn fresh_list(e : Engine, len : Int) -> Term {
  let mut acc : Term = Atom("[]")
  for _i in 0..<len {
    let v = Var(fresh_var_name(e, "_"))
    acc = Compound(".", [v, acc])
  }
  acc
}

///|
/// 内建谓词表：谓词键 -> 实现
fn builtin_table() -> Map[String, (Term, Engine) -> BuiltinResult] {
  let table : Map[String, (Term, Engine) -> BuiltinResult] = {
    "true/0": (_g, _e) => Succeed,
    "fail/0": (_g, _e) => Fail,
    "=/2": (g, e) => {
      match g {
        Compound(_, [a, b]) =>
          match unify(a, b, e.env) {
            Some(env) => SucceedEnv(env)
            None => Fail
          }
        _ => Fail
      }
    },
    "\\=/2": (g, e) => {
      match g {
        Compound(_, [a, b]) =>
          match unify(a, b, e.env) {
            Some(_) => Fail
            None => Succeed
          }
        _ => Fail
      }
    },
    "==/2": (g, e) => {
      match g {
        Compound(_, [a, b]) =>
          if term_identical(a, b, e.env) {
            Succeed
          } else {
            Fail
          }
        _ => Fail
      }
    },
    "\\==/2": (g, e) => {
      match g {
        Compound(_, [a, b]) =>
          if term_identical(a, b, e.env) {
            Fail
          } else {
            Succeed
          }
        _ => Fail
      }
    },
    "var/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          match walk(a, e.env) {
            Var(_) => Succeed
            _ => Fail
          }
        _ => Fail
      }
    },
    "nonvar/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          match walk(a, e.env) {
            Var(_) => Fail
            _ => Succeed
          }
        _ => Fail
      }
    },
    "atom/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          match walk(a, e.env) {
            Atom(_) => Succeed
            _ => Fail
          }
        _ => Fail
      }
    },
    "integer/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          match walk(a, e.env) {
            Int(_) => Succeed
            _ => Fail
          }
        _ => Fail
      }
    },
    "atomic/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          match walk(a, e.env) {
            Atom(_) | Int(_) => Succeed
            _ => Fail
          }
        _ => Fail
      }
    },
    "compound/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          match walk(a, e.env) {
            Compound(_, _) => Succeed
            _ => Fail
          }
        _ => Fail
      }
    },
    "ground/1": (g, e) => {
      match g {
        Compound(_, [a]) => if is_ground(a, e.env) { Succeed } else { Fail }
        _ => Fail
      }
    },
    "is/2": (g, e) => {
      match g {
        Compound(_, [target, expr]) => {
          let result = try eval_arith(expr, e.env) catch {
            _ => Fail
          } noraise {
            n =>
              match unify(target, Int(n), e.env) {
                Some(env) => SucceedEnv(env)
                None => Fail
              }
          }
          result
        }
        _ => Fail
      }
    },
    "=:=/2": (g, e) => arith_cmp(g, e, (x, y) => x == y),
    "=\\=/2": (g, e) => arith_cmp(g, e, (x, y) => x != y),
    "</2": (g, e) => arith_cmp(g, e, (x, y) => x < y),
    ">/2": (g, e) => arith_cmp(g, e, (x, y) => x > y),
    "=</2": (g, e) => arith_cmp(g, e, (x, y) => x <= y),
    ">=/2": (g, e) => arith_cmp(g, e, (x, y) => x >= y),
    "\\+/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          if sub_has_solution(e, [a], e.env) {
            Fail
          } else {
            Succeed
          }
        _ => Fail
      }
    },
    "not/1": (g, e) => {
      match g {
        Compound(_, [a]) =>
          if sub_has_solution(e, [a], e.env) {
            Fail
          } else {
            Succeed
          }
        _ => Fail
      }
    },
    "member/2": (g, e) => {
      match g {
        Compound(_, [x, l]) => {
          let h = Var(fresh_var_name(e, "H"))
          let t = Var(fresh_var_name(e, "T"))
          Choice(e.env, [
            Inline([(l, Compound(".", [x, t]))], []),
            Inline([(l, Compound(".", [h, t]))], [Compound("member", [x, t])]),
          ])
        }
        _ => Fail
      }
    },
    "length/2": (g, e) => {
      match g {
        Compound(_, [l, n]) => {
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
        }
        _ => Fail
      }
    },
    "append/3": (g, e) => {
      match g {
        Compound(_, [a, b, c]) => {
          let h = Var(fresh_var_name(e, "H"))
          let t1 = Var(fresh_var_name(e, "T1"))
          let r1 = Var(fresh_var_name(e, "R1"))
          Choice(e.env, [
            Inline([(a, Atom("[]")), (c, b)], []),
            Inline([(a, Compound(".", [h, t1])), (c, Compound(".", [h, r1]))], [
              Compound("append", [t1, b, r1]),
            ]),
          ])
        }
        _ => Fail
      }
    },
    "findall/3": (g, e) => {
      match g {
        Compound(_, [t, goal, l]) => {
          let envs = sub_solve_all(e, [goal], e.env)
          let terms = envs.map(env => walk_deep(t, env))
          let list = make_list(terms)
          match unify(l, list, e.env) {
            Some(env) => SucceedEnv(env)
            None => Fail
          }
        }
        _ => Fail
      }
    },
    "write/1": (g, e) => {
      match g {
        Compound(_, [a]) => {
          e.session.output.write_string(term_to_string_plain(a, e.env))
          Succeed
        }
        _ => Fail
      }
    },
    "writeln/1": (g, e) => {
      match g {
        Compound(_, [a]) => {
          e.session.output.write_string(term_to_string_plain(a, e.env))
          e.session.output.write_string("\n")
          Succeed
        }
        _ => Fail
      }
    },
    "nl/0": (_g, e) => {
      e.session.output.write_string("\n")
      Succeed
    },
    "atom_length/2": (g, e) => {
      match g {
        Compound(_, [a, n]) =>
          match walk(a, e.env) {
            Atom(s) =>
              match unify(n, Int(s.length()), e.env) {
                Some(env) => SucceedEnv(env)
                None => Fail
              }
            _ => Fail
          }
        _ => Fail
      }
    },
    "char_code/2": (g, e) => {
      match g {
        Compound(_, [c, code]) => {
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
        }
        _ => Fail
      }
    },
  }
  table
}

///|
/// 算术比较内建（=:= =\= < > =< >=）
fn arith_cmp(g : Term, e : Engine, cmp : (Int, Int) -> Bool) -> BuiltinResult {
  match g {
    Compound(_, [a, b]) => {
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
/// 查找内建谓词：命中返回实现，未命中返回 None（走用户子句）
fn exec_builtin(g : Term, e : Engine) -> BuiltinResult? {
  let key = pred_key(g)
  match builtin_table().get(key) {
    Some(f) => Some(f(g, e))
    None => None
  }
}
