///|
/// 白盒测试：合一、重命名与引擎内部行为。

///|
test "unify binds variables" {
  let s = Subst::new()
  assert_true(unify(s, LoveTerm::Var(0), LoveTerm::Atom("a")))
  assert_true(
    match s.deref(LoveTerm::Var(0)) {
      LoveTerm::Atom("a") => true
      _ => false
    },
  )
}

///|
test "unify aliases two variables" {
  let s = Subst::new()
  assert_true(unify(s, LoveTerm::Var(0), LoveTerm::Var(1)))
  assert_true(unify(s, LoveTerm::Var(1), LoveTerm::Atom("x")))
  assert_true(
    match s.deref(LoveTerm::Var(0)) {
      LoveTerm::Atom("x") => true
      _ => false
    },
  )
}

///|
test "unbind_to undoes bindings" {
  let s = Subst::new()
  assert_true(unify(s, LoveTerm::Var(0), LoveTerm::Atom("a")))
  assert_true(unify(s, LoveTerm::Var(1), LoveTerm::Atom("b")))
  assert_eq(s.trail.length(), 2)
  s.unbind_to(1)
  assert_true(
    match s.deref(LoveTerm::Var(0)) {
      LoveTerm::Atom("a") => true
      _ => false
    },
  )
  assert_true(
    match s.deref(LoveTerm::Var(1)) {
      LoveTerm::Var(_) => true
      _ => false
    },
  )
}

///|
test "occurs check rejects cyclic binding" {
  let s = Subst::new()
  // X = f(X) 应失败（带 occurs check）
  assert_false(
    unify(s, LoveTerm::Var(0), LoveTerm::Struct("f", [LoveTerm::Var(0)])),
  )
}

///|
test "subst mutation propagates through value params" {
  let s = Subst::new()
  assert_true(unify(s, LoveTerm::Var(5), LoveTerm::Atom("z")))
  assert_true(
    match s.deref(LoveTerm::Var(5)) {
      LoveTerm::Atom("z") => true
      _ => false
    },
  )
  assert_eq(s.trail.length(), 1)
}

///|
test "parser shares variable ids within a clause" {
  let p = parse_program("p(X) :- q(X).")
  match p.preds.get("p") {
    None => fail("p not found")
    Some(pc) => {
      assert_eq(pc.statics.length(), 1)
      let c = pc.statics[0]
      assert_true(
        match (c.head, c.body) {
          (
            LoveTerm::Struct("p", [LoveTerm::Var(a)]),
            LoveTerm::Struct("q", [LoveTerm::Var(b)]),
          ) => a == b
          _ => false
        },
      )
    }
  }
}

///|
test "rule body binds variables" {
  let p = parse_program("q(a). q(b). p(X) :- q(X).")
  let q = parse_query("p(X).")
  let sols = solve_terms(p, q)
  assert_eq(sols.length(), 2)
  assert_true(
    match sols[0] {
      LoveTerm::Struct("p", [LoveTerm::Atom("a")]) => true
      _ => false
    },
  )
  assert_true(
    match sols[1] {
      LoveTerm::Struct("p", [LoveTerm::Atom("b")]) => true
      _ => false
    },
  )
}

///|
test "fact query binds variables" {
  let p = parse_program("q(a). q(b).")
  let q = parse_query("q(X).")
  let sols = solve_terms(p, q)
  assert_eq(sols.length(), 2)
  assert_true(
    match sols[0] {
      LoveTerm::Struct("q", [LoveTerm::Atom("a")]) => true
      _ => false
    },
  )
}

///|
test "recursion shares clause variables across invocations" {
  let p = parse_program(
    "edge(a, b). edge(b, c). path(X, Y) :- edge(X, Y). path(X, Y) :- edge(X, Z), path(Z, Y).",
  )
  let q = parse_query("path(a, Y).")
  let sols = solve_terms(p, q)
  assert_eq(sols.length(), 2)
  assert_true(
    match sols[1] {
      LoveTerm::Struct("path", [LoveTerm::Atom("a"), LoveTerm::Atom("c")]) =>
        true
      _ => false
    },
  )
}

///|
test "read_term_from_line parses a term" {
  // 完整项
  match read_term_from_line("foo(1, bar).") {
    Some(LoveTerm::Struct("foo", [LoveTerm::Int(1), LoveTerm::Atom("bar")])) =>
      ()
    _ => fail("expected foo(1, bar)")
  }
  // 无结尾句点也可
  match read_term_from_line("hello") {
    Some(LoveTerm::Atom("hello")) => ()
    _ => fail("expected hello")
  }
  // 解析失败 → None（不完整的项）
  assert_true(read_term_from_line("foo(1") is None)
  assert_true(read_term_from_line("[a, b") is None)
}
