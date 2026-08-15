// Love 库的 stdin 读取 FFI（read/1 用）。
// 从标准输入读取一行（不含换行符），返回 UTF-8 字节；
// EOF/错误返回空字节。Windows 与 Unix 通用。

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

MOONBIT_FFI_EXPORT moonbit_bytes_t amistozy_love_read_line(void) {
  size_t cap = 256;
  size_t len = 0;
  char *buf = (char *)malloc(cap);
  if (!buf) {
    return moonbit_make_bytes(0, 0);
  }
  int c;
  while ((c = fgetc(stdin)) != EOF && c != '\n') {
    if (len + 1 >= cap) {
      cap *= 2;
      char *nb = (char *)realloc(buf, cap);
      if (!nb) {
        free(buf);
        return moonbit_make_bytes(0, 0);
      }
      buf = nb;
    }
    buf[len++] = (char)c;
  }
  if (len == 0 && c == EOF) {
    free(buf);
    return moonbit_make_bytes(0, 0);
  }
  // 去掉行尾 \r（CRLF）
  if (len > 0 && buf[len - 1] == '\r') {
    len--;
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(out, buf, len);
  }
  free(buf);
  return out;
}
