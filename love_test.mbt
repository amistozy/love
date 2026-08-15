///|
/// Love 语言黑盒测试：解析、合一、求解、内置谓词与算术。

///|
/// 便捷助手：解析程序与查询，返回每个解的解引用查询项的格式化字符串。
fn sols_of(
  program_src : String,
  query_src : String,
) -> Array[String] raise LoveError {
  let p = parse_program(program_src)
  let q = parse_query(query_src)
  solve_terms(p, q).map(fn(t) { format_term(t) })
}

///|
/// 便捷助手：只给查询（空程序 + 内置库）。
fn qs_of(query_src : String) -> Array[String] raise LoveError {
  sols_of("", query_src)
}

///|
/// 解析查询并带变量名格式化（解析测试用）。
fn pq(src : String) -> String raise LoveError {
  let (t, names) = parse_query_with_names(src)
  format_term_with_names(t, names)
}

// ---------- 解析 ----------

///|
test "parse: facts, rules, operators" {
  let src =
    #|likes(alice, bob).
    #|happy(X) :- likes(X, bob).
    #|sum(X, Y, Z) :- Z is X + Y.
    #|
  let p = parse_program(src)
  assert_true(p.preds.contains("likes"))
  assert_true(p.preds.contains("happy"))
  assert_true(p.preds.contains("sum"))
}

///|
test "parse: operator precedence" {
  assert_eq(pq("E = a - b - c."), "E = a - b - c")
  assert_eq(pq("E = (a, b, c)."), "E = (a, b, c)")
  assert_eq(pq("E = a + b * c."), "E = a + b * c")
}

///|
test "parse: lists" {
  assert_eq(pq("L = [1, 2, 3]."), "L = [1, 2, 3]")
  assert_eq(pq("L = [a | T]."), "L = [a | T]")
  assert_eq(pq("L = [a, b | T]."), "L = [a, b | T]")
  assert_eq(pq("L = []."), "L = []")
}

///|
test "parse: quoted atoms and strings" {
  assert_eq(pq("A = 'hello world'."), "A = 'hello world'")
  assert_eq(pq("S = \"hi\"."), "S = \"hi\"")
  assert_eq(pq("A = 'it''s'."), "A = 'it''s'")
}

///|
test "parse: comments" {
  let src =
    #|% 行注释
    #|/* 块
    #|   注释 */
    #|a(1). % 尾部注释
    #|
  let p = parse_program(src)
  assert_true(p.preds.contains("a"))
}

///|
test "parse: negative numbers and floats" {
  let sols = qs_of("X is -5.")
  assert_eq(sols[0], "-5 is -5")
}

// ---------- 合一 ----------

///|
test "unify: = binds and checks" {
  assert_eq(qs_of("X = 42.")[0], "42 = 42")
  assert_true(qs_of("X = Y, Y = hello.").length() == 1)
  assert_true(qs_of("a = b.").is_empty())
  assert_true(qs_of("X = a, X = b.").is_empty())
  assert_true(qs_of("f(X, b) = f(a, Y).").length() == 1)
  assert_true(qs_of("a \\= b.").length() == 1)
  assert_true(qs_of("X \\= X.").is_empty())
  assert_true(qs_of("a == a.").length() == 1)
  assert_true(qs_of("a == b.").is_empty())
  assert_true(qs_of("X == X.").length() == 1)
  assert_true(qs_of("f(X) == f(Y).").is_empty())
}

///|
test "occurs check: X = f(X) fails" {
  assert_true(qs_of("X = f(X).").is_empty())
  assert_true(qs_of("unify_with_occurs_check(X, f(X)).").is_empty())
}

// ---------- 求解 ----------

///|
test "solve: facts and simple rules" {
  let src =
    #|parent(tom, bob).
    #|parent(tom, lisa).
    #|male(tom).
    #|father(F, C) :- parent(F, C), male(F).
    #|
  let sols = sols_of(src, "?- father(F, C).")
  assert_eq(sols.length(), 2)
  assert_eq(sols[0], "father(tom, bob)")
  assert_eq(sols[1], "father(tom, lisa)")
}

