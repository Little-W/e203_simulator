#ifndef DSA_ACCEL_H
#define DSA_ACCEL_H

#include <stdint.h>
#include <stddef.h>

/* ========== 自定义指令编码 ========== */
#define CUSTOM_1_OPCODE 0x0B  // CUSTOM_1
#define CUSTOM_3_OPCODE 0x7B  // CUSTOM_3

/* CSR 访问 funct3 */
#define FUNCT3_CSRWR 0x2  // 010
#define FUNCT3_CSRRD 0x4  // 100

/* 矩阵乘法指令 */
#define FUNCT3_NICE  0x7  // 111
#define FUNCT7_MAT_MULT_T 0x01

/* ========== CSR 寄存器地址 ========== */
/* 指针类 */
#define CSR_MULT_LHS_PTR    0x7C0
#define CSR_MULT_RHS_PTR    0x7C1
#define CSR_MULT_DST_PTR    0x7C2
#define CSR_MULT_BIAS_PTR   0x7C3

/* 尺寸/步进类 */
#define CSR_MULT_LHS_ROWS        0x7C4  // K (A 的行数)
#define CSR_MULT_RHS_COLS        0x7C5  // N (B 的行数/内积长度)
#define CSR_MULT_RHS_ROWS        0x7C6  // M (B 的列数/输出通道数)
#define CSR_MULT_DST_ROW_STRIDE  0x7C7  // C 行步长
#define CSR_MULT_LHS_ROW_STRIDE  0x7C8  // A 行步长
#define CSR_MULT_RHS_COL_STRIDE  0x7C9  // B 列步长

/* 量化/激活类 */
#define CSR_MULT_LHS_OFFSET 0x7CA  // A 零点偏移
#define CSR_MULT_RHS_OFFSET 0x7CB  // B 零点偏移
#define CSR_MULT_DST_OFFSET 0x7CC  // 输出零点
#define CSR_MULT_DST_MULT   0x7CD  // per-tensor mult 或 per-channel mult 指针
#define CSR_MULT_DST_SHIFT  0x7CE  // per-tensor shift 或 per-channel shift 指针
#define CSR_MULT_ACT_MIN    0x7CF  // 激活下限
#define CSR_MULT_ACT_MAX    0x7D0  // 激活上限

/* ========== 配置字位域定义 ========== */
/* OUT_W 输出位宽 [2:0] */
#define CFG_OUT_W_S4   0x0
#define CFG_OUT_W_S8   0x1
#define CFG_OUT_W_S16  0x2
#define CFG_OUT_W_S32  0x3
#define CFG_OUT_W_S64  0x4

/* BIAS_W bias位宽 [4:3] */
#define CFG_BIAS_W_S8  (0x0 << 3)
#define CFG_BIAS_W_S16 (0x1 << 3)
#define CFG_BIAS_W_S32 (0x2 << 3)
#define CFG_BIAS_W_S64 (0x3 << 3)

/* B_W 右乘数位宽 [6:5] */
#define CFG_B_W_S4  (0x0 << 5)
#define CFG_B_W_S8  (0x1 << 5)
#define CFG_B_W_S16 (0x2 << 5)

/* A_W 左乘数位宽 [8:7] */
#define CFG_A_W_S4  (0x0 << 7)
#define CFG_A_W_S8  (0x1 << 7)
#define CFG_A_W_S16 (0x2 << 7)

/* PER_CH 量化模式 [9] */
#define CFG_PER_TENSOR (0x0 << 9)
#define CFG_PER_CHANNEL (0x1 << 9)

/* ========== 返回状态码 ========== */
#define DSA_SUCCESS          0x00000000
#define DSA_ERR_NULL_PTR     0x00000002  // 必需指针为空
#define DSA_ERR_INVALID_DIM  0x00000003  // 尺寸不满足对齐要求

/* ========== 数据类型枚举 ========== */
typedef enum {
    DSA_DTYPE_S4 = 0,
    DSA_DTYPE_S8,
    DSA_DTYPE_S16,
    DSA_DTYPE_S32,
    DSA_DTYPE_S64
} dsa_dtype_t;

typedef enum {
    DSA_QUANT_PER_TENSOR = 0,
    DSA_QUANT_PER_CHANNEL = 1
} dsa_quant_mode_t;

