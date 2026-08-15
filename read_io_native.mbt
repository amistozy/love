///|
/// 从 stdin 读取一行（native 实现，FFI 到 stub.c）。
/// 返回去除行尾换行的字符串；EOF/错误返回 None。

///|
extern "c" fn love_read_line_ffi() -> Bytes = "amistozy_love_read_line"

///|
fn read_line_stdin() -> String? {
  let b = love_read_line_ffi()
  if b.length() == 0 {
    None
  } else {
    Some(@utf8.decode_lossy(b))
  }
}
