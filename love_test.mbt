///|
/// Love 解释器核心功能测试（黑盒，通过 @love 公共 API）
test "parse program and query" {
  let db = @love.program_from_text(
    (
      #|parent(tom, bob).
      #|parent(bob, ann).
      #|grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- grandparent(tom, Who).", out)
  |> inspect(content="Who = ann")
}

///|
test "append generates all splits" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- append(X, Y, [1, 2, 3]).", out)
  |> inspect(
    content="X = [], Y = [1,2,3]; X = [1], Y = [2,3]; X = [1,2], Y = [3]; X = [1,2,3], Y = []",
  )
}

///|
test ": enumerates solutions" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- X : [a,b,c].", out)
  |> inspect(content="X = a; X = b; X = c")
}

///|
test "length works both directions" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- length([1, 2, 3], N).", out)
  |> inspect(content="N = 3")
  let out2 = StringBuilder()
  @love.answers_string(session, "?- length(L, 2).", out2)
  |> inspect(content="L = [_,_]")
}

///|
test "arithmetic is and comparison" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- X is 2 + 3 * 4.", out)
  |> inspect(content="X = 14")
  let out2 = StringBuilder()
  @love.answers_string(session, "?- 2 + 3 =:= 5.", out2)
  |> inspect(content="true")
  let out3 = StringBuilder()
  @love.answers_string(session, "?- 3 < 2.", out3) |> inspect(content="false")
}

