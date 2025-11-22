#include "dsa_accel.h"
#include <string.h>

/* ========== 辅助函数 ========== */

/**
 * 获取数据类型的字节大小
 */
static uint32_t get_dtype_size(dsa_dtype_t dtype) {
    switch (dtype) {
        case DSA_DTYPE_S4:  return 1;  // 按字节对齐
        case DSA_DTYPE_S8:  return 1;
        case DSA_DTYPE_S16: return 2;
        case DSA_DTYPE_S32: return 4;
        case DSA_DTYPE_S64: return 8;
        default: return 1;
    }
}

/**
 * 构建配置字
 */
uint32_t dsa_build_cfg_word(const dsa_matmul_config_t *config) {
    uint32_t cfg = 0;
    
    /* OUT_W [2:0] */
    cfg |= (config->out_dtype & 0x7);
    
    /* BIAS_W [4:3] */
    cfg |= ((config->bias_dtype & 0x3) << 3);
    
    /* B_W [6:5] */
    cfg |= ((config->rhs_dtype & 0x3) << 5);
    
    /* A_W [8:7] */
    cfg |= ((config->lhs_dtype & 0x3) << 7);
    
    /* PER_CH [9] */
    cfg |= ((config->quant_mode & 0x1) << 9);
    
    /* [31:10] 保留为0 */
    
    return cfg;
}

/**
 * 初始化配置结构
 */
void dsa_matmul_config_init(dsa_matmul_config_t *config) {
    memset(config, 0, sizeof(dsa_matmul_config_t));
    
    /* 设置默认数据类型 */
    config->lhs_dtype = DSA_DTYPE_S8;
    config->rhs_dtype = DSA_DTYPE_S8;   // B固定s8
    config->bias_dtype = DSA_DTYPE_S32;
    config->out_dtype = DSA_DTYPE_S8;   // 输出固定s8
    
    /* 默认per-tensor量化 */
    config->quant_mode = DSA_QUANT_PER_TENSOR;
    
    /* 默认激活范围(int8) */
    config->act_min = -128;
    config->act_max = 127;
}

/**
 * 配置所有CSR寄存器
 */
static uint32_t configure_csr_registers(const dsa_matmul_config_t *config) {
    /* 检查必需指针 */
    if (!config->lhs_ptr || !config->rhs_ptr || !config->dst_ptr) {
        return DSA_ERR_NULL_PTR;
    }
    
    /* Per-channel模式需要mult/shift数组 */
    if (config->quant_mode == DSA_QUANT_PER_CHANNEL) {
        if (!config->dst_mult_ptr || !config->dst_shift_ptr) {
            return DSA_ERR_NULL_PTR;
        }
    }
    
    /* 配置指针寄存器 */
    DSA_CSRWR(CSR_MULT_LHS_PTR, (uint32_t)(uintptr_t)config->lhs_ptr);
    DSA_CSRWR(CSR_MULT_RHS_PTR, (uint32_t)(uintptr_t)config->rhs_ptr);
    DSA_CSRWR(CSR_MULT_DST_PTR, (uint32_t)(uintptr_t)config->dst_ptr);
    DSA_CSRWR(CSR_MULT_BIAS_PTR, (uint32_t)(uintptr_t)config->bias_ptr);
    
    /* 配置尺寸寄存器 (注意：K/N/M 的语义映射) */
    DSA_CSRWR(CSR_MULT_LHS_ROWS, config->K);  // K: A的行数
    DSA_CSRWR(CSR_MULT_RHS_COLS, config->N);  // N: B的行数/内积长度
    DSA_CSRWR(CSR_MULT_RHS_ROWS, config->M);  // M: B的列数/输出通道数
    
    /* 步进配置 (字节，0表示自动推导) */
    DSA_CSRWR(CSR_MULT_LHS_ROW_STRIDE, config->lhs_row_stride);   // A行步长
    DSA_CSRWR(CSR_MULT_RHS_COL_STRIDE, config->rhs_row_stride);   // B列步长 (原rhs_row_stride，但语义为列)
    DSA_CSRWR(CSR_MULT_DST_ROW_STRIDE, config->dst_row_stride);   // C行步长
    
    /* 量化参数 */
    DSA_CSRWR(CSR_MULT_LHS_OFFSET, config->lhs_offset);  // A零点
    DSA_CSRWR(CSR_MULT_RHS_OFFSET, config->rhs_offset);  // B零点(通常为0)
    DSA_CSRWR(CSR_MULT_DST_OFFSET, config->dst_offset);  // 输出零点
    
    /* Mult/Shift配置（配合硬件侧 CMSIS-NN 风格 requant 实现） */
    if (config->quant_mode == DSA_QUANT_PER_TENSOR) {
        /* Per-tensor: 标量值 */
        DSA_CSRWR(CSR_MULT_DST_MULT, config->dst_mult);
        DSA_CSRWR(CSR_MULT_DST_SHIFT, config->dst_shift);
    } else {
        /* Per-channel: 指针(长度M) */
        DSA_CSRWR(CSR_MULT_DST_MULT, (uint32_t)(uintptr_t)config->dst_mult_ptr);
        DSA_CSRWR(CSR_MULT_DST_SHIFT, (uint32_t)(uintptr_t)config->dst_shift_ptr);
    }
    
    /* 激活限制 */
    DSA_CSRWR(CSR_MULT_ACT_MIN, config->act_min);
    DSA_CSRWR(CSR_MULT_ACT_MAX, config->act_max);
    
    return DSA_SUCCESS;
}

/**
 * 执行矩阵乘法
 */
uint32_t dsa_matmul_execute(const dsa_matmul_config_t *config) {
    uint32_t status;
    
    /* 参数校验 */
    if (!config) {
        return DSA_ERR_NULL_PTR;
    }
    
    /* 配置CSR寄存器 */
    status = configure_csr_registers(config);
    if (status != DSA_SUCCESS) {
        return status;
    }
    
    /* 构建配置字 */
    uint32_t cfg_word = dsa_build_cfg_word(config);
    
    /* 执行指令 */
    DSA_MAT_MULT_T((uint32_t)(uintptr_t)config->dst_ptr, cfg_word, status);
    
    return status;
}
