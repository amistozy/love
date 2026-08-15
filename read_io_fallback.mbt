///|
/// 从 stdin 读取一行（wasm/js 等非 native 目标的占位实现）。
/// 非 native 目标不支持交互输入，read/1 返回失败。

///|
fn read_line_stdin() -> String? {
  None
}
