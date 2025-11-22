#!/bin/bash

# TensorFlow Lite Micro 模型快速集成脚本
# 
# 使用方法:
#   ./quick_start.sh <model_name> <model_file> [test_data_dir] [categories] [example_type]
#
# 示例:
#   ./quick_start.sh my_classifier models/classifier.tflite test_data/images "cat,dog,bird" simple

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 帮助信息
show_help() {
    echo -e "${BLUE}TensorFlow Lite Micro 模型快速集成脚本${NC}"
    echo ""
    echo "使用方法:"
    echo "  $0 <model_name> <model_file> [test_data_dir] [categories] [example_type]"
    echo ""
    echo "参数说明:"
    echo "  model_name      模型名称 (必需)"
    echo "  model_file      .tflite 模型文件路径 (必需)"
    echo "  test_data_dir   测试数据目录 (可选)"
    echo "  categories      分类标签，用逗号分隔 (可选)"
    echo "  example_type    示例类型: simple|benchmark|test (可选，默认: simple)"
    echo ""
    echo "示例:"
    echo "  $0 my_classifier models/classifier.tflite test_data/images \"cat,dog,bird\" simple"
    echo "  $0 audio_model models/audio.tflite test_data/audio \"yes,no,unknown\" benchmark"
    echo ""
}

# 检查参数
if [ $# -lt 2 ]; then
    echo -e "${RED}错误: 参数不足${NC}"
    show_help
    exit 1
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# 参数赋值
MODEL_NAME="$1"
MODEL_FILE="$2"
TEST_DATA_DIR="${3:-}"
CATEGORIES="${4:-}"
EXAMPLE_TYPE="${5:-simple}"

echo -e "${GREEN}开始集成模型: ${MODEL_NAME}${NC}"

# 检查模型文件是否存在
if [ ! -f "$MODEL_FILE" ]; then
    echo -e "${RED}错误: 模型文件不存在: $MODEL_FILE${NC}"
    exit 1
fi

# 获取绝对路径
MODEL_FILE_ABS=$(readlink -f "$MODEL_FILE")
echo -e "${BLUE}模型文件: $MODEL_FILE_ABS${NC}"

# 处理测试数据
TEST_FILES=""
if [ -n "$TEST_DATA_DIR" ] && [ -d "$TEST_DATA_DIR" ]; then
    echo -e "${BLUE}搜索测试数据目录: $TEST_DATA_DIR${NC}"
    TEST_DATA_ABS=$(readlink -f "$TEST_DATA_DIR")
    
    # 查找测试文件
    FILES=$(find "$TEST_DATA_ABS" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.bmp" -o -name "*.wav" -o -name "*.csv" -o -name "*.npy" \) | head -5)
    
    if [ -n "$FILES" ]; then
        TEST_FILES=$(echo "$FILES" | tr '\n' ';' | sed 's/;$//')
        echo -e "${GREEN}找到测试文件:${NC}"
        echo "$FILES" | while read file; do
            echo "  - $(basename $file)"
        done
    else
        echo -e "${YELLOW}警告: 未找到测试文件${NC}"
    fi
fi

# 生成 CMake 配置
CMAKE_CONFIG="# 自动生成的模型集成配置 - $(date)
quick_model_integration(
  ${MODEL_NAME}
  \"${MODEL_FILE_ABS}\""

if [ -n "$TEST_FILES" ]; then
    CMAKE_CONFIG="${CMAKE_CONFIG}
  \"${TEST_FILES}\""
else
    CMAKE_CONFIG="${CMAKE_CONFIG}
  \"\""
fi

if [ -n "$CATEGORIES" ]; then
    # 将逗号替换为分号
    CATEGORIES_FORMATTED=$(echo "$CATEGORIES" | sed 's/,/;/g')
    CMAKE_CONFIG="${CMAKE_CONFIG}
  \"${CATEGORIES_FORMATTED}\""
else
    CMAKE_CONFIG="${CMAKE_CONFIG}
  \"\""
fi

CMAKE_CONFIG="${CMAKE_CONFIG}
  \"${EXAMPLE_TYPE}\"
)"

echo -e "${GREEN}生成的 CMake 配置:${NC}"
echo -e "${YELLOW}$CMAKE_CONFIG${NC}"

# 保存配置到文件
CONFIG_FILE="model_integration_${MODEL_NAME}.cmake"
echo "$CMAKE_CONFIG" > "$CONFIG_FILE"
echo -e "${GREEN}配置已保存到: $CONFIG_FILE${NC}"

# 生成集成指南
INTEGRATION_GUIDE="# ${MODEL_NAME} 集成指南

## 自动生成的配置

将以下代码添加到你的 CMakeLists.txt 文件中:

\`\`\`cmake
$CMAKE_CONFIG
\`\`\`

## 构建步骤

1. 将上述配置添加到 CMakeLists.txt
2. 创建构建目录并编译:
   \`\`\`bash
   mkdir -p build && cd build
   cmake ..
   make ${MODEL_NAME}_${EXAMPLE_TYPE}
   \`\`\`

3. 运行生成的程序:
   \`\`\`bash
   ./${MODEL_NAME}_${EXAMPLE_TYPE}
   \`\`\`

## 自定义配置

### 调整内存大小
编辑生成的 \`models/${MODEL_NAME}/model_settings.h\` 文件:
\`\`\`cpp
constexpr int k${MODEL_NAME}ModelArenaSize = 60 * 1024;  // 根据需要调整
\`\`\`

### 添加操作支持
编辑生成的 \`models/${MODEL_NAME}/${MODEL_NAME}_example.cc\` 文件，在操作解析器中添加所需操作:
\`\`\`cpp
resolver.AddConv2D();
resolver.AddDepthwiseConv2D();
resolver.AddFullyConnected();
resolver.AddSoftmax();
// 添加其他操作...
\`\`\`

## 故障排除

- 如果遇到内存不足错误，增加 \`ModelArenaSize\` 的值
- 如果操作不支持，检查模型并添加相应的操作到解析器
- 确保输入数据格式与模型期望一致

## 文件结构

集成完成后会生成:
- \`models/${MODEL_NAME}/model_settings.h\` - 模型配置
- \`models/${MODEL_NAME}/${MODEL_NAME}_example.cc\` - 示例代码
"

GUIDE_FILE="${MODEL_NAME}_integration_guide.md"
echo "$INTEGRATION_GUIDE" > "$GUIDE_FILE"
echo -e "${GREEN}集成指南已保存到: $GUIDE_FILE${NC}"

echo ""
echo -e "${GREEN}✅ 模型集成准备完成!${NC}"
echo ""
echo -e "${BLUE}下一步:${NC}"
echo "1. 将 $CONFIG_FILE 中的内容添加到你的 CMakeLists.txt"
echo "2. 运行 cmake 和 make 命令进行构建"
echo "3. 查看 $GUIDE_FILE 获取详细指导"
echo ""
echo -e "${YELLOW}注意: 你可能需要根据具体模型调整生成的代码${NC}"