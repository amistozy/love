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
  /// 输入结束
  Eof
}
