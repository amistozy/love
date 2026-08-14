///|
/// 终端原始模式 FFI（native 目标）。
/// 单字符按键读取（参考 Scryer Prolog 的 get_single_char/1）：无需回车。

///|
extern "c" fn love_tty_isatty() -> Int = "love_tty_isatty"

///|
extern "c" fn love_tty_init() -> Int = "love_tty_init"

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
/// 初始化终端（Windows 启用 VT 处理，ANSI 转义可用）。
fn tty_init() -> Unit {
  let _ = love_tty_init()
}

///|
/// 进入原始模式（保持开启，供逐字符输入会话使用）。
fn tty_begin() -> Bool {
  love_tty_raw_on() == 0
}

///|
/// 退出原始模式。
fn tty_end() -> Unit {
  let _ = love_tty_raw_off()
}

///|
/// 原始模式下读取一个字节（0-255）；EOF/错误返回 -1。
fn tty_read_byte() -> Int {
  love_tty_get_char()
}

///|
/// 读取一个按键（原始模式，无需回车）；EOF/错误返回 None。
fn read_tty_char() -> Char? {
  if !tty_begin() {
    return None
  }
  let c = tty_read_byte()
  tty_end()
  if c < 0 {
    None
  } else {
    c.to_char()
  }
}
