///|
/// 白盒测试：解析器细节与内部行为
test "operator precedence parsing" {
  let goals = parse_query_text("X is 1 + 2 * 3.")
  inspect(goals.length(), content="1")
  let t = match goals {
    More(t, ..) => t
    Empty => abort("empty goals")
  }
  guard t
    is Compound(
      "is",
      [Var("X"), Compound("+", [Int(1), Compound("*", [Int(2), Int(3)])])]
    ) else {
    fail("unexpected parse tree: \{clause_to_string(t, [])}")
  }
}

///|
test "left associativity of plus" {
  let goals = parse_query_text("X is 1 + 2 + 3.")
  let t = match goals {
    More(t, ..) => t
    Empty => abort("empty goals")
  }
  guard t
    is Compound(
      "is",
      [_, Compound("+", [Compound("+", [Int(1), Int(2)]), Int(3)])]
    ) else {
    fail("unexpected parse tree")
  }
}

///|
test "list sugar parsing" {
  let goals = parse_query_text("X = [a, b | T].")
  let t = match goals {
    More(t, ..) => t
    Empty => abort("empty goals")
  }
  guard t
    is Compound(
      "=",
      [
        Var("X"),
        Compound(".", [Atom("a"), Compound(".", [Atom("b"), Var("T")])]),
      ]
    ) else {
    fail("unexpected parse tree")
  }
  let empty = parse_query_text("X = [].")
  guard empty.head() is Some(Compound("=", [_, Atom("[]")])) else {
    fail("empty list should be [] atom")
  }
}

///|
test "anonymous variables are distinct" {
  let goals = parse_query_text("p(_, _).")
  let t = match goals {
    More(t, ..) => t
    Empty => abort("empty goals")
  }
  guard t is Compound("p", [Var(a), Var(b)]) && a != b else {
    fail("anonymous variables must be distinct")
  }
}

///|
test "reversed list program (nrev)" {
  let db = program_from_text(
    (
      #|nrev([], []).
      #|nrev([H | T], R) :- nrev(T, R1), append(R1, [H], R).
      #|
    ),
  )
  let session = Session(db)
  let out = StringBuilder()
  answers_string(session, "nrev([1, 2, 3, 4], X).", out)
  |> inspect(content="X = [4,3,2,1]")
}

///|
test "factorial recursion" {
  let db = program_from_text(
    (
      #|fact(0, 1).
      #|fact(N, F) :- N > 0, N1 is N - 1, fact(N1, F1), F is N * F1.
      #|
    ),
  )
  let session = Session(db)
  let out = StringBuilder()
  answers_string(session, "fact(5, F).", out) |> inspect(content="F = 120")
}

///|
test "fibonacci" {
  let db = program_from_text(
    (
      #|fib(0, 0).
      #|fib(1, 1).
      #|fib(N, F) :- N > 1, N1 is N - 1, N2 is N - 2, fib(N1, F1), fib(N2, F2), F is F1 + F2.
      #|
    ),
  )
  let session = Session(db)
  let out = StringBuilder()
  answers_string(session, "fib(10, F).", out) |> inspect(content="F = 55")
}

///|
test ": with concrete list and predicate" {
  let db = program_from_text(
    (
      #|has(X, L) :- X : L.
      #|
    ),
  )
  let session = Session(db)
  let out = StringBuilder()
  answers_string(session, "has(a, [b, a, c]).", out) |> inspect(content="true")
  let out2 = StringBuilder()
  answers_string(session, "has(z, [b, a, c]).", out2)
  |> inspect(content="false")
}

///|
test "findall with arithmetic goal" {
  let db = program_from_text(
    (
      #|between(0, N, N).
      #|
    ),
  )
  let session = Session(db)
  let out = StringBuilder()
  answers_string(session, "findall(X, (X = 1 ; X = 2 ; X = 3), L).", out)
  |> inspect(content="L = [1,2,3]")
}

///|
test "deep unification with repeated variables" {
  let db = program_from_text(
    (
      #|pair(X, X).
      #|
    ),
  )
  let session = Session(db)
  let out = StringBuilder()
  answers_string(session, "pair(f(a, b), f(a, b)).", out)
  |> inspect(content="true")
  let out2 = StringBuilder()
  answers_string(session, "pair(f(a, b), f(a, c)).", out2)
  |> inspect(content="false")
}

///|
test "quoted atom functor" {
  let goals = parse_query_text("'hello world'(a).")
  guard goals.head() is Some(Compound("hello world", [Atom("a")])) else {
    fail("quoted functor not parsed")
  }
}

///|
test "write shows operator terms" {
  let session = Session(Database())
  let out = StringBuilder()
  answers_string(session, "write(2 + 3).", out) |> inspect(content="true")
  out.to_string() |> inspect(content="2+3")
}

///|
test "openct prefix vs spaced paren" {
  // 运算符名后紧跟 `(`（OpenCT）按函数记法解析：`,` 是目标分隔符
  // 对应 Scryer `':'(','(:-(a),b))` 的行为
  let t1 = parse_query_text("let(a), b.")
  inspect(t1.length(), content="2")
  guard t1.head() is Some(Compound("let", [Atom("a")])) else {
    fail("let(a) should be function notation")
  }
  // 运算符名后跟空格 `(`：作为前缀运算符吸收括号项与逗号
  // 对应 Scryer `:-(','(a,b))` 的行为
  let t2 = parse_query_text("let (a), b.")
  inspect(t2.length(), content="1")
  guard t2.head() is Some(Compound("let", [Compound(",", [Atom("a"), _])])) else {
    fail("let (a), b should be absorbed as single arg")
  }
}