///|
test "solve: recursive rules" {
  let src =
    #|edge(a, b).
    #|edge(b, c).
    #|edge(c, d).
    #|path(X, Y) :- edge(X, Y).
    #|path(X, Y) :- edge(X, Z), path(Z, Y).
    #|
  let sols = sols_of(src, "?- path(a, D).")
  assert_eq(sols.length(), 3)
  assert_eq(sols[0], "path(a, b)")
  assert_eq(sols[1], "path(a, c)")
  assert_eq(sols[2], "path(a, d)")
}

///|
test "solve: multiple clauses and backtracking" {
  let src =
    #|color(red).
    #|color(green).
    #|color(blue).
    #|
  let sols = sols_of(src, "?- color(C).")
  assert_eq(sols.length(), 3)
}

///|
test "solve: conjunction and disjunction" {
  assert_true(qs_of("member(X, [1, 2]), X > 1.").length() == 1)
  assert_eq(qs_of("(X = a ; X = b).").length(), 2)
  assert_eq(qs_of("(true ; fail ; true).").length(), 2)
}

// ---------- cut ----------

///|
test "cut: commits to choices" {
  let src1 =
    #|p(1).
    #|p(2).
    #|q(X) :- p(X).
    #|
  assert_eq(sols_of(src1, "?- q(X).").length(), 2)
  let src2 =
    #|p(1).
    #|p(2).
    #|q(X) :- p(X), !.
    #|
  assert_eq(sols_of(src2, "?- q(X).").length(), 1)
}

///|
test "cut: if-then-else via ->" {
  let src =
    #|max(X, Y, M) :- (X > Y -> M = X ; M = Y).
    #|
  let sols = sols_of(src, "?- max(3, 7, M).")
  assert_eq(sols[0], "max(3, 7, 7)")
  let sols2 = sols_of(src, "?- max(9, 2, M).")
  assert_eq(sols2[0], "max(9, 2, 9)")
}

///|
test "negation as failure" {
  assert_true(qs_of("\\+ (a = b).").length() == 1)
  assert_true(qs_of("\\+ (a = a).").is_empty())
  // 否定不绑定变量：解即为原查询项
  let sols = qs_of("\\+ member(5, [1, 2]).")
  assert_eq(sols.length(), 1)
  assert_eq(sols[0], "\\+ member(5, [1, 2])")
}

// ---------- 算术 ----------

///|
test "arithmetic: is and comparisons" {
  assert_eq(qs_of("X is 1 + 2 * 3.")[0], "7 is 1 + 2 * 3")
  assert_eq(qs_of("X is (1 + 2) * 3.")[0], "9 is (1 + 2) * 3")
  assert_eq(qs_of("X is 10 // 3.")[0], "3 is 10 // 3")
  assert_eq(qs_of("X is 10 mod 3.")[0], "1 is 10 mod 3")
  assert_eq(qs_of("X is 7 / 2.")[0], "3.5 is 7 / 2")
  assert_eq(qs_of("X is 2 ^ 10.")[0], "1024 is 2 ^ 10")
  assert_eq(qs_of("X is abs(-5).")[0], "5 is abs(-5)")
  assert_eq(qs_of("X is sqrt(16).")[0], "4.0 is sqrt(16)")
  assert_true(qs_of("3 < 5.").length() == 1)
  assert_true(qs_of("5 =< 5.").length() == 1)
  assert_true(qs_of("1 + 1 =:= 2.").length() == 1)
  assert_true(qs_of("1 =:= 1.0.").length() == 1)
  assert_true(qs_of("3 > 5.").is_empty())
  assert_true(qs_of("X is 1 // 0.").is_empty())
}

///|
test "arithmetic: between and plus" {
  assert_eq(qs_of("between(1, 3, X).").length(), 3)
  assert_true(qs_of("between(1, 3, 2).").length() == 1)
  assert_true(qs_of("between(1, 3, 5).").is_empty())
  assert_eq(qs_of("plus(1, 2, X).")[0], "plus(1, 2, 3)")
  assert_eq(qs_of("plus(1, X, 3).")[0], "plus(1, 2, 3)")
  assert_eq(qs_of("plus(X, 2, 5).")[0], "plus(3, 2, 5)")
}

///|
test "arithmetic: float formatting" {
  assert_eq(qs_of("X is 2.5 + 1.0.")[0], "3.5 is 2.5 + 1.0")
  assert_eq(qs_of("X is 2.0 + 1.0.")[0], "3.0 is 2.0 + 1.0")
}

