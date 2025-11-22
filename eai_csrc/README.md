# DSA 自定义指令加速器驱动

## 概述

本驱动提供了对自定义矩阵乘法加速器指令的C语言接口封装，支持：
- CSR寄存器访问（csrrd/csrwr）
- 矩阵乘法指令（mat_mult_t）
- Per-tensor和per-channel量化
- 灵活的数据类型配置（s4/s8/s16/s32/s64）

## 文件说明

- `dsa_accel.h` - 驱动头文件，定义所有接口
- `dsa_accel.c` - 驱动实现文件

## 使用示例

### 1. 基本矩阵乘法（Per-Tensor量化）

```c
#include "dsa_accel.h"

int8_t A[128 * 256];  // M=128, K=256
int8_t B[256 * 64];   // K=256, N=64
int8_t C[128 * 64];   // M=128, N=64
int32_t bias[64];     // N=64

dsa_matmul_config_t config;
dsa_matmul_config_init(&config);

config.lhs_ptr = A;
config.rhs_ptr = B;
config.dst_ptr = C;
config.bias_ptr = bias;

config.M = 128;
config.K = 256;
config.N = 64;
config.K_aligned = 256;

config.lhs_offset = 128;  // 零点偏移
config.dst_mult = 1234567;
config.dst_shift = 10;

uint32_t status = dsa_matmul_execute(&config);
if (status != DSA_SUCCESS) {
    // 错误处理
}
```

### 2. Per-Channel量化

```c
int32_t mult_per_ch[64];   // 每通道mult
int32_t shift_per_ch[64];  // 每通道shift

dsa_matmul_config_init(&config);
// ...existing code...

config.quant_mode = DSA_QUANT_PER_CHANNEL;
config.dst_mult_ptr = mult_per_ch;
config.dst_shift_ptr = shift_per_ch;

uint32_t status = dsa_matmul_execute(&config);
```

### 3. 底层CSR直接访问

```c
// 写入CSR
dsa_csrwr(CSR_MULT_LHS_PTR, (uint32_t)A);

// 读取CSR
uint32_t value = dsa_csrrd(CSR_MULT_LHS_ROWS);

// 直接执行指令
uint32_t cfg = CFG_OUT_W_S8 | CFG_A_W_S8 | CFG_B_W_S8 | CFG_PER_TENSOR;
uint32_t status = dsa_mat_mult_t((uint32_t)C, cfg);
```

## 返回状态码

- `DSA_SUCCESS (0x00000000)` - 执行成功
- `DSA_ERR_NULL_PTR (0x00000002)` - 必需指针为空
- `DSA_ERR_INVALID_DIM (0x00000003)` - 尺寸不满足对齐要求

## 编译说明

```bash
riscv32-unknown-elf-gcc -c dsa_accel.c -o dsa_accel.o
```

## 注意事项

1. 所有指针必须是有效的物理地址
2. K_aligned必须≥K，且满足硬件对齐要求
3. Per-channel模式下，mult/shift数组长度必须等于N
4. 激活范围需根据输出数据类型合理设置
5. 步进值为0时，驱动会自动计算默认步进