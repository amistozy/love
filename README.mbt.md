# Love：用 MoonBit 实现的迷你 Prolog

Love 是一个用 [MoonBit](https://docs.moonbitlang.com) 实现的类 Prolog 逻辑编程语言。它遵循 Prolog 的核心模型：程序由**子句**（事实与规则）构成，查询通过**合一**与**带回溯的 SLD 解析**求解，并附带交互式 REPL。实现针对教学场景做了简化，但保留了核心语义。

## 特性

- **完整语法分析**：递归下降 + 运算符优先级爬升，支持函数记法、列表糖、引号原子、注释
- **纯函数式合一**：持久化不可变 HashMap 作为环境，结构共享、无 trail，带 occurs check
- **显式回溯**：选择点栈驱动的深度优先 SLD 解析，支持逐解枚举与无限程序
- **核心控制结构**：cut、否定即失败（`\+`）、`call/1`、析取
- **丰富内建谓词**：算术、列表、元编程（findall/bagof/setof）、动态数据库、会话控制
- **交互式 REPL**：逐解交互、预读自动收尾、`let`/`~`/`+` 便利谓词

## 快速开始

```bash
moon test              # 运行全部测试（36 个）
moon run cmd/main      # 启动 REPL
```

## REPL

提示符 `?- ` 后直接输入查询目标：

```prolog
?- X : [1,2,3].
X = 1 ;
X = 2 ;
X = 3.          % 预读（lookahead）发现无更多解，自动以句号收尾

?- X = 1.
X = 1.          % 单解直接结束，无需输入分号/句号
```

| 操作 | 行为 |
|---|---|
| `;` 查看下一个解 | 行尾显示 ` ;`，最后一个解自动以 `.` 收尾；无更多解打印 `false.` |
| `let Head.` / `let Head :- Body.` | 断言事实/规则到数据库 |
| `~foo/2.` | 按谓词指示符删除 `foo/2` 的全部子句 |
| `del.` | 清空动态数据库（删除全部子句） |
| `cls.` | 清屏（静默，无输出） |
| `+name.` | 导入 `name.love` |
| `halt.` | 退出 |

多行输入：输入不以 `.` 结束时用 ` | ` 续行。

## 语言

### 项（Term）

| 语法 | 含义 | 内部表示 |
|---|---|---|
| `42` | 整数 | `Int(Int)` |
| `foo`、`'hello world'` | 原子 | `Atom(String)` |
| `X`、`_` | 变量（大写/下划线开头） | `Var(String)` |
| `f(a, b)` | 复合项 | `Compound("f", [a, b])` |
| `[a, b, c]`、`[H \| T]`、`[]` | 列表 | `Compound(".", ...)` 链 |

### 子句与查询

```prolog
parent(tom, bob).                                  % 事实
grandparent(X, Y) :- parent(X, Z), parent(Z, Y).   % 规则
?- grandparent(tom, Who).                          % 查询 → Who = ann
```

### 运算符（优先级数字越大越松散）

```
1300 fy   let ~
1200 xfx  :-
1100 xfy  ;          1000 xfy  ,
 900 fy   \+         700 xfx  = \= == \== < > =< >= =:= =\= is :
 500 yfx  + -        400 yfx  * / //   400 xfx  mod
 200 xfy  ^          200 fy   - +
```

- `let`/`~`（1300）优先级高于 `:-`（1200）与 `/`（700）：`let Head :- Body.` 无需括号；`~foo/2.` 中 `~` 吸收谓词指示符。`+file.`（`+` 一元前缀）导入文件。
- `^`（200 xfy）是 bagof/setof 的存在量词运算符。
- 运算符名可作复合项 functor（函数记法）：`+(2,3)` 解析为 `2+3`；运算符名后紧跟 `(`（OpenCT）时按函数记法解析、不作为前缀运算符——`let(foo), X = 1.` 中 `,` 是目标分隔符（对照 `let (foo), X = 1.` 中 `,` 是 `let` 的参数）。
- 复合项 functor 必须紧跟 `(`：`foo(a)` 是复合项，`foo (a)` 是语法错误。
- 答案可回读：解值自动加括号保证重读无歧义（`X = (\+1)`、`X = (a;b)`）。

### 语义

- **合一**：持久化不可变 HashMap + occurs check（`X = f(X)` 失败）。
- **SLD 解析**：深度优先、最左目标、按子句书写顺序尝试；显式选择点栈支持逐解产出（`next_solution`）与无限程序（`length(L, N)` 逐解枚举）。
- **cut（`!`）**：截断选择点栈到当前子句进入时的高度，剪除替代分支。
- **否定即失败**：`\+ Goal` 子目标有解则失败，无解则成功（复用 `call/1`）。
- **未绑定变量/数字不能作为目标**（如 `?- X.`、`?- 1.`），返回 `false.`。
- **紧凑输出**：列表 `[1,2,3]`、`2+3`、`-5`、`\+foo` 无多余空格；字母类运算符（`is`/`mod`）保留空格避免黏连；相邻 graphic 符号运算符加空格保证回读（`- +5`，因 `-+` 会合并为未知 token 报错）；非标识符 functor 自动加引号。

## 内建谓词

- 控制：`true/0`、`fail/0`、`!/0`、`\+/1`、`call/1`、析取 `;/2`
- 合一/比较：`=/2`、`\=/2`、`==/2`、`\==/2`
- 项检查：`var/1`、`nonvar/1`、`atom/1`、`integer/1`、`atomic/1`、`compound/1`、`ground/1`
- 算术：`is/2`、`=:=/2`、`=\=/2`、`</2`、`>/2`、`=</2`、`>=/2`、`between/3`
- 列表：`:/2`（`X : [1,2,3]` 中缀成员）、`length/2`（双向）、`append/3`、`sort/2`（标准项序排序去重）、`keysort/2`（按键稳定排序，不去重）
- 元编程：`findall/3`、`bagof/3`（按 witness 分组）、`setof/3`（排序去重）、`^/2`
- 动态数据库：`let/1`（断言）、`~/1`（按 `Name/Arity` 删除全部子句）、`del/0`（清空数据库）、`listing/0`（列出全部子句）、`listing/1`（列出谓词定义）
- 会话：`cls/0`（清屏）、`halt/0`（退出）、`+/1`（加载 `name.love`，即 `+name.`）
- 输出：`write/1`、`writeln/1`、`nl/0`
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
| `Database()` / `Session(db)` | 创建数据库 / 会话 |
| `program_from_text(src)` | 从子句文本创建数据库 |
| `load_program(db, src)` / `load_text(session, src)` | 把子句文本原地加载进数据库 |
| `query(session, query_text)` | 从查询文本创建求解引擎（裸目标，不含 `?-`） |
| `next_solution(engine)` / `solve_all(engine)` | 逐解产出（`Env?`）/ 全部解的惰性迭代器（`Iter[Env]`） |
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
| `token.mbt` / `lexer.mbt` | 词法分析（含 OpenCT 紧凑括号区分） |
| `term.mbt` | 项表示、展示（列表/运算符/引号规则） |
| `parser.mbt` | 递归下降 + 优先级爬升（函数记法、括号隔离标记、惰性 `flatten`） |
| `unify.mbt` | 合一（持久化 HashMap + occurs check）、标准项序 `term_compare` |
| `engine.mbt` | 数据库、会话、链表目标队列、选择点栈求解引擎 |
| `builtins.mbt` | 内建谓词（call/bagof/setof 复用目标展开，`:/2` 等用伪子句实现双向性） |
| `api.mbt` | 顶层 API |
| `cmd/main/` | 交互式 REPL（native + async stdio） |

## 测试

```bash
moon test          # 36 个测试
moon coverage analyze > uncovered.log   # 查看未覆盖代码
```

覆盖解析（运算符优先级、函数记法、OpenCT 紧凑括号、列表糖、括号隔离）、合一（occurs check）、经典递归（nrev/factorial/fibonacci）、cut 语义、否定即失败、call、findall/bagof/setof（分组/排序去重/`^` 量化）、sort/keysort、动态数据库（let/~）、会话谓词（cls/halt/+）、变量/数字目标失败、紧凑输出与括号可回读等。