// ---------- 列表（内置库子句） ----------

///|
test "lists: member generates" {
  let sols = qs_of("member(X, [a, b, c]).")
  assert_eq(sols.length(), 3)
  assert_eq(sols[0], "member(a, [a, b, c])")
  assert_eq(sols[2], "member(c, [a, b, c])")
  assert_true(qs_of("member(a, [a, b, c]).").length() == 1)
}

///|
test "lists: append" {
  assert_eq(
    qs_of("append([1, 2], [3], L).")[0],
    "append([1, 2], [3], [1, 2, 3])",
  )
  let sols = qs_of("append(A, B, [1, 2]).")
  assert_eq(sols.length(), 3)
}

///|
test "lists: length reverse sum" {
  assert_eq(qs_of("length([a, b, c], N).")[0], "length([a, b, c], 3)")
  assert_eq(qs_of("reverse([1, 2, 3], R).")[0], "reverse([1, 2, 3], [3, 2, 1])")
  assert_eq(
    qs_of("sum_list([1, 2, 3, 4], S).")[0],
    "sum_list([1, 2, 3, 4], 10)",
  )
}

///|
test "lists: nth0 and nth1" {
  assert_eq(qs_of("nth0(1, [a, b, c], X).")[0], "nth0(1, [a, b, c], b)")
  assert_eq(qs_of("nth1(2, [a, b, c], X).")[0], "nth1(2, [a, b, c], b)")
}

///|
test "lists: sort and msort" {
  assert_eq(qs_of("sort([3, 1, 2, 1], L).")[0], "sort([3, 1, 2, 1], [1, 2, 3])")
  assert_eq(
    qs_of("msort([3, 1, 2, 1], L).")[0],
    "msort([3, 1, 2, 1], [1, 1, 2, 3])",
  )
  assert_eq(qs_of("msort([b, a, c], L).")[0], "msort([b, a, c], [a, b, c])")
}

///|
test "lists: maplist" {
  assert_true(qs_of("maplist(atom, [a, b, c]).").length() == 1)
  assert_true(qs_of("maplist(atom, [a, 1]).").is_empty())
  assert_true(qs_of("maplist(=(1), [1, 1, 1]).").length() == 1)
  assert_true(qs_of("maplist(=(X), [1, 1]), X = 1.").length() == 1)
}

// ---------- 项检查 ----------

///|
test "terms: inspection" {
  assert_true(qs_of("var(X).").length() == 1)
  assert_true(qs_of("var(a).").is_empty())
  assert_true(qs_of("nonvar(a).").length() == 1)
  assert_true(qs_of("atom(a).").length() == 1)
  assert_true(qs_of("atom(foo_bar).").length() == 1)
  assert_true(qs_of("number(42).").length() == 1)
  assert_true(qs_of("number(3.14).").length() == 1)
  assert_true(qs_of("integer(42).").length() == 1)
  assert_true(qs_of("float(3.14).").length() == 1)
  assert_true(qs_of("atomic(a).").length() == 1)
  assert_true(qs_of("compound(f(a)).").length() == 1)
  assert_true(qs_of("compound([a, b]).").length() == 1)
  assert_true(qs_of("ground(f(a, b)).").length() == 1)
  assert_true(qs_of("ground(f(X, b)).").is_empty())
}

///|
test "terms: functor, arg, univ" {
  assert_eq(qs_of("functor(foo(a, b), F, N).")[0], "functor(foo(a, b), foo, 2)")
  // functor 生成：X 被绑定为 foo(_1, _2)
  assert_true(
    qs_of("functor(X, foo, 2), arg(1, X, A), arg(2, X, B).").length() == 1,
  )
  assert_eq(qs_of("arg(2, foo(a, b), X).")[0], "arg(2, foo(a, b), b)")
  assert_eq(qs_of("X =.. [foo, a, b].")[0], "foo(a, b) =.. [foo, a, b]")
  assert_eq(qs_of("foo(a, b) =.. L.")[0], "foo(a, b) =.. [foo, a, b]")
}

