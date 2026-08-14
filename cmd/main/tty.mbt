///|
/// 终端原始模式 FFI（native 目标）。
/// 单字符按键读取（参考 Scryer Prolog 的 get_single_char/1）：无需回车。

///|
extern "c" fn love_tty_isatty() -> Int = "love_tty_isatty"

///|
extern "c" fn love_tty_raw_on() -> Int = "love_tty_raw_on"

///|
extern "c" fn love_tty_raw_off() -> Int = "love_tty_raw_off"

///|
extern "c" fn love_tty_get_char() -> Int = "love_tty_get_char"

///|
/// stdin 是否为交互终端（管道/重定向时为 false）。
fn stdin_is_tty() -> Bool {
  love_tty_isatty() != 0
}

///|
/// 读取一个按键（原始模式，无需回车）；EOF/错误返回 None。
fn read_tty_char() -> Char? {
  if love_tty_raw_on() != 0 {
    return None
  }
  let c = love_tty_get_char()
  let _ = love_tty_raw_off()
  if c < 0 {
    None
  } else {
    c.to_char()
  }
}
