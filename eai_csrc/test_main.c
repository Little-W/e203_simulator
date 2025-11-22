#include "dsa_accel.h"
#include "test_case.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h> // 新增：保证 uint32_t/int8_t 格式化安全

/* ========== 测试辅助宏 ========== */
#define TEST_PASS "\033[32m[PASS]\033[0m"
#define TEST_FAIL "\033[31m[FAIL]\033[0m"
#define TEST_INFO "\033[34m[INFO]\033[0m"

#define ASSERT_EQ(actual, expected, msg) \
    do { \
        if ((actual) == (expected)) { \
            printf("%s %s: 0x%08X == 0x%08X\n", TEST_PASS, msg, (uint32_t)(actual), (uint32_t)(expected)); \
        } else { \
            printf("%s %s: 0x%08X != 0x%08X\n", TEST_FAIL, msg, (uint32_t)(actual), (uint32_t)(expected)); \
            test_failed++; \
        } \
    } while(0)

/* 新增：带坐标输出的断言宏
   idx: 当前线性索引
   M:   每行/每列长度（这里 dst 矩阵列数为 M）
*/
#define ASSERT_EQ_COORD(actual, expected, idx, M, msg) \
    do { \
        uint32_t _idx = (uint32_t)(idx); \
        uint32_t _M = (uint32_t)(M); \
        uint32_t _r = _M ? (_idx / _M) : 0; \
        uint32_t _c = _M ? (_idx % _M) : _idx; \
        if ((actual) == (expected)) { \
            printf("%s %s @(%u,%u): 0x%02X == 0x%02X\n", TEST_PASS, msg, _r, _c, (uint8_t)(actual), (uint8_t)(expected)); \
        } else { \
            printf("%s %s @(%u,%u): 0x%02X != 0x%02X\n", TEST_FAIL, msg, _r, _c, (uint8_t)(actual), (uint8_t)(expected)); \
            test_failed++; \
        } \
    } while(0)

/* ========== 全局测试计数器 ========== */
static int test_failed = 0;

/* ========== 使用高层 API 测试 ========== */
void test_high_level_api(void) {
    printf("\n========================================\n");
    printf("High-level API test (using Python-generated test cases)\n");
    printf("========================================\n");

    /* 使用 Python 生成的全局配置结构和全局输出缓冲区：
       K/N/M、dst_mult/dst_shift、矩阵内容均为随机 */
    dsa_matmul_config_t config = test_config;

    /* 根据 Python 生成的尺寸清零 dst_data */
    uint32_t total = config.K * config.M;
    memset(dst_data, 0, total * sizeof(int8_t));

    /* 确保 config.dst_ptr 指向全局 dst_data */
    config.dst_ptr = dst_data;

    printf("%s Reading configuration from test_case.c\n", TEST_INFO);
    printf("  Matrix dimensions: K=%u, N=%u, M=%u\n", config.K, config.N, config.M);
    printf("  Quantization parameters: dst_mult=%d, dst_shift=%d\n",
           config.dst_mult, config.dst_shift);

    /* 执行矩阵乘法 */
    printf("\n%s Calling dsa_matmul_execute()...\n", TEST_INFO);
    uint32_t status = dsa_matmul_execute(&config);

    printf("%s API call completed\n", TEST_INFO);
    printf("  Return status code: 0x%08X\n", status);

    if (status == DSA_SUCCESS) {
        printf("%s High-level API execution successful\n", TEST_PASS);

        /* 使用 expected_dst_data 验证结果 */
        for (uint32_t idx = 0; idx < total; idx++) {
            int8_t actual = dst_data[idx];
            int8_t expected = expected_dst_data[idx];
            /* 将原来的 ASSERT_EQ 改为 ASSERT_EQ_COORD，输出 (row,col) 坐标 */
            ASSERT_EQ_COORD(actual, expected, idx, config.M, "DST result verification");
        }
    } else {
        printf("%s High-level API execution failed (status code: 0x%08X)\n", TEST_FAIL, status);
        test_failed++;
    }
}

/* ========== 主函数 ========== */
int main(void) {
    // printf("\n");
    // printf("========================================\n");
    // printf("DSA 加速器驱动测试程序\n");
    // printf("========================================\n");

    test_failed = 0;

    /* 运行所有测试 */
    test_high_level_api();

    /* 输出测试结果摘要 */
    printf("\n========================================\n");
    printf("Test result summary\n");
    printf("========================================\n");

    if (test_failed == 0) {
        printf("%s All tests passed!\n", TEST_PASS);
        printf("Test Finished.\n");
        return 0;
    } else {
        printf("%s %d tests failed\n", TEST_FAIL, test_failed);
        printf("Test Finished.\n");
        return 1;
    }
    
}