///|
test "terms: atom ops" {
  assert_eq(qs_of("atom_length(hello, N).")[0], "atom_length(hello, 5)")
  assert_eq(
    qs_of("atom_concat(foo, bar, X).")[0],
    "atom_concat(foo, bar, foobar)",
  )
  assert_eq(
    qs_of("atom_concat(foo, X, foobar).")[0],
    "atom_concat(foo, bar, foobar)",
  )
  assert_eq(
    qs_of("atom_concat(X, bar, foobar).")[0],
    "atom_concat(foo, bar, foobar)",
  )
  assert_eq(
    qs_of("sub_atom(hello, 1, 3, _, S).")[0],
    "sub_atom(hello, 1, 3, 1, ell)",
  )
}

///|
test "terms: comparison and standard order" {
  assert_eq(qs_of("compare(O, a, b).")[0], "compare(<, a, b)")
  assert_eq(qs_of("compare(O, a, a).")[0], "compare(=, a, a)")
  assert_eq(qs_of("compare(O, b, a).")[0], "compare(>, b, a)")
  assert_true(qs_of("a @< b.").length() == 1)
  assert_true(qs_of("1 @< a.").length() == 1)
  assert_true(qs_of("f(a) @< f(b).").length() == 1)
}

// ---------- findall ----------

///|
test "findall collects solutions" {
  // findall 的结果列表
  assert_eq(
    qs_of("findall(X, member(X, [1, 2, 3]), L).")[0],
    "findall(_0, member(_0, [1, 2, 3]), [1, 2, 3])",
  )
  assert_eq(
    qs_of("findall(X, (member(X, [1, 2]), X > 1), L).")[0],
    "findall(_0, (member(_0, [1, 2]), _0 > 1), [2])",
  )
  assert_eq(qs_of("findall(X, fail, L).")[0], "findall(_0, fail, [])")
  assert_eq(
    qs_of("findall(f(X), member(X, [a, b]), L).")[0],
    "findall(f(_0), member(_0, [a, b]), [f(a), f(b)])",
  )
}

// ---------- catch/throw ----------

///|
test "catch: throw caught by matching catcher" {
  assert_eq(qs_of("catch(throw(x), x, true).").length(), 1)
  assert_eq(
    qs_of("catch(throw(x), x, R = caught).")[0],
    "catch(throw(x), x, caught = caught)",
  )
  // Recovery 运行并绑定变量
  assert_eq(
    qs_of("catch(throw(x), x, R = ok).")[0],
    "catch(throw(x), x, ok = ok)",
  )
}

///|
test "catch: non-matching catcher propagates (uncaught fails)" {
  // throw(y) 与 catcher x 不合一 → 未捕获 → 整个查询失败
  assert_true(qs_of("catch(throw(x), y, true).").is_empty())
  // 无 catch 直接 throw → 失败
  assert_true(qs_of("throw(x).").is_empty())
}

///|
test "catch: goal failure does not run recovery" {
  assert_true(qs_of("catch(fail, _, true).").is_empty())
  assert_true(qs_of("catch(fail, _, R = ok).").is_empty())
}

///|
test "catch: nested catches and outer propagation" {
  // 内层 catcher 匹配 → 内层恢复（R 是同一查询变量，保持 inner 绑定）
  assert_eq(
    qs_of("catch(catch(throw(x), x, R = inner), y, R = outer).")[0],
    "catch(catch(throw(x), x, inner = inner), y, inner = outer)",
  )
  // 内层不匹配 → 外层捕获
  assert_eq(
    qs_of("catch(catch(throw(x), y, fail), x, R = outer).")[0],
    "catch(catch(throw(x), y, fail), x, outer = outer)",
  )
}

///|
test "catch: throw inside goal after partial work" {
  // 先绑定再抛：捕获时撤销 Goal 中的绑定，恢复运行 Recovery
  assert_eq(
    qs_of("catch((X = 1, throw(x)), x, R = X).")[0],
    "catch((_0 = 1, throw(x)), x, _0 = _0)",
  )
}

///|
test "catch: works with backtracking in goal" {
  // Goal 有多个解，第一个解成功 → catch 成功；回溯进入第二个解抛异常 → 被捕获
  let sols = qs_of("catch((X = 1 ; throw(x)), x, R = caught).")
  assert_eq(sols.length(), 2)
}

///|
test "catch: goal backtracking into throw is caught" {
  // X = 1 成功 → catch 成功；回溯进入 throw(x) 分支 → 被捕获 → Recovery 运行
  let sols = qs_of("catch((X = 1 ; throw(x)), x, R = caught).")
  assert_eq(sols.length(), 2)
}

