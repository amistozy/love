# Love：一个用 MoonBit 实现的类 Prolog 语言

Love 是一个逻辑编程（logic programming）语言，语法与语义遵循 Prolog 的核心
模型：程序由**子句**（事实与规则）构成，查询通过**合一**与**带回溯的 SLD 解析**
求解。实现针对教学场景做了简化：直接以项结构递归合一，用显式选择点栈实现
回溯；环境采用**持久化不可变 HashMap**（`moonbitlang/core/immut/hashmap`），
绑定返回结构共享的新环境，省去 trail。

## 快速开始

```bash
moon test                 # 运行全部测试（36 个）
moon run --target native cmd/main   # 启动 REPL
```

## REPL

提示符 `?- ` 后直接输入查询目标，采用 SWI-Prolog 风格的逐解交互：

```prolog
?- X : [1,2,3].
X = 1 ;
X = 2 ;
X = 3.           ← 预读（lookahead）发现无更多解，自动以句号收尾

?- X = 1.
X = 1.           ← 单解直接结束，无需输入分号/句号
```

**句号规则**：程序自动收尾的句号前**没有空格**（`X = 3.`）；用户手动输入的
句号（终端回显）前才有空格（`X = 2 .`）。

### 交互约定

| 操作 | 行为 |
|---|---|
| 输入查询目标 | 提示符 `?- ` 后直接输入，如 `X : [1,2]`. |
| `;` 看下一个解 | 有后续解时行尾显示 ` ;`，最后一个解自动 `.` 收尾 |
| 无更多解 | 打印 `false.` |
| 多行输入 | 输入不以 `.` 结束时用 ` | ` 续行（如长查询换行写） |
| `let Head.` / `let Head :- Body.` | 断言事实/规则到数据库 |
| `del foo/2.` | 按谓词指示符删除 `foo/2` 的全部子句 |
| `cls.` | 清屏（静默，无输出） |
| `[name].` | 导入 `name.love`（`consult(name).` 的语法糖） |
| `halt.` | 退出 |

```prolog
?- let parent(tom, bob).                          % 断言事实
true.
?- let grandparent(X, Y) :- parent(X, Z), parent(Z, Y).   % 断言规则（let 优先级高于 :-，无需括号）
true.
?- [family].                                      % 导入 family.love
true.
?- grandparent(tom, Who).
Who = ann.                                        % 单解，预读直接收尾
?- del parent/2.                                  % 删除谓词 parent/2 的全部子句
true.
?- cls.                                           % 清屏（静默）
?- halt.                                          % 退出
```

`[name].` 的判定在 term 层完成：读入的 term 为**单元素列表 `[Item]` 且
`Item` 是原子**时转成 `consult(Item)` 查询；`[X, Y] = [2, 3].`、`[X].` 等
不会被误判，仍按普通查询求解。

## 语言

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
1300 fy   let del
1200 xfx  :-
1100 xfy  ;          1000 xfy  ,
 900 fy   \+         700 xfx  = \= == \== < > =< >= =:= =\= is :
 500 yfx  + -         400 yfx  * / // mod
 200 xfy  ^          200 fy   -
```

- `let`/`del`（1300）优先级高于 `:-`（1200）：`let Head :- Body.` 无需括号
  即可把整个规则作为参数——它们是 REPL 便利谓词，不出现在谓词定义中。
- `^`（200 xfy）是 bagof/setof 的存在量词运算符：`Y^Goal` 中 `Y` 不参与分组。
- 运算符名可作为复合项 functor（函数记法）：`+(2,3)` 解析为 `2+3`、`is(X,Y)`
  解析为 `X is Y`。

### 语法与优先级约束

- **前缀运算符受上下文优先级约束**（ISO）：`X = \+ 1` 报语法错误
  （`\+` 900 超过 `=` 右操作数 699 的允许范围，与 SWI 的 Operator priority
  clash / Scryer 的 incomplete_reduction 一致）；需写作 `X = (\+ 1)`。
- **答案可回读**：解值写在 `=` 右操作数上下文，`\+`/`let`/`;`/`,` 等优先级
  高于 699 的项自动加括号（`X = (\+1)`、`X = (a;b)`、`X = (a,b)`）；`- 1`
  显示为 `-1`。

### 语义

- **合一**：持久化不可变 HashMap + occurs check（`X = f(X)` 失败）。
- **SLD 解析**：深度优先、最左目标、按子句书写顺序尝试；显式选择点栈支持
  逐解产出（`next_solution`）与无限程序（`length(L, N)` 逐解枚举）。
- **cut（`!`）**：截断选择点栈到当前子句进入时的高度，剪除替代分支。
- **否定即失败**：`\+ Goal` 子目标有解则失败，无解则成功（复用 `call/1`）。
- **未绑定变量/数字不能作为目标**（如 `?- X.`、`?- 1.`），返回 `false.` 而非崩溃。
- **紧凑输出**：列表 `[1,2,3]`、复合 `foo(bar,baz)`、符号运算符 `2+3`、
  前缀 `-5`、`\+foo` 无多余空格；字母类运算符（`is`/`mod`）保留空格
  （`2 is 3`）避免黏连。

## 内建谓词

- 控制：`true/0`、`fail/0`、`!/0`、`\+/1`、`call/1`、析取 `;/2`
- 合一/比较：`=/2`、`\=/2`、`==/2`、`\==/2`
- 项检查：`var/1`、`nonvar/1`、`atom/1`、`integer/1`、`atomic/1`、`compound/1`、`ground/1`
- 算术：`is/2`、`=:=/2`、`=\=/2`、`</2`、`>/2`、`=</2`、`>=/2`、`between/3`
- 列表：`:/2`（`X : [1,2,3]`，中缀成员）、`length/2`（双向）、`append/3`
- 元编程：`findall/3`、`bagof/3`（按 witness 分组）、`setof/3`（排序去重）、`^/2`（存在量词）
- 动态数据库：`let/1`（断言，对应 `assert`）、`del/1`（按谓词指示符 `Name/Arity` 删除全部子句）
- 会话：`cls/0`（清屏）、`halt/0`（退出）、`consult/1`（加载 `name.love`，`[name].` 为其语法糖）
- 输出（写入会话缓冲）：`write/1`、`writeln/1`、`nl/0`
- 字符串：`atom_length/2`、`char_code/2`

### bagof / setof 分组

```prolog
?- f(1, 2). f(1, 3). f(2, 4).
?- bagof(X, f(X, Y), L).          % Y 是 witness（Goal 中自由、不在模板、未量化）
L = [1] ; L = [1] ; L = [2].      % 按 Y=2,3,4 分三组
?- bagof(X, Y^f(X, Y), L).        % Y 存在量化
L = [1,1,2].
?- setof(X, Y^f(X, Y), L).        % 排序去重
L = [1,2].
?- bagof(X, f(X, 9), L).          % 无解 → 失败（区别于 findall 的 []）
false.
```

## 示例程序

```prolog
% 列表反转
nrev([], []).
nrev([H | T], R) :- nrev(T, R1), append(R1, [H], R).

