#include "dsa_accel.h"
#include "test_case.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

/* ========== 全局测试计数器 ========== */
static int test_failed = 0;

/* ========== 使用高层 API 测试 ========== */
void test_high_level_api(void) {
    printf("\n========================================\n");
    printf("高层 API 测试 (使用 Python 生成的用例)\n");
    printf("========================================\n");

    /* 使用 Python 生成的全局配置结构和全局输出缓冲区：
       K/N/M、dst_mult/dst_shift、矩阵内容均为随机 */
    dsa_matmul_config_t config = test_config;

    /* 根据 Python 生成的尺寸清零 dst_data */
    uint32_t total = config.K * config.M;
    memset(dst_data, 0, total * sizeof(int8_t));

    /* 确保 config.dst_ptr 指向全局 dst_data */
    config.dst_ptr = dst_data;

    printf("%s 从 test_case.c 读取配置\n", TEST_INFO);
    printf("  矩阵尺寸: K=%u, N=%u, M=%u\n", config.K, config.N, config.M);
    printf("  量化参数: dst_mult=%d, dst_shift=%d\n",
           config.dst_mult, config.dst_shift);

    /* 执行矩阵乘法 */
    printf("\n%s 调用 dsa_matmul_execute()...\n", TEST_INFO);
    uint32_t status = dsa_matmul_execute(&config);

    printf("%s API 调用完成\n", TEST_INFO);
    printf("  返回状态码: 0x%08X\n", status);

    if (status == DSA_SUCCESS) {
        printf("%s 高层 API 执行成功\n", TEST_PASS);

        /* 使用 expected_dst_data 验证结果 */
        for (uint32_t idx = 0; idx < total; idx++) {
            int8_t actual = dst_data[idx];
            int8_t expected = expected_dst_data[idx];
            ASSERT_EQ(actual, expected, "DST 结果验证");
        }
    } else {
        printf("%s 高层 API 执行失败 (状态码: 0x%08X)\n", TEST_FAIL, status);
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
    printf("测试结果摘要\n");
    printf("========================================\n");

    if (test_failed == 0) {
        printf("%s 所有测试通过!\n", TEST_PASS);
        return 0;
    } else {
        printf("%s %d 个测试失败\n", TEST_FAIL, test_failed);
        return 1;
    }
}