///|
test "catch: recovery suppresses remaining alternatives" {
  // Goal 内 throw 之后的 choice point 应被截断：`; X = 1` 不再尝试
  let sols = qs_of("catch((throw(x) ; X = 1), x, R = ok).")
  assert_eq(sols.length(), 1)
  assert_eq(sols[0], "catch((throw(x) ; _0 = 1), x, ok = ok)")
}

///|
test "throw: ball can be any term" {
  assert_eq(qs_of("catch(throw(f(a, b)), f(A, B), true).").length(), 1)
  assert_eq(
    qs_of("catch(throw(42), N, true).")[0],
    "catch(throw(42), 42, true)",
  )
}

// ---------- bagof/setof ----------

///|
test "bagof: collects template instances" {
  assert_eq(
    qs_of("bagof(X, member(X, [1, 2, 3]), L).")[0],
    "bagof(_0, member(_0, [1, 2, 3]), [1, 2, 3])",
  )
  // 无解 → 失败（与 findall 返回 [] 不同）
  assert_true(qs_of("bagof(X, fail, L).").is_empty())
}

///|
test "bagof: groups by free variables" {
  // 自由变量 Y：按 Y 的取值分组
  let sols = qs_of("bagof(X, member(X-Y, [1-a, 2-b, 3-a]), L).")
  assert_eq(sols.length(), 2)
  assert_eq(sols[0], "bagof(_0, member(_0 - a, [1 - a, 2 - b, 3 - a]), [1, 3])")
  assert_eq(sols[1], "bagof(_0, member(_0 - b, [1 - a, 2 - b, 3 - a]), [2])")
}

///|
test "bagof: existential quantification with ^" {
  // Y 是存在量化变量 → 不参与分组
  assert_eq(
    qs_of("bagof(X, Y^member(X-Y, [1-a, 2-b, 3-a]), L).")[0],
    "bagof(_0, _1 ^ member(_0 - _1, [1 - a, 2 - b, 3 - a]), [1, 2, 3])",
  )
}

///|
test "bagof: binds free variables in query" {
  // 分组时自由变量 Y 绑定到分组取值
  let p = parse_program("")
  let q = parse_query("bagof(X, member(X-Y, [1-a, 2-b, 3-a]), L), Y = b.")
  let sols = solve_terms(p, q)
  assert_eq(sols.length(), 1)
}

///|
test "setof: sorts and deduplicates" {
  assert_eq(
    qs_of("setof(X, member(X, [3, 1, 3, 2, 1]), L).")[0],
    "setof(_0, member(_0, [3, 1, 3, 2, 1]), [1, 2, 3])",
  )
  // 按标准序分组
  let sols = qs_of("setof(X, member(X-Y, [1-b, 2-a, 3-a]), L).")
  assert_eq(sols.length(), 2)
  assert_eq(sols[0], "setof(_0, member(_0 - a, [1 - b, 2 - a, 3 - a]), [2, 3])")
  assert_eq(sols[1], "setof(_0, member(_0 - b, [1 - b, 2 - a, 3 - a]), [1])")
}

// ---------- 动态数据库 ----------

///|
test "assert and retract" {
  let p = parse_program("")
  let q = parse_query("assertz(cat(tom)), assertz(cat(pat)), cat(X).")
  let sols = solve_terms(p, q)
  assert_eq(sols.length(), 2)
  let q2 = parse_query("retract(cat(tom)), cat(X).")
  let sols2 = solve_all(p, q2)
  assert_eq(sols2.length(), 1)
  // X 应绑定为 pat（tom 已被 retract）
  let ids = query_var_ids(q2)
  match sols2[0].bindings.get(ids[0]) {
    Some(LoveTerm::Atom("pat")) => ()
    _ => fail("X should be bound to pat after retract")
  }
}

///|
test "clause enumerates" {
  let p = parse_program("a(1). a(2) :- b.")
  let q = parse_query("clause(a(X), B).")
  let sols = solve_terms(p, q)
  assert_eq(sols.length(), 2)
}