% 阶乘
fact(0, 1).
fact(N, F) :- N > 0, N1 is N - 1, fact(N1, F1), F is N * F1.

% 斐波那契
fib(0, 0).
fib(1, 1).
fib(N, F) :- N > 1, N1 is N - 1, N2 is N - 2, fib(N1, F1), fib(N2, F2), F is F1 + F2.

% 剪枝：p(X) 只给出 X = 1
p(X) :- q(X), !.
q(1).  q(2).
p(3).

% 元编程：收集所有满足条件的元素
?- findall(Y, (X : [1,2,3], Y is X*10), L).
L = [10,20,30].
```

## 库 API（`amistozy/love`）

| 函数 | 说明 |
|---|---|
| `program_from_text(src)` | 从子句文本创建数据库 |
| `load_program(db, src)` | 把子句文本原地加载进已有数据库 |
| `load_text(session, src)` | 加载进会话的数据库（`[file].` 导入用） |
| `query(session, query_text)` | 从查询文本创建求解引擎 |
| `next_solution(engine)` | 逐步产出解（`Env?`），支持逐解枚举 |
| `solve_all(engine)` | 收集全部解 |
| `answers_string(session, query, out)` | 生成答案文本（REPL/测试用） |
| `engine_vars(engine)` | 查询中的顶层变量名 |
| `parse_program_text` / `parse_clause_text` / `parse_query_text` / `lex` | 解析入口 |
| `unify` / `walk` / `walk_deep` / `term_identical` / `is_ground` / `term_compare` | 合一与展开 |
| `term_to_string` / `term_to_string_plain` / `write_term` / `clause_to_string` | 项展示 |

错误通过 `LoveError` 抛出（`raise LoveError`）。

## 代码组织

| 文件 | 职责 |
|---|---|
| `ops.mbt` | 运算符表（优先级/结合性） |
| `token.mbt` / `lexer.mbt` | 词法分析 |
| `term.mbt` | 项表示、展示（列表/运算符/引号规则） |
| `parser.mbt` | 递归下降 + 优先级爬升（含函数记法 `+(2,3)`） |
| `unify.mbt` | 合一（持久化 HashMap + occurs check）、标准项序 `term_compare` |
| `engine.mbt` | 数据库（`(name/arity)` → 子句列表）、会话、选择点栈求解引擎 |
| `builtins.mbt` | 内建谓词（call/bagof/setof 复用目标展开，`:/2` 等用伪子句实现双向性） |
| `api.mbt` | 顶层 API（`program_from_text`、`answers_string`） |
| `cmd/main/` | 交互式 REPL（native + async stdio） |

## 测试

```bash
moon test          # 36 个测试
moon coverage analyze > uncovered.log   # 查看未覆盖代码
```

覆盖：解析（运算符优先级、函数记法、列表糖、匿名变量、前缀优先级约束）、
合一（occurs check、重复变量）、经典递归（nrev/factorial/fibonacci）、
cut 语义、否定即失败、call、findall/bagof/setof（分组/排序去重/`^` 量化）、
between、析取、动态数据库（let/del）、会话谓词（cls/halt/consult）、
变量/数字目标失败、紧凑输出与括号可回读等。
