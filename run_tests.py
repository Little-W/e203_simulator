import subprocess
import os
import shutil
import time
import signal
import sys
import select  # 新增导入

# 配置参数
NUM_ITERATIONS = 500  # 循环次数，可调整
LOG_DIR = "/home/etc/FPGA/e203_simulator/test_logs"
EXCEPTION_DIR = "/home/etc/FPGA/e203_simulator/exception_cases"
TIMEOUT_SECONDS = 300  # 5分钟超时

os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(EXCEPTION_DIR, exist_ok=True)

def run_iteration(iteration_id):
    print(f"开始第 {iteration_id} 轮测试...")
    
    # 调用 generate_test_case.py
    try:
        subprocess.run([sys.executable, "generate_test_case.py"], check=True, cwd="/home/etc/FPGA/e203_simulator")
    except subprocess.CalledProcessError as e:
        print(f"生成测试用例失败: {e}")
        return "exception", None
    
    # 运行 make sim，实时捕获输出
    log_path = os.path.join(LOG_DIR, f"log_{iteration_id}.txt")
    with open(log_path, 'w', encoding='utf-8') as log_file:
        process = subprocess.Popen(["make", "sim"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd="/home/etc/FPGA/e203_simulator", text=True, encoding='utf-8')
        
        last_output_time = time.time()
        finished = False
        while True:
            # 非阻塞等待输出，最多1秒
            ready, _, _ = select.select([process.stdout], [], [], 1.0)
            if ready:
                line = process.stdout.readline()
                if not line:
                    break
                log_file.write(line)
                log_file.flush()  # 确保实时写入
                last_output_time = time.time()  # 更新最后输出时间
                if "Test Finished." in line:
                    finished = True
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                    break
            else:
                # 没有输出，检查超时
                if time.time() - last_output_time > TIMEOUT_SECONDS:
                    print(f"第 {iteration_id} 轮 5分钟无输出，终止进程。")
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                    # 保存异常用例
                    shutil.copy("/home/etc/FPGA/e203_simulator/eai_csrc/test_case.c", os.path.join(EXCEPTION_DIR, f"exception_{iteration_id}.c"))
                    return "exception", None
        
        # 如果没有找到 "Test Finished."，也标记为异常
        if not finished:
            return "exception", None
    
    # 读取完整 log 内容用于结果检查
    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 检查结果
    if "All tests passed!" in content:
        result = "pass"
    elif "tests failed" in content:
        result = "fail"
    else:
        result = "unknown"
    
    return result, content

def main():
    pass_count = 0
    total_count = 0
    summary_log = os.path.join(LOG_DIR, "summary.txt")
    
    with open(summary_log, 'w') as summary:
        for i in range(1, NUM_ITERATIONS + 1):
            result, content = run_iteration(i)
            total_count += 1
            if result == "pass":
                pass_count += 1
            elif result == "fail":
                pass_count += 0  # 不增加
            elif result == "exception":
                pass_count += 0
            
            accuracy = (pass_count / total_count) * 100 if total_count > 0 else 0
            summary.write(f"第 {i} 轮: {result}, 当前准确率: {accuracy:.2f}%\n")
            print(f"第 {i} 轮完成: {result}, 准确率: {accuracy:.2f}%")
        
        summary.write(f"\n最终总结: 总轮数 {total_count}, 通过 {pass_count}, 准确率 {accuracy:.2f}%\n")
        print(f"测试完成。最终准确率: {accuracy:.2f}%")

if __name__ == "__main__":
    main()
