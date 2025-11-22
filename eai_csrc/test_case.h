#ifndef TEST_CASE_H
#define TEST_CASE_H

#include <stdint.h>
#include "dsa_accel.h"

extern int8_t lhs_data[2730];
extern int8_t rhs_data[1435];
extern int32_t bias_data[41];
extern int8_t expected_dst_data[3198];
extern int8_t dst_data[3198];
extern dsa_matmul_config_t test_config;

#endif // TEST_CASE_H
