///|
/// 变量绑定环境：按变量 id 索引的绑定表 + trail（回溯撤销记录）。
priv struct Subst {
  bindings : Array[LoveTerm?]
  trail : Array[Int]
}

///|
fn Subst::new() -> Subst {
  { bindings: [], trail: [] }
}

///|
/// 解引用：沿绑定链找到最终项（结构性递归：复合项参数一并解引用）。
fn Subst::deref(subst : Subst, t : LoveTerm) -> LoveTerm {
  match t {
    LoveTerm::Var(id) =>
      match subst.bindings.get(id) {
        Some(Some(b)) => subst.deref(b)
        _ => t
      }
    LoveTerm::Struct(n, args) =>
      LoveTerm::Struct(n, args.map(fn(a) { subst.deref(a) }))
    LoveTerm::ListCons(h, tl) =>
      LoveTerm::ListCons(subst.deref(h), subst.deref(tl))
    _ => t
  }
}

///|
/// 绑定变量（带 occurs check）。自反绑定（X = X）视为成功。
fn Subst::bind(subst : Subst, id : Int, t : LoveTerm) -> Bool {
  match t {
    LoveTerm::Var(x) if x == id => return true
    _ => ()
  }
  if contains_var(t, id) {
    return false
  }
  while subst.bindings.length() <= id {
    subst.bindings.push(None)
  }
  subst.bindings[id] = Some(t)
  subst.trail.push(id)
  true
}

///|
/// 撤销 trail 中 len 之后的全部绑定。
fn Subst::unbind_to(subst : Subst, len : Int) -> Unit {
  for i in len..<subst.trail.length() {
    subst.bindings[subst.trail[i]] = None
  }
  subst.trail.truncate(len)
}

///|
/// 项中是否包含变量 id（occurs check）。
fn contains_var(t : LoveTerm, id : Int) -> Bool {
  match t {
    LoveTerm::Var(x) => x == id
    LoveTerm::Struct(_, args) => {
      for a in args {
        if contains_var(a, id) {
          return true
        }
      }
      false
    }
    LoveTerm::ListCons(h, tl) => contains_var(h, id) || contains_var(tl, id)
    _ => false
  }
}

///|
/// 合一（带 occurs check）。成功返回 true 并产生绑定，失败返回 false。
fn unify(subst : Subst, a : LoveTerm, b : LoveTerm) -> Bool {
  match (subst.deref(a), subst.deref(b)) {
    (LoveTerm::Var(x), t) => subst.bind(x, t)
    (t, LoveTerm::Var(x)) => subst.bind(x, t)
    (LoveTerm::Int(x), LoveTerm::Int(y)) => x == y
    (LoveTerm::Float(x), LoveTerm::Float(y)) => x == y
    (LoveTerm::Atom(x), LoveTerm::Atom(y)) => x == y
    (LoveTerm::Str(x), LoveTerm::Str(y)) => x == y
    (LoveTerm::Struct(n1, a1), LoveTerm::Struct(n2, a2)) => {
      if n1 != n2 || a1.length() != a2.length() {
        return false
      }
      for i in 0..<a1.length() {
        if !unify(subst, a1[i], a2[i]) {
          return false
        }
      }
      true
    }
    (LoveTerm::ListCons(h1, t1), LoveTerm::ListCons(h2, t2)) =>
      if unify(subst, h1, h2) {
        unify(subst, t1, t2)
      } else {
        false
      }
    (LoveTerm::ListNil, LoveTerm::ListNil) => true
    _ => false
  }
}

///|
/// 结构相等（==/2 用，不产生绑定）。
fn term_equal(subst : Subst, a : LoveTerm, b : LoveTerm) -> Bool {
  match (subst.deref(a), subst.deref(b)) {
    (LoveTerm::Var(x), LoveTerm::Var(y)) => x == y
    (LoveTerm::Int(x), LoveTerm::Int(y)) => x == y
    (LoveTerm::Float(x), LoveTerm::Float(y)) => x == y
    (LoveTerm::Atom(x), LoveTerm::Atom(y)) => x == y
    (LoveTerm::Str(x), LoveTerm::Str(y)) => x == y
    (LoveTerm::Struct(n1, a1), LoveTerm::Struct(n2, a2)) => {
      if n1 != n2 || a1.length() != a2.length() {
        return false
      }
      for i in 0..<a1.length() {
        if !term_equal(subst, a1[i], a2[i]) {
          return false
        }
      }
      true
    }
    (LoveTerm::ListCons(h1, t1), LoveTerm::ListCons(h2, t2)) =>
      if term_equal(subst, h1, h2) {
        term_equal(subst, t1, t2)
      } else {
        false
      }
    (LoveTerm::ListNil, LoveTerm::ListNil) => true
    _ => false
  }
}

///|
/// 项中是否含变量。
fn contains_any_var(t : LoveTerm) -> Bool {
  match t {
    LoveTerm::Var(_) => true
    LoveTerm::Struct(_, args) => {
      for a in args {
        if contains_any_var(a) {
          return true
        }
      }
      false
    }
    LoveTerm::ListCons(h, tl) => contains_any_var(h) || contains_any_var(tl)
    _ => false
  }
}
