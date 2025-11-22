#ifndef TEST_CASE_H
#define TEST_CASE_H

#include <stdint.h>
#include "dsa_accel.h"

extern int8_t lhs_data[475];
extern int8_t rhs_data[475];
extern int32_t bias_data[25];
extern int8_t expected_dst_data[625];
extern int8_t dst_data[625];
extern dsa_matmul_config_t test_config;

#endif // TEST_CASE_H