///|
test "dynamic rules via assert" {
  let p = parse_program("")
  let q = parse_query(
    "assertz((grand(X, Y) :- parent(X, Z), parent(Z, Y))), assertz(parent(a, b)), assertz(parent(b, c)), grand(a, G).",
  )
  let sols = solve_all(p, q)
  assert_eq(sols.length(), 1)
  let ids = query_var_ids(q)
  match sols[0].bindings.get(ids[ids.length() - 1]) {
    Some(LoveTerm::Atom("c")) => ()
    _ => fail("G should be bound to c")
  }
}

// ---------- DCG ----------

///|
test "dcg: simple grammar with phrase" {
  let src =
    #|s --> [a], b.
    #|b --> [b].
    #|b --> [c].
    #|
  // phrase(s, [a, b]) / [a, c] 成功
  assert_true(sols_of(src, "?- phrase(s, [a, b]).").length() == 1)
  assert_true(sols_of(src, "?- phrase(s, [a, c]).").length() == 1)
  // 不匹配
  assert_true(sols_of(src, "?- phrase(s, [a]).").is_empty())
  assert_true(sols_of(src, "?- phrase(s, [b, c]).").is_empty())
  // 生成：枚举两个可接受的串
  let sols = sols_of(src, "?- phrase(s, L).")
  assert_eq(sols.length(), 2)
}

///|
test "dcg: recursive grammar" {
  let src =
    #|digits --> [].
    #|digits --> [D], {integer(D)}, digits.
    #|
  assert_true(sols_of(src, "?- phrase(digits, []).").length() == 1)
  assert_true(sols_of(src, "?- phrase(digits, [1, 2, 3]).").length() == 1)
  assert_true(sols_of(src, "?- phrase(digits, [1, a]).").is_empty())
  assert_true(sols_of(src, "?- phrase(digits, [a]).").is_empty())
}

///|
test "dcg: curly braces embed plain goals" {
  let src =
    #|s(X) --> [a], {X is 1 + 1}, [b].
    #|
  let sols = sols_of(src, "?- phrase(s(X), [a, b]).")
  assert_eq(sols.length(), 1)
  // X 应绑定为 2
  let p = parse_program(src)
  let q = parse_query("phrase(s(X), [a, b]).")
  let all = solve_all(p, q)
  let ids = query_var_ids(q)
  match all[0].bindings.get(ids[0]) {
    Some(LoveTerm::Int(v)) => assert_eq(v, 2L)
    _ => fail("X should be 2")
  }
}

///|
test "dcg: disjunction and negation" {
  let src =
    #|s --> ([a] ; [b]).
    #|no_a --> \+ [a], [b].
    #|
  assert_true(sols_of(src, "?- phrase(s, [a]).").length() == 1)
  assert_true(sols_of(src, "?- phrase(s, [b]).").length() == 1)
  assert_true(sols_of(src, "?- phrase(s, [c]).").is_empty())
  // \+ [a] 不消耗输入：整体匹配「非 a 开头的串」+ 首字符 b
  assert_true(sols_of(src, "?- phrase(no_a, [b]).").length() == 1)
  assert_true(sols_of(src, "?- phrase(no_a, [a]).").is_empty())
  assert_true(sols_of(src, "?- phrase(no_a, [x]).").is_empty())
}

///|
test "dcg: if-then-else" {
  let src =
    #|s --> ([a] -> [b] ; [c]).
    #|
  assert_true(sols_of(src, "?- phrase(s, [a, b]).").length() == 1)
  assert_true(sols_of(src, "?- phrase(s, [c]).").length() == 1)
  assert_true(sols_of(src, "?- phrase(s, [a, c]).").is_empty())
}

// ---------- op/3 自定义运算符 ----------

///|
test "op: defines a new infix operator for subsequent parses" {
  let p = parse_program("")
  // 第一段：定义运算符
  let q1 = p.parse_query("op(500, yfx, foo).")
  assert_eq(solve_terms(p, q1).length(), 1)
  // 第二段：用新运算符解析并求解（同一程序实例，运算符表已更新）
  let q2 = p.parse_query("X = a foo b.")
  let sols = solve_all(p, q2)
  assert_eq(sols.length(), 1)
  let ids = query_var_ids(q2)
  match sols[0].bindings.get(ids[0]) {
    Some(LoveTerm::Struct("foo", [LoveTerm::Atom("a"), LoveTerm::Atom("b")])) =>
      ()
    _ => fail("X should be foo(a, b)")
  }
}

