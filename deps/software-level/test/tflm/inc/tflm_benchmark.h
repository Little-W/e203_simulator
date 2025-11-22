#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/// @brief 调用TFLM基准测试函数
void tflm_benchmark();

// 模型初始化函数
// 返回值: 0表示成功，非0表示失败
extern int ModelInit(void);

// 模型推理函数
// 输入: image_data - 图像数据指针
// 返回: 识别到的字符 (A-Z), 如果推理失败返回 '\0'
extern char ModelInference(const uint8_t* image_data);

extern int keyword_benchmark();

void PrintArray64x64(uint8_t arr[64][64]);
void PrintInferResult(int result);

#ifdef __cplusplus
}
#endif
