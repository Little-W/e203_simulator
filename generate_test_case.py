import numpy as np
import os
import random

# 随机生成矩阵尺寸 (1~128)
K = random.randint(16, 32)
N = random.randint(16, 32)
M = random.randint(16, 32)

# 随机生成 lhs (A)、rhs (B) 的 int8 内容
lhs = np.random.randint(-128, 128, size=(K, N), dtype=np.int8)
rhs = np.random.randint(-128, 128, size=(N, M), dtype=np.int8)

# bias 随机或为 0，这里先简单设为 0
bias = np.zeros(M, dtype=np.int32)

# 计算累加结果 (int32)
sum_result = np.dot(lhs.astype(np.int32), rhs.astype(np.int32))  # [K, M]
result = sum_result + bias  # broadcasting

def compute_requant_params(acc: np.ndarray):
    """
    根据累加结果范围，生成 dst_mult 和 dst_shift，使得
      output = (acc * dst_mult + (1 << (shift-1))) >> shift
    落在 int8 范围内且不完全溢出。
    """
    acc_min = int(acc.min())
    acc_max = int(acc.max())
    max_abs = max(abs(acc_min), abs(acc_max))
    if max_abs == 0:
        # 全 0，任意量化都行，返回恒等
        return 1, 0

    # 我们使用右移 (shift >= 0)，不进行小数放大，保证简单可靠
    # 目标：max_abs * mult / 2^shift <= 127 且 mult 尽量大
    # 先枚举适当范围的 shift，选出最大的 mult
    best_mult = 1
    best_shift = 0
    max_shift = 31  # int32 足够
    for s in range(max_shift + 1):
        # mult <= 127 * 2^s / max_abs
        num = 127 * (1 << s)
        mult = num // max_abs  # floor
        if mult < 1:
            continue
        # 记录 mult 最大的组合
        if mult > best_mult:
            best_mult = mult
            best_shift = s

    return int(best_mult), int(best_shift)

def requantize_array(acc: np.ndarray, mult: int, shift: int) -> np.ndarray:
    """
    使用 CMSIS-NN 公式对整个 acc 数组做 requant：
      output = (acc * mult + (1 << (shift-1))) / 2^shift
    其中 / 是算术右移。
    """
    acc_int64 = acc.astype(np.int64)
    prod = acc_int64 * int(mult)
    if shift > 0:
        # 加上舍入项 (1 << (shift-1))
        prod = prod + (1 << (shift - 1))
        prod = prod >> shift
    # shift == 0 时，直接使用 prod
    prod = np.clip(prod, -128, 127)
    return prod.astype(np.int8)

# 根据结果范围计算 dst_mult / dst_shift
dst_mult, dst_shift = compute_requant_params(result)

# 使用同样公式生成预期输出
quantized = requantize_array(result, dst_mult, dst_shift)

# 输出目录：./eai_csrc
out_dir = "/home/etc/FPGA/e203_simulator/eai_csrc"
os.makedirs(out_dir, exist_ok=True)
c_path = os.path.join(out_dir, "test_case.c")
h_path = os.path.join(out_dir, "test_case.h")
debug_path = os.path.join(out_dir, "debug_output.txt")

# 生成调试文件：未经量化的累加结果 (int32)
with open(debug_path, 'w') as f:
    f.write(f"未经量化的矩阵乘法中间结果 (K={K}, N={N}, M={M})\n")
    f.write("格式: int32 矩阵，每行对应输出的一行\n\n")
    for i in range(K):
        row_str = ' '.join(f'{result[i, j]:8d}' for j in range(M))
        f.write(f"行 {i}: {row_str}\n")
    f.write(f"\n量化参数: dst_mult={dst_mult}, dst_shift={dst_shift}\n")

