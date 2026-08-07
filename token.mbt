///|
/// Love 的词法单元（token）。
pub enum Token {
  /// 标识符：变量（大写/`_` 开头）或原子（小写开头），保留原始文本
  Name(String)
  /// 单引号引号原子：`'hello world'`
  Quoted(String)
  /// 整数
  Int(Int)
  /// 符号：`:-` `,` `;` `|` `(` `)` `[` `]` `.` `!` `=` `<` `+` `-` `*` `/` 等
  Symbol(String)
  /// 紧凑左括号（紧跟前一个 token 无空白）：`foo(` 的 `(`。
  /// ISO open_ct——复合项 functor 必须紧跟 `(`，`foo (a)` 是语法错误。
  OpenCT
  /// 输入结束
  Eof
}
