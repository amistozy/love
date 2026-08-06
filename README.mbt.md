# Love：一个用 MoonBit 实现的类 Prolog 语言

Love 是一个逻辑编程（logic programming）语言，语法与语义遵循 Prolog 的核心
模型：程序由**子句**（事实与规则）构成，查询通过**合一**与**带回溯的 SLD 解析**
求解。实现参考了 [Scryer Prolog](https://github.com/mthom/scryer-prolog)
（WAM 架构）的设计，但针对教学场景做了大幅简化：直接以项结构递归合一，
用显式选择点栈实现回溯；环境采用**持久化不可变 HashMap**
（`moonbitlang/core/immut/hashmap`），绑定返回结构共享的新环境，省去 trail。

## 语言概览

### 项（Term）

| 语法 | 含义 | 内部表示 |
|---|---|---|
| `42` | 整数 | `Int(Int)` |
| `foo`、`'hello world'` | 原子 | `Atom(String)` |
| `X`、`_` | 变量（大写/下划线开头） | `Var(String)` |
| `f(a, b)` | 复合项 | `Compound("f", [a, b])` |
| `[a, b, c]`、`[H \| T]`、`[]` | 列表（`.`/`[]` 链语法糖） | `Compound(".", ...)` |

### 子句与查询

```prolog
parent(tom, bob).                    % 事实
grandparent(X, Y) :- parent(X, Z), parent(Z, Y).   % 规则
?- grandparent(tom, Who).            % 查询（答案为 Who = ann）
```

### 运算符（优先级数字越大越松散）

```
1200 xfx  :-         1300 fy   let del
1100 xfy  ;          1000 xfy  ,
 900 fy   \+ not      700 xfx  = \= == \== < > =< >= =:= =\= is
 500 yfx  + -         400 yfx  * / // mod
 200 fy   -
```

## 语义

- **合一**：持久化不可变 HashMap + occurs check（`X = f(X)` 失败）。
- **SLD 解析**：深度优先、最左目标、按子句书写顺序尝试；显式选择点栈支持
  逐解产出（`next_solution`）与无限程序（`length(L, N)` 逐解枚举）。
- **cut（`!`）**：截断选择点栈到当前子句进入时的高度，剪除替代分支。
- **否定即失败**：`\+ Goal` 子目标有解则失败，无解则成功。

## 内建谓词

- 控制：`true/0`、`fail/0`、`!/0`、`\+/1`、`not/1`、析取 `;/2`
- 合一/比较：`=/2`、`\=/2`、`==/2`、`\==/2`
- 项检查：`var/1`、`nonvar/1`、`atom/1`、`integer/1`、`atomic/1`、`compound/1`、`ground/1`
- 算术：`is/2`、`=:=/2`、`=\=/2`、`</2`、`>/2`、`=</2`、`>=/2`
- 列表：`member/2`、`length/2`（双向）、`append/3`
- 元编程：`findall/3`
- 动态数据库：`let/1`、`del/1`（前缀运算符，对应 `assert`/`retract`）
- 输出（写入会话缓冲）：`write/1`、`writeln/1`、`nl/0`
- 字符串：`atom_length/2`、`char_code/2`

## 示例程序

```prolog
% 列表反转
nrev([], []).
nrev([H | T], R) :- nrev(T, R1), append(R1, [H], R).

% 阶乘
fact(0, 1).
fact(N, F) :- N > 0, N1 is N - 1, fact(N1, F1), F is N * F1.

% 剪枝：p(X) 只给出 X = 1
p(X) :- q(X), !.
q(1).  q(2).
p(3).
```

## 使用

```bash
moon test              # 运行全部测试
moon run --target native cmd/main   # 启动 REPL
```

REPL 采用 SWI-Prolog 风格的顶层交互：提示符 `?- ` 后**直接输入查询目标**
（无需再写 `?-`），答案后输入 `;` 看下一个解、`.` 或回车结束、无更多解时
打印 `false.`；用 `let` / `del` 前缀运算符断言或删除子句（对应标准 Prolog
的 `assert`/`retract`）；`halt.` 退出。

```prolog
?- let parent(tom, bob).         % 断言事实
true.
?- let grandparent(X, Y) :- parent(X, Z), parent(Z, Y).   % 断言规则（无需括号，let 优先级高于 :-）
true.
?- grandparent(tom, Who).
Who = ann ;
false.
?- del parent(tom, bob).         % 删除子句
true.
```

## 代码组织（参考 Scryer Prolog 的结构）

| 文件 | 职责 |
|---|---|
| `ops.mbt` | 运算符表（优先级/结合性） |
| `token.mbt` / `lexer.mbt` | 词法分析 |
| `term.mbt` | 项表示、展示（列表/运算符/引号规则） |
| `parser.mbt` | 递归下降 + 优先级爬升 |
| `unify.mbt` | 合一（持久化 HashMap + occurs check） |
| `engine.mbt` | 数据库、会话、选择点栈求解引擎 |
| `builtins.mbt` | 内建谓词（member/length/append 用伪子句展开实现双向性） |
| `api.mbt` | 顶层 API（`program_from_text`、`answers_string`） |
| `cmd/main/` | 交互式 REPL（native + async stdio） |

与 Scryer Prolog 的对应关系：Scryer 用 heap/trail/寄存器堆的 WAM 实现，
Love 用选择点栈 + 持久化不可变 HashMap；Scryer 的 `parser.rs` 用操作数栈规约，
Love 用优先级爬升。两者都遵循 ISO Prolog 的运算符约束（`xfx`/`xfy`/`yfx`）。
