# Love —— 一门用 MoonBit 实现的逻辑编程语言

Love（♥）是一门口袋大小的 **Prolog 风格逻辑编程语言**，用 [MoonBit](https://www.moonbitlang.com)
从零实现。它的架构参考了 `reference/` 目录中的经典 Prolog 实现：

- **Trealla Prolog**（C）：WAM 风格堆单元 + trail 回溯，引擎设计的主要参考；
- **SWI-Prolog**（C）：内置谓词集、运算符优先级表、`findall/3` 等语义参照；
- **Scryer Prolog**（Rust）：项表示与干净的错误处理参考；
- **Mercury**（逻辑+函数式）：语言设计文档风格参考。

Love 的目标不是复刻 ISO Prolog 的全部，而是用一套**小而完整**的核心（项、合一、SLD 求解、
回溯、cut、内置谓词、动态数据库、REPL）演示逻辑编程语言的完整实现路径。

完整设计文档见 [DESIGN.md](DESIGN.md)。

## 快速上手

### 构建与运行

```bash
# 编译并运行（模块默认 native 目标，直接运行即可）
moon run cmd/main

# 加载程序文件进入 REPL
moon run cmd/main -- examples/family.lv

# 批处理：运行单个查询并打印全部解
moon run cmd/main -- examples/family.lv "?- father(F, C)."

# 运行测试
moon test
```

### REPL 示例

```
Love> father(F, C).
F = tom, C = bob
;
F = tom, C = lisa
;
F = bob, C = ann
.
Love> X is 1 + 2 * 3.
X = 7
Love> append([1, 2], [3], L).
L = [1, 2, 3]
Love> findall(X, member(X, [a, b, c]), L).
L = [a, b, c]
Love> halt.
```

输入 `;`（分号）获取下一个解，`.` 或其他输入停止枚举；`halt.` 退出 REPL。

## 语言速览

### 事实、规则与查询

```prolog
% 事实
likes(alice, bob).
likes(bob, carol).

% 规则：Head :- Body.
happy(X) :- likes(X, bob).

% 查询（REPL 中直接输入）
?- happy(X).
X = alice
```

### 项

- 变量：`X`、`Name`、`_`（匿名，每次出现都是新变量）
- 原子：`alice`、`'hello world'`
- 整数 / 浮点数：`42`、`-7`、`3.14`、`1e-3`
- 字符串：`"hello"`（字符串项）
- 复合项：`likes(alice, bob)`
- 列表：`[]`、`[a, b, c]`、`[H | T]`
- 剪切：`!`

### 运算符

Love 内置与 ISO/SWI 兼容的运算符优先级表：`:-`(1200) `;`(1100) `->`(1050) `,`(1000)
`\+`(900) `=` `\=` `==` `\==` `is` `=:=` `=\=` `<` `=<` `>` `>=` `=..` `@<` 等(700)
`+` `-`(500) `*` `/` `//` `mod` `rem` `div`(400) `^`(200) 以及前缀 `-` `+` `\`(200)。

## 内置谓词

| 类别 | 谓词 |
| --- | --- |
| 控制流 | `true/0` `fail/0` `!/0` `call/1` `,/2` `;/2` `->/2,3` `\+/1` `once/1` `repeat/0` |
| 合一与项 | `=/2` `\=/2` `==/2` `\==/2` `unify_with_occurs_check/2` `var/1` `nonvar/1` `atom/1` `number/1` `integer/1` `float/1` `string/1` `atomic/1` `compound/1` `callable/1` `ground/1` `functor/3` `arg/3` `=../2` |
| 原子操作 | `atom_length/2` `atom_concat/3` `sub_atom/5` `compare/3` `@</2` `@=</2` `@>/2` `@>=/2` |
| 列表 | `member/2` `append/3` `length/2` `reverse/2` `sort/2` `msort/2` `sum_list/2` `maplist/2` `nth0/3` `nth1/3` |
| 算术 | `is/2` `=:=/2` `=\=/2` `</2` `=</2` `>/2` `>=/2` `between/3` `plus/3`；可求值函子：`+ - * / // rem mod div abs max min sign sqrt exp log sin cos tan floor ceiling round truncate float integer ^` |
| 动态库 | `assertz/1` `asserta/1` `retract/1` `clause/2` `listing/0` |
| 收集 | `findall/3` |
| I/O | `write/1` `writeln/1` `nl/0` |

## 示例

### 递归与列表

```prolog
% 斐波那契（examples/fib.lv）
fib(0, 0).
fib(1, 1).
fib(N, F) :-
    N > 1,
    N1 is N - 1,
    N2 is N - 2,
    fib(N1, F1),
    fib(N2, F2),
    F is F1 + F2.
```

```prolog
?- fib(10, F).
F = 55
```

### 回溯与 cut

```prolog
max(X, Y, M) :- (X > Y -> M = X ; M = Y).
```

### 动态数据库

```prolog
?- assertz(cat(tom)), assertz(cat(pat)), cat(X).
X = tom
;
X = pat
```

## 实现架构

```
love.mbt       公开 API 门面（parse_program / solve / REPL 服务）
syntax.mbt     LoveTerm、Clause、Program 等类型（含内置库子句）
lexer.mbt      词法分析（token 流）
parser.mbt     Pratt 递归下降解析器（运算符优先级表）
unify.mbt      合一 + trail + occurs check
engine.mbt     SLD 引擎（目标栈 + choice point 栈 + cut barrier）
builtins.mbt   内置谓词分发
arith.mbt      算术表达式求值
pretty.mbt     项打印（运算符、列表、引号规则）
cmd/main        CLI：加载文件 + 查询 + REPL
```

求解器采用**惰性迭代器**：每次 `next()` 只推进到下一个解。回溯通过
**trail + choice point（含目标栈快照）** 实现，cut 通过帧屏障截断 choice point 栈实现。

## 与 ISO Prolog 的已知差异（v0.1）

1. 字符串 `"..."` 是字符串项，不是字符码列表；
2. 合一**默认带 occurs check**（`X = f(X)` 失败），另提供 `unify_with_occurs_check/2`；
3. 算术错误使目标失败而非抛出异常；
4. 无 `catch/3`、`throw/1`、DCG、模块系统、自定义运算符；
5. `bagof/3`、`setof/3` 未实现（`findall/3` 已实现）；
6. `atom_concat/3` 在两个变量加一个原子的组合时不枚举所有切分。

## 路线图

- [x] v0.1：解析器、合一、SLD 引擎、cut、内置谓词、算术、动态库、REPL
- [ ] v0.2：`catch/throw`、`bagof/setof`、DCG、`read/1`、自定义运算符
- [ ] v0.3：表驱动（tabling）、约束（CLP）、模块系统