/* ========== 矩阵乘法配置结构 ========== */
typedef struct {
    /* 数据指针 */
    const void *lhs_ptr;      // A矩阵(左乘数)基址
    const void *rhs_ptr;      // B矩阵(右乘数)基址
    void *dst_ptr;            // C矩阵(输出)基址
    const int32_t *bias_ptr;  // Bias数组(可为NULL)
    
    /* 矩阵尺寸 */
    uint32_t K;  // A的行数 (MULT_LHS_ROWS)
    uint32_t N;  // B的行数/内积长度 (MULT_RHS_COLS)
    uint32_t M;  // B的列数/输出通道数 (MULT_RHS_ROWS)
    
    /* 行步进(字节，0=自动推导) */
    uint32_t lhs_row_stride;   // A行步距(MULT_LHS_COLS_OFFSET)
    uint32_t rhs_row_stride;   // B行步距(MULT_RHS_ROW_STRIDE)
    uint32_t dst_row_stride;   // 输出行步距(MULT_ROW_ADDR_OFFSET)
    
    /* 数据类型 */
    dsa_dtype_t lhs_dtype;   // A的数据类型
    dsa_dtype_t rhs_dtype;   // B的数据类型(固定s8)
    dsa_dtype_t bias_dtype;  // Bias数据类型
    dsa_dtype_t out_dtype;   // 输出数据类型(固定s8)
    
    /* 量化参数 */
    dsa_quant_mode_t quant_mode;  // 量化模式
    int32_t lhs_offset;           // A的零点偏移
    int32_t rhs_offset;           // B的零点偏移(通常为0)
    int32_t dst_offset;           // 输出零点
    
    /* Per-tensor量化参数
     * 与 CMSIS-NN requant 公式一致:
     *   output = (acc * dst_mult + (1 << (dst_shift - 1))) >> dst_shift
     */
    int32_t dst_mult;             // 标量mult
    int32_t dst_shift;            // 标量shift
    
    /* Per-channel量化参数(指针) */
    const int32_t *dst_mult_ptr;  // mult数组(长度M)
    const int32_t *dst_shift_ptr; // shift数组(长度M)
    
    /* 激活限制 */
    int32_t act_min;
    int32_t act_max;
} dsa_matmul_config_t;

/* ========== 底层CSR访问宏 ========== */

/**
 * CSR写入（立即数 csr）
 * @param csr CSR地址（编译期常量）
 * @param val 写入值
 */
#define DSA_CSRWR(csr, val) \
  __asm__ volatile ( \
    ".insn i 0x7B, 0x2, x0, %0, %1\n" /* csrwr rs1, imm12 */ \
    :: "r"(val), "i"(csr) \
    : "memory")

/**
 * CSR读取（立即数 csr）
 * @param csr CSR地址（编译期常量）
 * @param out_var 输出变量
 */
#define DSA_CSRRD(csr, out_var) \
  __asm__ volatile ( \
    ".insn i 0x7B, 0x4, %0, x0, %1\n" /* csrrd rd, imm12 */ \
    : "=r"(out_var) \
    : "i"(csr) \
    : "memory")

/* ========== 执行矩阵乘法指令宏 ========== */

/**
 * 执行矩阵乘法指令
 * @param dst_addr 输出起始地址
 * @param cfg 配置字
 * @param out_var 输出变量（状态码）
 */
#define DSA_MAT_MULT_T(dst_addr, cfg, out_var) \
  __asm__ volatile ( \
    ".insn r 0x2B, 0x7, 0x01, %0, %1, %2\n" /* mat_mult_t rd, rs1, rs2 */ \
    : "=r"(out_var) \
    : "r"(dst_addr), "r"(cfg) \
    : "memory")

/* ========== 高层API ========== */

/**
 * 配置并执行矩阵乘法
 * @param config 矩阵乘法配置结构
 * @return 状态码(0=成功)
 */
uint32_t dsa_matmul_execute(const dsa_matmul_config_t *config);

/**
 * 构建配置字
 * @param config 矩阵乘法配置结构
 * @return 配置字
 */
uint32_t dsa_build_cfg_word(const dsa_matmul_config_t *config);

/**
 * 初始化配置结构为默认值
 * @param config 待初始化的配置结构
 */
void dsa_matmul_config_init(dsa_matmul_config_t *config);

#endif /* DSA_ACCEL_H */
