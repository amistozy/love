# Love —— 一门用 MoonBit 实现的逻辑编程语言

Love 是一门口袋大小的 **Prolog 风格逻辑编程语言**，用 [MoonBit](https://www.moonbitlang.com) 从零实现。
它的架构参考了 `reference/` 目录中的经典 Prolog 实现：

- **Trealla Prolog**（C）：WAM 风格堆单元 + trail 回溯，本项目的引擎设计主要参考它；
- **SWI-Prolog**（C）：内置谓词集、运算符优先级表、`findall/3` 等高级内置的语义参照；
- **Scryer Prolog**（Rust）：项表示与干净的错误处理参考；
- **Mercury**（逻辑+函数式）：语言设计文档风格参考。

Love 的目标不是复刻 ISO Prolog 的全部，而是用一套**小而完整**的核心
（项、合一、SLD 求解、回溯、cut、内置谓词、动态数据库、REPL）演示逻辑编程
语言的完整实现路径，全部代码可在 MoonBit 中编译、测试、运行。

## 1. 语法

Love 采用 Prolog 风格语法：事实、规则、查询；变量以大写字母或 `_` 开头；
谓词以 `.` 结束。

### 1.1 程序与查询

```
% 这是注释（% 到行尾）
/* 这也是注释 */

% 事实
likes(alice, bob).

% 规则：Head :- Body.
happy(X) :- likes(X, bob).

% 查询（交互式输入或命令行参数）
?- happy(X).
```

- 一个程序（program）由若干 `子句` 组成。
- 子句有三种：**事实** `Head.`、**规则** `Head :- Body.`、**指令** `:- Goal.`（在加载时执行一次，v0.1 支持）。
- 查询形式为 `?- Goal.`，也可直接给出目标项（REPL 中省略 `?-`）。

### 1.2 项（Term）

| 类别 | 示例 | 说明 |
| --- | --- | --- |
| 变量 | `X`、`Name`、`_` | 大写/下划线开头；`_` 为匿名变量，每次出现都是新变量 |
| 原子 | `alice`、`bob`、`foo_bar` | 小写开头；可用单引号 `'hello world'` 引用特殊字符 |
| 整数 | `42`、`-7`、`0xFF` | 64 位有符号整数 |
| 浮点数 | `3.14`、`1e-3`、`-2.5` | IEEE 754 double |
| 字符串 | `"hello"` | 双引号字符串，作为独立的字符串项（不同于 ISO 的字符码表） |
| 复合项 | `likes(alice, bob)`、`f(g(X))` | 函子 + 参数列表 |
| 列表 | `[]`、`[a, b, c]`、`[H | T]`、`[a, b | T]` | 空表 / 表头表尾 |
| 剪切 | `!` | 控制流内置 |

### 1.3 运算符（内置优先级表）

Love 内置一张与 ISO/SWI 兼容的运算符表，解析时按优先级与结合性组项：

| 优先级 | 运算符 | 结合性 |
| --- | --- | --- |
| 1200 | `:-` | xfx |
| 1100 | `;` | xfy |
| 1050 | `->` | xfy |
| 1000 | `,` | xfy |
| 900 | `\+` | fy |
| 700 | `=` `\=` `==` `\==` `@<` `@=<` `@>` `@>=` `is` `=:=` `=\=` `<` `=<` `>` `>=` `=..` | xfx |
| 500 | `+` `-` | yfx |
| 400 | `*` `/` `//` `mod` `rem` `div` | yfx |
| 200 | `^` | xfy |
| 200 | `-` `+` `\` | fy（前缀） |

- `x` 表示该侧不能出现同优先级运算符（用于实现左/右结合规则）。
- 用户在 REPL 中不能自定义运算符（v0.1 限制，语法上仅支持内置表）。

### 1.4 注释

- `% ...` 行注释；`/* ... */` 块注释（可跨行）。

## 2. 语义

### 2.1 求值模型

Love 采用标准 Prolog 的 **SLD 解析**：

- 深度优先、从左到右求解目标、自上而下选择子句；
- 每一步对目标头与子句头做**合一**（unification）；
- 失败时沿 **choice point** 回溯；
- 每次调用子句时，子句中的变量被**重命名**为全新变量（fresh rename）；
- 合一**默认不做 occurs check**（与主流 Prolog 一致），另提供
  `unify_with_occurs_check/2` 内置谓词。

### 2.2 变量绑定与回溯（trail）

- 每个变量在运行时有唯一整数 id；绑定存储在 `subst`（按 id 索引的数组）中；
- 每次绑定将变量 id 压入 `trail`；
- 回溯到某个 choice point 时，撤销 `trail` 中该点之后的所有绑定（并清空对应
  `subst` 槽位），恢复目标栈与子句游标，继续尝试下一条子句。

### 2.3 cut（`!`）

- `!` 提交当前子句内自进入该子句以来所做的所有选择：删除其后的 choice point，
  使回溯不再进入本子句的其它分支；
- 实现：每个目标帧携带 `barrier`（进入该子句体时的 choice point 数），执行
  `!` 时把 choice point 栈截断到 `barrier`。

### 2.4 多解枚举

- 求解器是**惰性迭代器**：每次 `next()` 只推进到下一个解，因此 REPL 可以逐个
  显示解，也便于 `findall/3` 收集全部解。

## 3. 内置谓词

### 3.1 控制流

`true/0`、`fail/0`、`!/0`、`call/1`、`,/2`、`;/2`、`->/2,3`、`\+/1`、`once/1`、
`repeat/0`。

### 3.2 项与合一

`=/2`、`\=/2`、`==/2`、`\==/2`、`unify_with_occurs_check/2`、`var/1`、
`nonvar/1`、`atom/1`、`number/1`、`integer/1`、`float/1`、`string/1`、
`atomic/1`、`compound/1`、`callable/1`、`ground/1`、`functor/3`、`arg/3`、
`=../2`、`atom_length/2`、`atom_concat/3`、`sub_atom/5`、`compare/3`、
`@</2` `@=</2` `@>/2` `@>=/2`。

### 3.3 列表

`member/2`、`append/3`、`length/2`、`reverse/2`、`sort/2`、`msort/2`、
`sum_list/2`、`maplist/2`、`nth0/3`、`nth1/3`。

### 3.4 算术

- `is/2`：求值右端算术表达式并与左端合一；
- 比较：`=:=` `=\=` `<` `=<` `>` `>=`（两端都求值）；
- `between/3`、`plus/3`；
- 可求值函子：`+ - * / // rem mod div abs max min sign sqrt exp log sin cos
  tan floor ceiling round truncate float integer`；
- 运算错误（除零、负数开方、非数值）**导致目标失败**（v0.1 简化，不做异常传播）。

### 3.5 动态数据库

- `assertz/1`、`asserta/1`、`retract/1`、`clause/2`、`listing/0`；
- `assertz/asserta` 向动态子句表追加/前插；`retract/1` 删除第一条可合一
  的动态子句；对静态（源码）谓词执行 `retract` 失败；
- 这让 REPL 中「边查询边建库」成为可能。

### 3.6 高阶与收集

- `call/1`、`maplist/2`、`findall/3`、`bagof/3`（v0.1 提供 `findall/3`，
  `bagof`/`setof` 留待后续）。

### 3.7 I/O

- `write/1`、`writeln/1`、`nl/0`；
- 通过 `@stdio`（native 目标）输出；后续可加 `read/1`。

## 4. 运行时架构（MoonBit 实现）

```
love.mbt       公开 API 门面（parse_program / solve / REPL 服务）
syntax.mbt     LoveTerm、Clause、Program 等 AST 类型
lexer.mbt      词法分析（token 流）
parser.mbt     Pratt 递归下降解析器（运算符优先级表）
unify.mbt      合一 + trail + occurs check
engine.mbt     SLD 引擎（目标栈 + choice point 栈 + cut barrier）
builtins.mbt   内置谓词分发
arith.mbt      算术表达式求值
pretty.mbt     项打印（运算符、列表、引号规则）
cmd/main        CLI：加载文件 + 查询 + REPL
```

核心数据结构：

```mbt
enum LoveTerm {
  Var(Int)                    // 变量，唯一 id
  Atom(String)                // 原子
  Int(Int64)
  Float(Double)
  Str(String)                 // 双引号字符串项
  Struct(String, Array[LoveTerm])  // 复合项
  ListCons(LoveTerm, LoveTerm)     // [H|T]
  ListNil
}

struct Engine {
  program : Map[String, PredClauses]   // 每个谓词的子句表（静态+动态）
  mut subst : Array[Option[LoveTerm]]  // 变量绑定
  mut trail : Array[Int]               // 绑定记录
  mut goals : Array[Frame]             // 目标栈
  mut cps : Array[ChoicePoint]         // choice point 栈
  mut var_counter : Int64              // 全新变量 id 生成器
}
```

## 5. CLI 用法

```
moon run cmd/main            # 空库启动 REPL
moon run cmd/main -- prog.lv  # 加载程序并进入 REPL
moon run cmd/main -- prog.lv "?- happy(X)."   # 运行单个查询并打印全部解
```

模块默认目标为 native（`moon.mod` 中 `preferred_target = "native"`），无需指定
`--target`；库代码本身保持目标无关，仍可用 `moon build --target wasm` 交叉构建。

REPL 交互参考 **Scryer Prolog** 的 toplevel：提示符 `?- `，多行输入续行提示 `|  `；
答案后跟 `;` 表示还有解（等待输入）、`.` 表示确定解（无剩余 choice point）。

```
?- happy(X).
   X = alice ;
;
   X = bob ;
.
;  ... .
?- X = 1 + 2, write(X), nl.
   3.
   X = 3.
```

答案后的按键：`;`/空格/`n` 下一个解，`Enter`/`.` 停止（显示 `;  ... .`），`a` 全部，
`f` 再 5 个，`h` 帮助。确定性判断基于 choice point 是否耗尽（对应 Scryer 用 WAM
B 寄存器比较：`B0 == B` 时为最终解）。

## 6. 与 ISO Prolog 的已知差异（v0.1）

1. 字符串 `"..."` 是字符串项，不是字符码列表；
2. 算术错误使目标失败而非抛出异常；
3. 无 `catch/3`、`throw/1`；
4. 无 DCG（`-->`）、模块系统、自定义运算符；
5. 无 occurs check（默认），仅提供显式内置；
6. `bagof/3`、`setof/3` 未实现（`findall/3` 已实现）。

## 7. 路线图

- [x] v0.1：解析器、合一、SLD 引擎、cut、内置谓词、算术、动态库、REPL
- [ ] v0.2：`catch/throw`、`bagof/setof`、DCG、`read/1`、自定义运算符
- [ ] v0.3：表驱动（tabling）、约束（CLP）、模块系统
