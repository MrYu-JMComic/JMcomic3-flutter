#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void init_ffi(const char* path);
char* invoke_ffi(const char* params);
void free_str_ffi(char* ptr);

#ifdef __cplusplus
}
#endif
