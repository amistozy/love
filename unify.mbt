///|
/// 沿环境展开变量（顶层展开；复合项内部在递归时展开）
pub fn walk(t : Term, env : Env) -> Term {
  match t {
    Var(name) =>
      match env.get(name) {
        Some(v) => walk(v, env)
        None => t
      }
    _ => t
  }
}

///|
/// 深度展开：复合项内部也递归展开（用于 findall 收集与答案展示）
pub fn walk_deep(t : Term, env : Env) -> Term {
  match walk(t, env) {
    Compound(f, args) => Compound(f, args.map(a => walk_deep(a, env)))
    other => other
  }
}

///|
/// 检查变量 `name` 是否出现在项 `t` 中（occurs check）
fn occurs(name : String, t : Term, env : Env) -> Bool {
  match walk(t, env) {
    Var(n) => n == name
    Compound(_, args) => {
      let mut found = false
      for a in args {
        if occurs(name, a, env) {
          found = true
          break
        }
      }
      found
    }
    _ => false
  }
}

///|
/// 合一：在环境 `env` 下合一 `t1` 与 `t2`。
///
/// 采用 copy-on-write：绑定变量时复制环境，返回新环境；
/// 失败返回 `None`。合一带 occurs check，避免产生循环项。
pub fn unify(t1 : Term, t2 : Term, env : Env) -> Env? {
  let a = walk(t1, env)
  let b = walk(t2, env)
  match a {
    Var(n) =>
      if occurs(n, b, env) {
        None
      } else {
        let new_env = env.copy()
        new_env[n] = b
        Some(new_env)
      }
    _ =>
      match b {
        Var(n) =>
          if occurs(n, a, env) {
            None
          } else {
            let new_env = env.copy()
            new_env[n] = a
            Some(new_env)
          }
        _ =>
          match (a, b) {
            (Int(x), Int(y)) => if x == y { Some(env) } else { None }
            (Atom(x), Atom(y)) => if x == y { Some(env) } else { None }
            (Compound(f1, args1), Compound(f2, args2)) =>
              if f1 == f2 && args1.length() == args2.length() {
                let mut cur = env
                for i in 0..<args1.length() {
                  match unify(args1[i], args2[i], cur) {
                    Some(env2) => cur = env2
                    None => return None
                  }
                }
                Some(cur)
              } else {
                None
              }
            _ => None
          }
      }
  }
}

///|
/// 严格相等（`==`/`\==` 的语义）：在环境中展开后按结构比较，
/// 未绑定变量按名字比较。
pub fn term_identical(t1 : Term, t2 : Term, env : Env) -> Bool {
  let a = walk(t1, env)
  let b = walk(t2, env)
  match (a, b) {
    (Var(x), Var(y)) => x == y
    (Int(x), Int(y)) => x == y
    (Atom(x), Atom(y)) => x == y
    (Compound(f1, args1), Compound(f2, args2)) =>
      f1 == f2 &&
      args1.length() == args2.length() &&
      ({
        let mut same = true
        for i in 0..<args1.length() {
          if !term_identical(args1[i], args2[i], env) {
            same = false
            break
          }
        }
        same
      })
    _ => false
  }
}

///|
/// 判断项在环境中是否已 ground（不含未绑定变量）
pub fn is_ground(t : Term, env : Env) -> Bool {
  match walk(t, env) {
    Var(_) => false
    Compound(_, args) => {
      let mut ok = true
      for a in args {
        if !is_ground(a, env) {
          ok = false
          break
        }
      }
      ok
    }
    _ => true
  }
}
