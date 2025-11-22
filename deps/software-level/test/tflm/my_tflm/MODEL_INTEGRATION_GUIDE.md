# TensorFlow Lite Micro 模型快速集成指南

这个文档展示如何快速集成你的自定义模型到 TensorFlow Lite Micro 项目中。

## 快速开始

### 1. 基本模型集成

最简单的方式是使用 `quick_model_integration` 函数：

```cmake
# 在 CMakeLists.txt 中添加
quick_model_integration(
  my_classifier                                    # 模型名称
  "${CMAKE_CURRENT_SOURCE_DIR}/models/my_model.tflite"  # 模型文件路径
  "${CMAKE_CURRENT_SOURCE_DIR}/test_data/test1.jpg;${CMAKE_CURRENT_SOURCE_DIR}/test_data/test2.jpg"  # 测试数据
  "cat;dog;bird;fish"                             # 分类标签
  "simple"                                        # 示例类型
)
```

### 2. 不同的示例类型

#### 简单示例 (simple)
```cmake
quick_model_integration(my_model "model.tflite" "test.jpg" "cat;dog" "simple")
```
生成一个基础的推理示例，展示模型加载和基本信息。

#### 基准测试 (benchmark)
```cmake
quick_model_integration(my_model "model.tflite" "test.jpg" "cat;dog" "benchmark")
```
生成性能基准测试，用于测量模型推理速度。

#### 功能测试 (test)
```cmake
quick_model_integration(my_model "model.tflite" "test.jpg" "cat;dog" "test")
```
生成功能测试，验证模型是否正常工作。

## 文件结构

集成后会生成以下文件结构：
```
models/
└── my_model/
    ├── model_settings.h      # 模型配置头文件
    └── my_model_example.cc   # 示例应用代码
```

## 构建目标

根据示例类型，会创建不同的构建目标：
- `my_model_example` (simple)
- `my_model_benchmark` (benchmark)  
- `my_model_test` (test)

## 高级用法

### 1. 自定义操作解析器

生成的代码包含操作解析器模板，你需要根据模型添加所需的操作：

```cpp
${MODEL_NAME}OpResolver& get_${MODEL_NAME}_op_resolver() {
  static ${MODEL_NAME}OpResolver resolver;
  
  // 根据你的模型添加需要的操作
  resolver.AddFullyConnected();
  resolver.AddSoftmax();
  resolver.AddConv2D();
  resolver.AddDepthwiseConv2D();
  resolver.AddAdd();
  resolver.AddMul();
  resolver.AddRelu();
  // 更多操作...
  
  return resolver;
}
```

### 2. 内存配置

调整模型设置中的内存大小：

```cpp
// 在生成的 model_settings.h 中
constexpr int kMyModelModelArenaSize = 60 * 1024;  // 根据你的模型调整
constexpr int kMyModelInputSize = 224 * 224 * 3;   // 根据输入大小调整
```

### 3. 输入数据处理

在生成的示例代码中添加你的数据预处理逻辑：

```cpp
// 在 main 函数中
TfLiteTensor* input = interpreter.input(0);

// TODO: 添加你的数据预处理代码
// 例如：图像预处理、音频预处理等
```

## 完整示例

假设你有一个图像分类模型，这是完整的集成步骤：

### 1. 准备文件
```
my_project/
├── models/
│   └── image_classifier.tflite
└── test_data/
    ├── cat.jpg
    ├── dog.jpg
    └── bird.jpg
```

### 2. 在 CMakeLists.txt 中添加
```cmake
quick_model_integration(
  image_classifier
  "${CMAKE_CURRENT_SOURCE_DIR}/models/image_classifier.tflite"
  "${CMAKE_CURRENT_SOURCE_DIR}/test_data/cat.jpg;${CMAKE_CURRENT_SOURCE_DIR}/test_data/dog.jpg;${CMAKE_CURRENT_SOURCE_DIR}/test_data/bird.jpg"
  "cat;dog;bird"
  "simple"
)
```

### 3. 构建和运行
```bash
mkdir build && cd build
cmake ..
make image_classifier_example
./image_classifier_example
```

## 故障排除

### 1. 模型文件未找到
确保模型文件路径正确，使用绝对路径或正确的相对路径。

### 2. 内存不足
增加 `kModelArenaSize` 的值：
```cpp
constexpr int kMyModelModelArenaSize = 100 * 1024;  // 增加内存
```

### 3. 操作不支持
检查模型需要的操作，在操作解析器中添加对应的操作：
```cpp
resolver.AddConv2D();
resolver.AddDepthwiseConv2D();
// 添加模型需要的其他操作
```

### 4. 输入输出维度不匹配
检查并更新 `model_settings.h` 中的输入输出大小配置。

## 注意事项

1. **操作支持**: 确保你的模型只使用 TensorFlow Lite Micro 支持的操作
2. **内存限制**: 嵌入式设备内存有限，选择合适的模型大小和 arena 大小
3. **数据类型**: 注意模型的输入输出数据类型（float32, uint8, int8 等）
4. **性能优化**: 考虑使用量化模型来减少内存占用和提高推理速度

## 进一步定制

如果需要更复杂的集成，你可以：

1. 修改生成的源代码文件
2. 创建自定义的预处理和后处理函数
3. 添加自定义的操作支持
4. 实现特定的硬件优化

这个快速集成工具为你提供了一个良好的起点，你可以在此基础上进行进一步的定制和优化。