///|
/// Love 语言中的项（term）。
pub enum LoveTerm {
  /// 变量，id 为解析/运行时的唯一编号
  Var(Int)
  /// 原子
  Atom(String)
  /// 64 位整数
  Int(Int64)
  /// 浮点数
  Float(Double)
  /// 双引号字符串项
  Str(String)
  /// 复合项：函子 + 参数列表
  Struct(String, Array[LoveTerm])
  /// 列表 [H | T]
  ListCons(LoveTerm, LoveTerm)
  /// 空列表 []
  ListNil
} derive(Debug)

///|
/// 把数组构造成列表项（[a, b, c]）。
pub fn list_of(xs : Array[LoveTerm]) -> LoveTerm {
  list_of_with_tail(xs, LoveTerm::ListNil)
}

///|
/// 把数组构造成带尾部的列表项（[a, b | T]）。
pub fn list_of_with_tail(xs : Array[LoveTerm], tail : LoveTerm) -> LoveTerm {
  let mut acc = tail
  for i = xs.length() - 1; i >= 0; i = i - 1 {
    acc = LoveTerm::ListCons(xs[i], acc)
  }
  acc
}

///|
/// 子句：事实（body 为 true）或规则（body 为体目标）。
pub struct Clause {
  head : LoveTerm
  body : LoveTerm
} derive(Debug)

///|
/// 谓词的子句集合：静态（源码）与动态（assertz/asserta）。
pub struct PredClauses {
  statics : Array[Clause]
  dynamics : Array[Clause]
}

///|
/// Love 程序：谓词表、指令与运算符表。
pub struct Program {
  preds : Map[String, PredClauses]
  directives : Array[LoveTerm]
  /// 运算符表（op/3 可动态修改；默认内置表）
  ops : Map[String, OpDef]
  /// 标记为表驱动的谓词名（`:- table p/1.` 指令与 table/1 内置）
  tabled : Map[String, Bool]
  /// 表驱动运行时表：谓词名 -> 变体表项（每查询开始清空）
  tables : Map[String, Array[TableEntry]]
  /// 全局不动点求解的重入锁（批量求解子引擎中创建新变体时不再嵌套触发）
  passing : Array[Bool]
}

///|
/// 创建空程序（自动注入内置库子句）。
pub fn Program::new() -> Program {
  let p = Program::empty()
  p.seed_libraries()
  p
}

///|
/// 创建不注入库子句的空程序（解析器用：先加用户子句再注入库）。
pub fn Program::empty() -> Program {
  {
    preds: Map([]),
    directives: [],
    ops: op_table(),
    tabled: Map([]),
    tables: Map([]),
    passing: [false],
  }
}

///|
/// 使用程序当前的运算符表解析查询。
pub fn Program::parse_query(
  program : Program,
  src : String,
) -> LoveTerm raise LoveError {
  parse_query_with_ops(src, program.ops)
}

///|
/// 使用程序当前的运算符表解析查询并返回具名变量表。
pub fn Program::parse_query_with_names(
  program : Program,
  src : String,
) -> (LoveTerm, Map[Int, String]) raise LoveError {
  parse_query_with_names_ops(src, program.ops)
}

///|
/// 追加一条源码子句（保持源码顺序）。
fn Program::add_source_clause(program : Program, clause : Clause) -> Unit {
  let name = functor_of(clause.head)
  match program.preds.get(name) {
    None => program.preds[name] = { statics: [clause], dynamics: [] }
    Some(pc) => pc.statics.push(clause)
  }
}

///|
/// 追加一条动态子句（assertz/asserta）。
fn Program::assert_clause(
  program : Program,
  clause : Clause,
  at_head : Bool,
) -> Unit {
  let name = functor_of(clause.head)
  match program.preds.get(name) {
    None => program.preds[name] = { statics: [], dynamics: [clause] }
    Some(pc) =>
      if at_head {
        pc.dynamics.insert(0, clause)
      } else {
        pc.dynamics.push(clause)
      }
  }
}

///|
/// 谓词 name 的全部子句（静态在前，动态在后）。
fn Program::clauses_of(program : Program, name : String) -> Array[Clause] {
  match program.preds.get(name) {
    None => []
    Some(pc) => pc.statics + pc.dynamics
  }
}

///|
/// 全部子句（clause/2 用）。
fn Program::all_clauses(program : Program) -> Array[Clause] {
  let out : Array[Clause] = []
  for _, pc in program.preds {
    for c in pc.statics {
      out.push(c)
    }
    for c in pc.dynamics {
      out.push(c)
    }
  }
  out
}

///|
/// 注入内置库子句：member/append/length/reverse/sum_list/nth0/nth1。
/// 库子句追加在用户子句之后，用户自定义同名谓词优先。
fn Program::seed_libraries(program : Program) -> Unit {
  let src =
    #|member(X, [X | _]).
    #|member(X, [_ | T]) :- member(X, T).
    #|append([], L, L).
    #|append([H | T], L, [H | R]) :- append(T, L, R).
    #|length([], 0).
    #|length([_ | T], N) :- length(T, M), N is M + 1.
    #|reverse(L, R) :- reverse(L, [], R).
    #|reverse([], A, A).
    #|reverse([H | T], A, R) :- reverse(T, [H | A], R).
    #|sum_list([], 0).
    #|sum_list([H | T], S) :- sum_list(T, S0), S is S0 + H.
    #|nth0(0, [X | _], X).
    #|nth0(N, [_ | T], X) :- N > 0, M is N - 1, nth0(M, T, X).
    #|nth1(1, [X | _], X).
    #|nth1(N, [_ | T], X) :- N > 1, M is N - 1, nth1(M, T, X).
    #|
  for clause in parse_library_clauses(src) {
    program.add_source_clause(clause)
  }
}

///|
/// 解析库子句源码（内部使用，忽略错误则返回空）。
fn parse_library_clauses(src : String) -> Array[Clause] {
  let p = Program::empty()
  try parse_program_into(p, src) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  // 直接取出静态子句
  let out : Array[Clause] = []
  for _, pc in p.preds {
    for c in pc.statics {
      out.push(c)
    }
  }
  out
}

///|
/// 项的可调用函子名（子句头必须可调用）。
fn functor_of(t : LoveTerm) -> String {
  match t {
    Atom(n) => n
    Struct(n, _) => n
    _ => "$$"
  }
}

///|
/// 由项构造子句（assertz/asserta 用）：`H :- B` 为规则，否则为事实。
fn clause_from_term(t : LoveTerm) -> Clause {
  match t {
    Struct(":-", [h, b]) => { head: h, body: b }
    other => { head: other, body: LoveTerm::Atom("true") }
  }
}
