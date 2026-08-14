///|
/// cmd/main 白盒测试：逐字符查询读取核心（read_query_chars_core）的按键处理逻辑。
/// 覆盖：CRLF 回车、遗留 '\n' 吞掉、多行续行、Backspace、Ctrl-D、方向键编辑与历史。

///|
/// 便捷助手：从字节数组模拟按键流。
fn keys_of(bytes : Array[Byte]) -> () -> Int {
  fn() { if bytes.is_empty() { -1 } else { bytes.remove(0).to_int() } }
}

///|
/// 运行核心并收集 emit 输出。
async fn run_core(
  bytes : Array[Byte],
  history : Array[String],
) -> (String?, String) {
  let out = StringBuilder()
  let r = read_query_chars_core(
    keys_of(bytes),
    bs => out.write_string(@utf8.decode_lossy(bs)),
    history,
  )
  (r, out.to_string())
}

///|
async test "chars: CRLF 回车提交一次，无遗留" {
  // 输入："X = 42." + \r + \n（CRLF 回车）
  let (r, _) = run_core([b'X', b' ', b'=', b' ', b'4', b'2', b'.', 13, 10], [])
  assert_eq(r, Some("X = 42."))
}

///|
async test "chars: 遗留的 \n 被吞掉，不触发空行续行" {
  // 模拟上一次 CRLF 遗留的 '\n'，随后是新查询
  let (r, _) = run_core([10, b'Y', b' ', b'=', b' ', b'1', b'.', 13], [])
  assert_eq(r, Some("Y = 1."))
}

///|
async test "chars: 多行续行 + CRLF" {
  // "member(X," \r \n "[a, b])." \r
  let (r, _) = run_core(
    [
      b'm', b'e', b'm', b'b', b'e', b'r', b'(', b'X', b',', 13, 10, b'[', b'a', b',',
      b' ', b'b', b']', b')', b'.', 13,
    ],
    [],
  )
  assert_eq(r, Some("member(X,[a, b])."))
}

///|
async test "chars: Backspace 删除字符" {
  // "ab" + Backspace + "c." + \r → "ac."
  let (r, _) = run_core([b'a', b'b', 8, b'c', b'.', 13], [])
  assert_eq(r, Some("ac."))
}

///|
async test "chars: 未以点结尾则续行，补点后提交" {
  // "X = 1" \r "." \r → "X = 1."
  let (r, _) = run_core([b'X', b' ', b'=', b' ', b'1', 13, b'.', 13], [])
  assert_eq(r, Some("X = 1."))
}

///|
async test "chars: Ctrl-D 空缓冲退出，非空忽略" {
  // 空缓冲 Ctrl-D → None（退出）
  let (r1, _) = run_core([4], [])
  assert_eq(r1, None)
  // 非空时 Ctrl-D 忽略，随后回车提交
  let (r2, _) = run_core([b'X', 4, b'.', 13], [])
  assert_eq(r2, Some("X."))
}

///|
async test "chars: Ctrl-C 取消当前行" {
  // "bad" + Ctrl-C + "ok." + \r → "ok."
  let (r, _) = run_core([b'b', b'a', b'd', 3, b'o', b'k', b'.', 13], [])
  assert_eq(r, Some("ok."))
}

///|
async test "chars: 未回车直接 EOF 提交已有内容" {
  let (r, _) = run_core([b'q', b'.'], [])
  assert_eq(r, Some("q."))
}

///|
async test "chars: 左箭头移动光标后插入" {
  // "abc" + 左箭头（光标在 b 与 c 之间）+ "X" → "abXc"；再 "." → "abX.c"（光标在 X 与 c 之间）
  let (r, _) = run_core([b'a', b'b', b'c', 27, b'[', b'D', b'X', b'.', 13], [])
  assert_eq(r, Some("abX.c"))
}

///|
async test "chars: 右箭头移动光标" {
  // "ab" 左左（光标 0）右（光标 1）"c" → "acb"；"." → "ac.b"
  let (r, _) = run_core(
    [b'a', b'b', 27, b'[', b'D', 27, b'[', b'D', 27, b'[', b'C', b'c', b'.', 13],
    [],
  )
  assert_eq(r, Some("ac.b"))
}

///|
async test "chars: Home 与 End" {
  // "abc" + Home（光标 0）+ "X" → "Xabc"；End（光标 4）+ "." → "Xabc."
  let (r, _) = run_core(
    [b'a', b'b', b'c', 27, b'[', b'H', b'X', 27, b'[', b'F', b'.', 13],
    [],
  )
  assert_eq(r, Some("Xabc."))
}

///|
async test "chars: Delete 删除光标处字符" {
  // "abc" + 左左（光标 1，在 b 前）+ Delete（删 b）→ "ac"（光标仍在 a 与 c 之间）；"." → "a.c"
  let (r, _) = run_core(
    [
      b'a', b'b', b'c', 27, b'[', b'D', 27, b'[', b'D', 27, b'[', b'3', b'~', b'.',
      13,
    ],
    [],
  )
  assert_eq(r, Some("a.c"))
}

///|
async test "chars: 上箭头召回历史，下箭头回到新输入" {
  // 先提交一条 "p(1)."，第二条按上箭头召回再提交
  let history : Array[String] = []
  let (r1, _) = run_core([b'p', b'(', b'1', b')', b'.', 13], history)
  assert_eq(r1, Some("p(1)."))
  // 上箭头召回 "p(1)."，回车提交
  let (r2, _) = run_core([27, b'[', b'A', 13], history)
  assert_eq(r2, Some("p(1)."))
  // 上箭头再下箭头回到新输入，输入新查询
  let (r3, _) = run_core(
    [27, b'[', b'A', 27, b'[', b'B', b'q', b'.', 13],
    history,
  )
  assert_eq(r3, Some("q."))
  // 历史包含两条（重复的 p(1). 不重复入历史）
  assert_eq(history.length(), 2)
}

///|
async test "chars: 多字节 UTF-8 输入与光标移动" {
  // "中"（E4 B8 AD）+ "文"（E6 96 87）+ 左箭头（光标在 中 与 文 之间）+ "a" + "." → "中a.文"
  let (r, _) = run_core(
    [0xE4, 0xB8, 0xAD, 0xE6, 0x96, 0x87, 27, b'[', b'D', b'a', b'.', 13],
    [],
  )
  assert_eq(r, Some("中a.文"))
}