///|
test "cut prunes alternatives" {
  let db = @love.program_from_text(
    (
      #|p(1).
      #|p(2) :- !.
      #|p(3).
      #|q(X) :- p(X).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- q(X).", out)
  |> inspect(content="X = 1; X = 2")
}

///|
test "cut in middle of body" {
  let db = @love.program_from_text(
    (
      #|p(X) :- q(X), !, r(X).
      #|q(1).
      #|q(2).
      #|r(1).
      #|r(3).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- p(X).", out) |> inspect(content="X = 1")
}

///|
test "cut removes alternative clause" {
  let db = @love.program_from_text(
    (
      #|p(X) :- q(X), !.
      #|q(1).
      #|q(2).
      #|p(3).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- p(X).", out) |> inspect(content="X = 1")
}

///|
test "negation as failure" {
  let db = @love.program_from_text(
    (
      #|man(tom).
      #|man(bob).
      #|woman(ann).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- \\+ man(ann).", out)
  |> inspect(content="true")
  let out2 = StringBuilder()
  @love.answers_string(session, "?- \\+ man(tom).", out2)
  |> inspect(content="false")
}

///|
test "findall collects solutions" {
  let db = @love.program_from_text(
    (
      #|color(red).
      #|color(green).
      #|color(blue).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- findall(C, color(C), L).", out)
  |> inspect(content="L = [red,green,blue]")
}

///|
test "findall with comma and disjunction goal" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  // goal 是 `,` 复合（多目标），需扁平化
  @love.answers_string(
    session, "?- findall(Y, (X : [1,2,3], Y is X+1), L).", out,
  )
  |> inspect(content="L = [2,3,4]")
  // goal 混合 `,` 与 `;`
  @love.answers_string(session, "?- findall(X, (X : [1,2] ; X = 9), L).", out)
  |> inspect(content="L = [1,2,9]")
  // `\+` 的 goal 含 `,`：有解则否定失败
  @love.answers_string(session, "?- \\+ (X = 1, Y = 2).", out)
  |> inspect(content="false")
  @love.answers_string(session, "?- \\+ (X = 1, X = 2).", out)
  |> inspect(content="true")
}

///|
test "call meta predicate" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  // call 执行 `,` 复合目标
  @love.answers_string(session, "?- call((X = 1, Y = 2)).", out)
  |> inspect(content="X = 1, Y = 2")
  // call 支持回溯
  @love.answers_string(session, "?- call(X : [1,2]).", out)
  |> inspect(content="X = 1; X = 2")
  // call 执行 `;` 析取
  @love.answers_string(session, "?- call((X : [1,2] ; X = 9)).", out)
  |> inspect(content="X = 1; X = 2; X = 9")
  // 数字/失败目标
  @love.answers_string(session, "?- call(1).", out) |> inspect(content="false")
  @love.answers_string(session, "?- call(fail).", out)
  |> inspect(content="false")
}

///|
test "disjunction with semicolon" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- (X = a ; X = b ; X = c).", out)
  |> inspect(content="X = a; X = b; X = c")
}

///|
test "write builtin outputs to buffer" {
  let db = @love.program_from_text(
    (
      #|greet(X) :- write('hello '), writeln(X).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- greet(world).", out)
  |> inspect(content="true")
  out.to_string() |> inspect(content="hello world\n")
}

///|
test "unification with occurs check" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- X = f(X).", out) |> inspect(content="false")
}

///|
test "family tree with multiple answers" {
  let db = @love.program_from_text(
    (
      #|parent(tom, bob).
      #|parent(tom, sue).
      #|parent(bob, ann).
      #|parent(sue, joe).
      #|grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
      #|sibling(X, Y) :- parent(Z, X), parent(Z, Y), X \= Y.
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- grandparent(tom, Who).", out)
  |> inspect(content="Who = ann; Who = joe")
  let out2 = StringBuilder()
  @love.answers_string(session, "?- sibling(bob, X).", out2)
  |> inspect(content="X = sue")
}

///|
test "quoted atoms and lists display" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- X = 'hello world'.", out)
  |> inspect(content="X = 'hello world'")
  let out2 = StringBuilder()
  @love.answers_string(session, "?- X = [a,b | T].", out2)
  |> inspect(content="X = [a,b|T]")
}

///|
test "variable identity preserved across clause" {
  let db = @love.program_from_text(
    (
      #|same(X, X).
      #|
    ),
  )
  let session = @love.Session::new(db)
  let out = StringBuilder()
  @love.answers_string(session, "?- same(a, b).", out)
  |> inspect(content="false")
  let out2 = StringBuilder()
  @love.answers_string(session, "?- same(a, a).", out2)
  |> inspect(content="true")
}

///|
test "unbound predicate fails" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  @love.answers_string(session, "?- unknown_predicate(x).", out)
  |> inspect(content="false")
}

///|
test "let and del builtins" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  // 断言事实
  @love.answers_string(session, "?- let parent(tom, bob).", out)
  |> inspect(content="true")
  // 断言规则：let 优先级高于 :-，无需括号
  @love.answers_string(session, "?- let parent(bob, ann) :- true.", out)
  |> inspect(content="true")
  // 查询断言结果
  @love.answers_string(session, "?- parent(tom, X).", out)
  |> inspect(content="X = bob")
  // 按谓词指示符删除全部子句
  @love.answers_string(session, "?- del parent/2.", out)
  |> inspect(content="true")
  @love.answers_string(session, "?- parent(tom, X).", out)
  |> inspect(content="false")
  // 删除不存在的谓词失败
  @love.answers_string(session, "?- del nope/3.", out)
  |> inspect(content="false")
  // 非谓词指示符参数失败
  @love.answers_string(session, "?- del parent(x, y).", out)
  |> inspect(content="false")
}

///|
test "variable or number as goal fails" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  // 未绑定变量不能作为目标（不崩溃，失败）
  @love.answers_string(session, "?- X.", out) |> inspect(content="false")
  // 数字不能作为目标
  @love.answers_string(session, "?- 1.", out) |> inspect(content="false")
  // 变量绑定到复合项后按其求解（foo/1 未定义 → 失败）
  @love.answers_string(session, "?- X = foo(1), X.", out)
  |> inspect(content="false")
  // 绑定到已定义谓词则正常求解（X 作为查询变量被显示）
  let _ = @love.load_text(session, "bar(7).")
  @love.answers_string(session, "?- X = bar(7), X.", out)
  |> inspect(content="X = bar(7)")
}

///|
test "cls halt consult builtins" {
  let session = @love.Session::new(@love.Database::new())
  let out = StringBuilder()
  // cls/0：把 ANSI 清屏序列写入输出缓冲
  @love.answers_string(session, "?- cls.", out) |> inspect(content="true")
  out.to_string() |> inspect(content="\u{1b}[2J\u{1b}[H")
  // halt/0：请求退出（不真正终止测试）
  @love.answers_string(session, "?- halt.", out) |> inspect(content="true")
  session.halt_requested() |> inspect(content="true")
  // consult/1：读取 `.love` 文件并加载子句
  let _ = @fs.write_string_to_file("love_consult_test.love", "p(a). p(b).")
  @love.answers_string(session, "?- consult(love_consult_test).", out)
  |> inspect(content="true")
  @love.answers_string(session, "?- p(X).", out)
  |> inspect(content="X = a; X = b")
  // 语法错误的文件 → consult 失败
  let _ = @fs.write_string_to_file("love_consult_bad.love", "broken(")
  @love.answers_string(session, "?- consult(love_consult_bad).", out)
  |> inspect(content="false")
  // 文件不存在 → consult 失败
  @love.answers_string(session, "?- consult(no_such_file_xyz).", out)
  |> inspect(content="false")
  // 清理临时文件
  let _ = @fs.remove_file("love_consult_test.love")
  let _ = @fs.remove_file("love_consult_bad.love")
}
