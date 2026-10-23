#ifndef V_FINAL_PATH_WINDOWS_H
#define V_FINAL_PATH_WINDOWS_H

#ifdef __TINYC__

#ifndef __stdcall
#define __stdcall
#endif

#ifdef __cplusplus
extern "C" {
#endif

extern unsigned long __stdcall GetFinalPathNameByHandleW(void* hFile,
	unsigned short* lpFilePath, unsigned long nSize, unsigned long dwFlags);

#ifdef __cplusplus
}
#endif

#endif

#endif