///|
test "op: precedence and associativity" {
  let p = parse_program("")
  assert_eq(solve_terms(p, p.parse_query("op(500, yfx, foo).")).length(), 1)
  // yfx：左结合，a foo b foo c = foo(foo(a, b), c)
  let q = p.parse_query("X = a foo b foo c.")
  let sols = solve_all(p, q)
  let ids = query_var_ids(q)
  match sols[0].bindings.get(ids[0]) {
    Some(LoveTerm::Struct("foo", [LoveTerm::Struct("foo", [_, _]), _])) => ()
    _ => fail("yfx should be left-associative")
  }
}

///|
test "op: prefix operator" {
  let p = parse_program("")
  assert_eq(solve_terms(p, p.parse_query("op(200, fy, not_).")).length(), 1)
  let q = p.parse_query("X = not_ a.")
  let sols = solve_all(p, q)
  let ids = query_var_ids(q)
  match sols[0].bindings.get(ids[0]) {
    Some(LoveTerm::Struct("not_", [LoveTerm::Atom("a")])) => ()
    _ => fail("X should be not_(a)")
  }
}

///|
test "op: list of names and removal" {
  let p = parse_program("")
  // 列表形式一次定义多个
  assert_eq(
    solve_terms(p, p.parse_query("op(500, yfx, [foo, bar]).")).length(),
    1,
  )
  assert_eq(solve_terms(p, p.parse_query("X = a bar b.")).length(), 1)
  // prec 0 删除
  assert_eq(solve_terms(p, p.parse_query("op(0, yfx, foo).")).length(), 1)
  // 删除后 foo 不再是运算符 → 解析失败
  let bad = Some(p.parse_query("X = a foo b.")) catch { _ => None }
  assert_true(bad is None)
}

// ---------- 字符串与控制流 ----------

///|
test "solution.more reflects pending choices" {
  let p = parse_program("")
  // 确定性：无剩余 choice point
  let sols = solve_all(p, parse_query("X = 42."))
  assert_eq(sols.length(), 1)
  assert_true(!sols[0].more)
  // 非确定性：member 还有未试子句
  let sols2 = solve_all(p, parse_query("member(X, [1, 2])."))
  assert_eq(sols2.length(), 2)
  assert_true(sols2[0].more)
  // 递归谓词：存在剩余 choice point（即使后续会失败）——与 Scryer 的 B 寄存器语义一致
  let sols3 = solve_all(p, parse_query("append([1, 2], [3], L)."))
  assert_eq(sols3.length(), 1)
  assert_true(sols3[0].more)
}

///|
test "strings are terms" {
  assert_eq(qs_of("S = \"abc\".")[0], "\"abc\" = \"abc\"")
  assert_true(qs_of("string(\"abc\").").length() == 1)
}

///|
test "cut in if-then-else controls alternatives" {
  let sols = qs_of("member(X, [1, 2, 3]), (X = 2 -> true ; fail).")
  assert_eq(sols.length(), 1)
}

///|
test "repeat with cut" {
  let sols = qs_of("repeat, !, true.")
  assert_eq(sols.length(), 1)
}

///|
test "errors in arithmetic fail the goal" {
  assert_true(qs_of("X is 1 + a.").is_empty())
  assert_true(qs_of("X is 1 // 0.").is_empty())
}

// ---------- 表驱动 tabling ----------

///|
test "tabling: left recursion terminates (transitive closure)" {
  let src =
    #|:- table reach/2.
    #|reach(X, Y) :- edge(X, Z), reach(Z, Y).
    #|reach(X, Y) :- edge(X, Y).
    #|edge(a, b). edge(b, c). edge(c, a).
    #|
  // 无 tabling 时该左递归程序不终止
  let sols = sols_of(src, "reach(a, X).")
  sols.sort()
  assert_eq(sols, ["reach(a, a)", "reach(a, b)", "reach(a, c)"])
  // 每个查询独立求值：b 的闭包同样完备（含 reach(b, b)）
  let sols2 = sols_of(src, "reach(b, X).")
  sols2.sort()
  assert_eq(sols2, ["reach(b, a)", "reach(b, b)", "reach(b, c)"])
}

///|
test "tabling: mutual recursion" {
  let src =
    #|:- table a/1, b/1.
    #|a(X) :- b(X).
    #|b(X) :- a(X).
    #|b(1).
    #|
  assert_eq(sols_of(src, "a(X)."), ["a(1)"])
  assert_eq(sols_of(src, "b(X)."), ["b(1)"])
}

