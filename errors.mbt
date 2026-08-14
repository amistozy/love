///|
/// Love 语言的错误类型。
pub(all) suberror LoveError {
  /// 词法错误：出错位置（字符偏移）+ 说明
  LexError(pos~ : Int, String)
  /// 语法错误：出错位置（字符偏移）+ 说明
  ParseError(pos~ : Int, String)
} derive(Debug)

///|
pub impl Show for LoveError with fn output(self, logger) {
  match self {
    LoveError::LexError(pos~, msg) =>
      logger.write_string("lex error at \{pos}: \{msg}")
    LoveError::ParseError(pos~, msg) =>
      logger.write_string("parse error at \{pos}: \{msg}")
  }
}