# 生成C文件
with open(c_path, 'w') as f:
    f.write('#include "test_case.h"\n\n')
    # LHS
    f.write('// LHS data (K x N)\n')
    f.write('int8_t lhs_data[{}] = {{\n'.format(K * N))
    for i in range(K * N):
        f.write(f'  {int(lhs.flatten()[i])}')
        if i < K * N - 1:
            f.write(',')
        if (i + 1) % N == 0:
            f.write('\n')
        else:
            f.write(' ')
    f.write('};\n\n')

    # RHS
    f.write('// RHS data (N x M, column-major)\n')
    f.write('int8_t rhs_data[{}] = {{\n'.format(N * M))
    rhs_flat = rhs.flatten(order='F')  # 列展平
    for i in range(N * M):
        f.write(f'  {int(rhs_flat[i])}')
        if i < N * M - 1:
            f.write(',')
        if (i + 1) % N == 0:  # 每列 N 个元素后换行（列优先）
            f.write('\n')
        else:
            f.write(' ')
    f.write('};\n\n')

    # Bias
    f.write('// Bias data (length M)\n')
    f.write('int32_t bias_data[{}] = {{\n'.format(M))
    for i in range(M):
        f.write(f'  {int(bias[i])}')
        if i < M - 1:
            f.write(',')
        f.write('\n' if (i + 1) % M == 0 else ' ')
    f.write('};\n\n')

    # Expected DST
    f.write('// Expected DST data (K x M)\n')
    f.write('int8_t expected_dst_data[{}] = {{\n'.format(K * M))
    for i in range(K * M):
        f.write(f'  {int(quantized.flatten()[i])}')
        if i < K * M - 1:
            f.write(',')
        if (i + 1) % M == 0:
            f.write('\n')
        else:
            f.write(' ')
    f.write('};\n\n')

    # 输出缓冲区（由 Python 固定大小生成）
    f.write('// DST buffer (K x M), used as output buffer\n')
    f.write('int8_t dst_data[{}];\n\n'.format(K * M))

    # Config
    f.write('// Auto-generated matmul config\n')
    f.write('dsa_matmul_config_t test_config = {\n')
    f.write('  .lhs_ptr = lhs_data,\n')
    f.write('  .rhs_ptr = rhs_data,\n')
    f.write('  .dst_ptr = dst_data,\n')
    f.write('  .bias_ptr = bias_data,\n')
    f.write('  .K = %d,\n' % K)
    f.write('  .N = %d,\n' % N)
    f.write('  .M = %d,\n' % M)
    f.write('  .lhs_row_stride = %d,\n' % N)  # 连续行
    f.write('  .rhs_row_stride = %d,\n' % N)  # 连续行
    f.write('  .dst_row_stride = %d,\n' % M)  # 连续行
    # 数据类型
    f.write('  .lhs_dtype = DSA_DTYPE_S8,\n')
    f.write('  .rhs_dtype = DSA_DTYPE_S8,\n')
    f.write('  .bias_dtype = DSA_DTYPE_S32,\n')
    f.write('  .out_dtype = DSA_DTYPE_S8,\n')
    # 量化模式与零点
    f.write('  .quant_mode = DSA_QUANT_PER_TENSOR,\n')
    f.write('  .lhs_offset = 0,\n')
    f.write('  .rhs_offset = 0,\n')
    f.write('  .dst_offset = 0,\n')
    # per-tensor 量化
    f.write('  .dst_mult = %d,\n' % dst_mult)
    f.write('  .dst_shift = %d,\n' % dst_shift)
    # per-channel 量化指针（未使用）
    f.write('  .dst_mult_ptr = NULL,\n')
    f.write('  .dst_shift_ptr = NULL,\n')
    # 激活范围
    f.write('  .act_min = -128,\n')
    f.write('  .act_max = 127,\n')
    f.write('};\n')

# 生成头文件
with open(h_path, 'w') as f:
    f.write('#ifndef TEST_CASE_H\n')
    f.write('#define TEST_CASE_H\n\n')
    f.write('#include <stdint.h>\n')
    f.write('#include "dsa_accel.h"\n\n')
    f.write('extern int8_t lhs_data[%d];\n' % (K * N))
    f.write('extern int8_t rhs_data[%d];\n' % (N * M))
    f.write('extern int32_t bias_data[%d];\n' % M)
    f.write('extern int8_t expected_dst_data[%d];\n' % (K * M))
    f.write('extern int8_t dst_data[%d];\n' % (K * M))
    f.write('extern dsa_matmul_config_t test_config;\n\n')
    f.write('#endif // TEST_CASE_H\n')