///|
test "tabling: duplicate answers are removed" {
  let src =
    #|:- table p/1.
    #|p(a). p(a). p(b).
    #|
  assert_eq(sols_of(src, "p(X)."), ["p(a)", "p(b)"])
}

///|
test "tabling: non-ground answers replay with fresh variables" {
  let src =
    #|:- table p/1.
    #|p(X).
    #|
  assert_eq(sols_of(src, "p(X).").length(), 1)
  // 两次回放得到不同的全新变量
  assert_true(sols_of(src, "p(X), p(Y), X == Y.").is_empty())
}

///|
test "tabling: variant distinguishes repeated vs distinct variables" {
  let src =
    #|:- table p/2.
    #|p(a, a).
    #|
  assert_eq(sols_of(src, "p(X, X)."), ["p(a, a)"])
  assert_eq(sols_of(src, "p(X, Y)."), ["p(a, a)"])
  assert_eq(sols_of(src, "p(X, a)."), ["p(a, a)"])
  assert_true(sols_of(src, "p(X, b).").is_empty())
}

///|
test "tabling: table directive comma and list forms" {
  let comma =
    #|:- table p/1, q/1.
    #|p(X) :- p(X).
    #|p(a).
    #|q(X) :- q(X).
    #|q(b).
    #|
  assert_eq(sols_of(comma, "p(X)."), ["p(a)"])
  assert_eq(sols_of(comma, "q(X)."), ["q(b)"])
  let list =
    #|:- table([p/1]).
    #|p(X) :- p(X).
    #|p(a).
    #|
  assert_eq(sols_of(list, "p(X)."), ["p(a)"])
}

///|
test "tabling: table/1 builtin works at runtime" {
  // 未标记前：p(X,Y) :- p(Y,X) 左右互调，永不终止
  let p = parse_program("p(X, Y) :- p(Y, X). p(a, b).")
  // 运行时标记表驱动
  assert_eq(solve_terms(p, parse_query("table(p/2).")).length(), 1)
  // 最小不动点：{p(a,b), p(b,a)}
  let sols = solve_terms(p, parse_query("p(X, Y).")).map(fn(t) {
    format_term(t)
  })
  sols.sort()
  assert_eq(sols, ["p(a, b)", "p(b, a)"])
}

///|
test "tabling: works inside findall and setof" {
  let src =
    #|:- table reach/2.
    #|reach(X, Y) :- edge(X, Z), reach(Z, Y).
    #|reach(X, Y) :- edge(X, Y).
    #|edge(a, b). edge(b, c). edge(c, a).
    #|
  // findall 在子引擎中收集全部解（表内答案顺序）
  let sols = sols_of(src, "findall(Y, reach(a, Y), L).")
  assert_eq(sols.length(), 1)
  // setof 排序去重
  let sols2 = sols_of(src, "setof(Y, reach(a, Y), S).")
  assert_eq(sols2.length(), 1)
}

///|
test "tabling: tables are fresh per query (assert visible immediately)" {
  let src =
    #|:- table p/1.
    #|p(a).
    #|
  let p = parse_program(src)
  assert_eq(solve_terms(p, parse_query("p(X).")).length(), 1)
  // assertz 后新查询立即可见（每查询清空表）
  assert_eq(solve_terms(p, parse_query("assertz(p(b)).")).length(), 1)
  assert_eq(solve_terms(p, parse_query("p(X).")).length(), 2)
  // abolish_table/1 与 abolish_all_tables/0 仍可用
  assert_eq(solve_terms(p, parse_query("abolish_table(p/1).")).length(), 1)
  assert_eq(solve_terms(p, parse_query("abolish_all_tables.")).length(), 1)
  assert_eq(solve_terms(p, parse_query("p(X).")).length(), 2)
}

///|
test "tabling: dcg non-terminal via p//1" {
  let src =
    #|:- table p//1.
    #|p --> [a].
    #|
  // p//1 视同 p/3（DCG 翻译后），phrase 正常解析
  assert_eq(sols_of(src, "phrase(p, [a]).").length(), 1)
  assert_eq(sols_of(src, "phrase(p, X).").length(), 1)
}
