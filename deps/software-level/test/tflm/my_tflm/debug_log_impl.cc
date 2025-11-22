#include <cstdio>
#include <cstdarg>

extern "C" {
  void MicroPrintf(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    fflush(stdout);
  }
  
  void DebugLog(const char* s) {
    printf("%s", s);
    fflush(stdout);
  }
}