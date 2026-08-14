// Love REPL 终端原始模式支持（单字符按键，无需回车）。
// 参考 Scryer Prolog 的 get_single_char/1（raw 模式读单个字符）。
//
// Windows: 用 GetConsoleMode/SetConsoleMode 关闭行缓冲与回显，再 _read 单字符。
// Unix:    用 termios 清除 ICANON/ECHO，再 read 单字符。

#include <stdint.h>
#include <stdio.h>
#include <moonbit.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>

static HANDLE g_console_in = INVALID_HANDLE_VALUE;
static DWORD g_orig_mode = 0;
static int g_raw = 0;

static int love_is_tty(void) {
  return _isatty(_fileno(stdin));
}

#else
#include <termios.h>
#include <unistd.h>

static struct termios g_orig;
static int g_raw = 0;

static int love_is_tty(void) {
  return isatty(STDIN_FILENO);
}
#endif

// stdin 是否为交互终端（管道/重定向时为 0）。
MOONBIT_FFI_EXPORT int32_t love_tty_isatty(void) {
  return love_is_tty() ? 1 : 0;
}

// 进入原始模式：关闭行缓冲与回显。成功返回 0，失败返回 -1。
MOONBIT_FFI_EXPORT int32_t love_tty_raw_on(void) {
  if (!love_is_tty() || g_raw) {
    return g_raw ? 0 : -1;
  }
#ifdef _WIN32
  g_console_in = GetStdHandle(STD_INPUT_HANDLE);
  if (g_console_in == INVALID_HANDLE_VALUE) {
    return -1;
  }
  if (!GetConsoleMode(g_console_in, &g_orig_mode)) {
    return -1;
  }
  DWORD raw_mode = g_orig_mode & ~(DWORD)(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
  if (!SetConsoleMode(g_console_in, raw_mode)) {
    return -1;
  }
  g_raw = 1;
  return 0;
#else
  if (tcgetattr(STDIN_FILENO, &g_orig) != 0) {
    return -1;
  }
  struct termios raw = g_orig;
  raw.c_lflag &= ~(tcflag_t)(ICANON | ECHO);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) {
    return -1;
  }
  g_raw = 1;
  return 0;
#endif
}

// 恢复原始终端模式。
MOONBIT_FFI_EXPORT int32_t love_tty_raw_off(void) {
  if (!g_raw) {
    return 0;
  }
#ifdef _WIN32
  if (!SetConsoleMode(g_console_in, g_orig_mode)) {
    return -1;
  }
#else
  if (tcsetattr(STDIN_FILENO, TCSANOW, &g_orig) != 0) {
    return -1;
  }
#endif
  g_raw = 0;
  return 0;
}

// 读取一个字符（原始模式下无需回车）；EOF/错误返回 -1。
MOONBIT_FFI_EXPORT int32_t love_tty_get_char(void) {
#ifdef _WIN32
  char c = 0;
  int n = _read(_fileno(stdin), &c, 1);
  if (n <= 0) {
    return -1;
  }
  return (int32_t)(unsigned char)c;
#else
  char c = 0;
  ssize_t n = read(STDIN_FILENO, &c, 1);
  if (n <= 0) {
    return -1;
  }
  return (int32_t)(unsigned char)c;
#endif
}
