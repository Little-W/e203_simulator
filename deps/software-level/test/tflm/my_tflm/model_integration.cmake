# Copyright 2025 TensorFlow Lite Micro Model Integration Utilities
#
# This file provides utilities for quickly integrating custom models
# into TensorFlow Lite Micro projects.

#==============================================================================
# quick_model_integration: Quickly integrate a custom model
#
# This function creates a complete integration for a custom model including:
# - Model data generation from .tflite file
# - Test data generation from input files
# - Example application code generation
# - Build target creation
#
# Arguments:
#   MODEL_NAME     - Name of the model (used for target and variable names)
#   TFLITE_FILE    - Path to the .tflite model file
#   INPUT_FILES    - List of input test data files (.wav, .bmp, .csv, .npy)
#   CATEGORIES     - List of output categories/labels (optional)
#   EXAMPLE_TYPE   - Type of example: "simple", "benchmark", "test" (default: simple)
#
# Example usage:
#   quick_model_integration(
#     my_model
#     "${CMAKE_CURRENT_SOURCE_DIR}/models/my_model.tflite" 
#     "${CMAKE_CURRENT_SOURCE_DIR}/test_data/input1.wav;${CMAKE_CURRENT_SOURCE_DIR}/test_data/input2.wav"
#     "cat;dog;bird"
#     "simple"
#   )
#==============================================================================
function(quick_model_integration MODEL_NAME TFLITE_FILE INPUT_FILES CATEGORIES EXAMPLE_TYPE)
  # 设置默认值
  if(NOT EXAMPLE_TYPE)
    set(EXAMPLE_TYPE "simple")
  endif()
  
  # 验证输入文件
  if(NOT EXISTS ${TFLITE_FILE})
    message(FATAL_ERROR "TFLite model file not found: ${TFLITE_FILE}")
  endif()
  
  message(STATUS "=== Quick Model Integration: ${MODEL_NAME} ===")
  message(STATUS "  Model file: ${TFLITE_FILE}")
  message(STATUS "  Input files: ${INPUT_FILES}")
  message(STATUS "  Categories: ${CATEGORIES}")
  message(STATUS "  Example type: ${EXAMPLE_TYPE}")
  
  # 创建模型专用目录
  set(MODEL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/models/${MODEL_NAME})
  file(MAKE_DIRECTORY ${MODEL_DIR})
  
  # 生成模型设置头文件
  set(MODEL_SETTINGS_FILE ${MODEL_DIR}/model_settings.h)
  generate_model_settings_header(${MODEL_NAME} "${CATEGORIES}" ${MODEL_SETTINGS_FILE})
  
  # 生成示例应用代码
  set(EXAMPLE_SOURCE_FILE ${MODEL_DIR}/${MODEL_NAME}_example.cc)
  generate_example_source(${MODEL_NAME} ${EXAMPLE_TYPE} ${EXAMPLE_SOURCE_FILE})
  
  # 准备输入文件列表
  set(ALL_INPUT_FILES ${TFLITE_FILE})
  if(INPUT_FILES)
    list(APPEND ALL_INPUT_FILES ${INPUT_FILES})
  endif()
  
  # 创建构建目标
  if(EXAMPLE_TYPE STREQUAL "benchmark")
    microlite_test(${MODEL_NAME}_benchmark
      "${EXAMPLE_SOURCE_FILE}"
      "${MODEL_SETTINGS_FILE}"
      "${ALL_INPUT_FILES}"
    )
  elseif(EXAMPLE_TYPE STREQUAL "test")
    microlite_test(${MODEL_NAME}_test
      "${EXAMPLE_SOURCE_FILE}"
      "${MODEL_SETTINGS_FILE}"
      "${ALL_INPUT_FILES}"
    )
  else()
    microlite_executable(${MODEL_NAME}_example
      "${EXAMPLE_SOURCE_FILE}"
      "${MODEL_SETTINGS_FILE}"
      "${ALL_INPUT_FILES}"
    )
  endif()
  
  message(STATUS "=== Model Integration Complete ===")
  message(STATUS "Generated files:")
  message(STATUS "  - ${MODEL_SETTINGS_FILE}")
  message(STATUS "  - ${EXAMPLE_SOURCE_FILE}")
  message(STATUS "Build target: ${MODEL_NAME}_${EXAMPLE_TYPE}")
endfunction()

#==============================================================================
# generate_model_settings_header: Generate model settings header file
#==============================================================================
function(generate_model_settings_header MODEL_NAME CATEGORIES OUTPUT_FILE)
  # 转换模型名为大写用于宏定义
  string(TOUPPER ${MODEL_NAME} MODEL_NAME_UPPER)
  
  # 处理分类标签
  set(CATEGORIES_ARRAY "")
  set(CATEGORY_COUNT 0)
  if(CATEGORIES)
    string(REPLACE ";" "\", \"" CATEGORIES_FORMATTED ${CATEGORIES})
    set(CATEGORIES_ARRAY "\"${CATEGORIES_FORMATTED}\"")
    list(LENGTH CATEGORIES CATEGORY_COUNT)
  endif()
  
  # 生成头文件内容
  file(WRITE ${OUTPUT_FILE}
"// Copyright 2025 The TensorFlow Authors. All Rights Reserved.
// Auto-generated model settings for ${MODEL_NAME}

#ifndef TENSORFLOW_LITE_MICRO_EXAMPLES_${MODEL_NAME_UPPER}_MODEL_SETTINGS_H_
#define TENSORFLOW_LITE_MICRO_EXAMPLES_${MODEL_NAME_UPPER}_MODEL_SETTINGS_H_

// Model configuration
constexpr int k${MODEL_NAME}ModelArenaSize = 60 * 1024;  // Adjust based on your model
constexpr int k${MODEL_NAME}InputSize = 224 * 224 * 3;   // Adjust based on your input
constexpr int k${MODEL_NAME}OutputSize = ${CATEGORY_COUNT};

// Category labels
constexpr int k${MODEL_NAME}CategoryCount = ${CATEGORY_COUNT};
")

  if(CATEGORY_COUNT GREATER 0)
    file(APPEND ${OUTPUT_FILE}
"extern const char* k${MODEL_NAME}CategoryLabels[k${MODEL_NAME}CategoryCount];
")
  endif()

  file(APPEND ${OUTPUT_FILE}
"
#endif  // TENSORFLOW_LITE_MICRO_EXAMPLES_${MODEL_NAME_UPPER}_MODEL_SETTINGS_H_
")
endfunction()

#==============================================================================
# generate_example_source: Generate example application source code
#==============================================================================
function(generate_example_source MODEL_NAME EXAMPLE_TYPE OUTPUT_FILE)
  # 转换模型名
  string(TOUPPER ${MODEL_NAME} MODEL_NAME_UPPER)
  
  # 生成基础源文件
  file(WRITE ${OUTPUT_FILE}
"// Copyright 2025 The TensorFlow Authors. All Rights Reserved.
// Auto-generated example application for ${MODEL_NAME}

#include <cstdio>
#include \"tensorflow/lite/micro/micro_interpreter.h\"
#include \"tensorflow/lite/micro/micro_log.h\"
#include \"tensorflow/lite/micro/micro_mutable_op_resolver.h\"
#include \"tensorflow/lite/micro/system_setup.h\"
#include \"tensorflow/lite/schema/schema_generated.h\"

#include \"model_settings.h\"

// Include generated model data
#include \"${MODEL_NAME}_model_data.h\"

namespace {
using ${MODEL_NAME}OpResolver = tflite::MicroMutableOpResolver<10>;

${MODEL_NAME}OpResolver& get_${MODEL_NAME}_op_resolver() {
  static ${MODEL_NAME}OpResolver resolver;
  // Add required operations here
  // Example: resolver.AddFullyConnected();
  //          resolver.AddSoftmax();
  //          resolver.AddConv2D();
  return resolver;
}

// Arena for model execution
alignas(16) uint8_t g_${MODEL_NAME}_arena[k${MODEL_NAME}ModelArenaSize];

}  // namespace

")

  # 根据示例类型生成不同的main函数
  if(EXAMPLE_TYPE STREQUAL "benchmark")
    file(APPEND ${OUTPUT_FILE}
"#include \"tensorflow/lite/micro/benchmarks/micro_benchmark.h\"

void ${MODEL_NAME}_benchmark_run(int iterations) {
  // Initialize the TensorFlow Lite interpreter
  const tflite::Model* model = tflite::GetModel(g_${MODEL_NAME}_model_data);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    MicroPrintf(\"Model schema version %d not supported\", model->version());
    return;
  }

  ${MODEL_NAME}OpResolver& op_resolver = get_${MODEL_NAME}_op_resolver();
  
  tflite::MicroInterpreter interpreter(model, op_resolver, g_${MODEL_NAME}_arena, 
                                      k${MODEL_NAME}ModelArenaSize);
  
  if (interpreter.AllocateTensors() != kTfLiteOk) {
    MicroPrintf(\"AllocateTensors() failed\");
    return;
  }

  // Run benchmark
  for (int i = 0; i < iterations; ++i) {
    if (interpreter.Invoke() != kTfLiteOk) {
      MicroPrintf(\"Invoke() failed on iteration %d\", i);
      return;
    }
  }
  
  MicroPrintf(\"${MODEL_NAME} benchmark completed %d iterations\", iterations);
}

int main(int argc, char* argv[]) {
  tflite::InitializeTarget();
  
  const int kIterations = 100;  // Adjust as needed
  ${MODEL_NAME}_benchmark_run(kIterations);
  
  MicroPrintf(\"${MODEL_NAME} benchmark finished\");
  return 0;
}
")
  elseif(EXAMPLE_TYPE STREQUAL "test")
    file(APPEND ${OUTPUT_FILE}
"int main(int argc, char* argv[]) {
  tflite::InitializeTarget();
  
  MicroPrintf(\"Starting ${MODEL_NAME} test\");
  
  // Initialize the TensorFlow Lite interpreter
  const tflite::Model* model = tflite::GetModel(g_${MODEL_NAME}_model_data);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    MicroPrintf(\"Model test FAILED: Unsupported schema version %d\", model->version());
    return 1;
  }

  ${MODEL_NAME}OpResolver& op_resolver = get_${MODEL_NAME}_op_resolver();
  
  tflite::MicroInterpreter interpreter(model, op_resolver, g_${MODEL_NAME}_arena, 
                                      k${MODEL_NAME}ModelArenaSize);
  
  if (interpreter.AllocateTensors() != kTfLiteOk) {
    MicroPrintf(\"Model test FAILED: AllocateTensors() failed\");
    return 1;
  }

  // Get input tensor
  TfLiteTensor* input = interpreter.input(0);
  if (input == nullptr) {
    MicroPrintf(\"Model test FAILED: Could not get input tensor\");
    return 1;
  }

  // TODO: Load test data and populate input tensor
  // For now, just fill with dummy data
  for (int i = 0; i < input->bytes; ++i) {
    input->data.uint8[i] = i % 256;
  }

  // Run inference
  if (interpreter.Invoke() != kTfLiteOk) {
    MicroPrintf(\"Model test FAILED: Invoke() failed\");
    return 1;
  }

  // Get output
  TfLiteTensor* output = interpreter.output(0);
  if (output == nullptr) {
    MicroPrintf(\"Model test FAILED: Could not get output tensor\");
    return 1;
  }

  MicroPrintf(\"${MODEL_NAME} test PASSED\");
  MicroPrintf(\"Output shape: [%d, %d, %d, %d]\", 
             output->dims->data[0], output->dims->data[1], 
             output->dims->data[2], output->dims->data[3]);
  
  return 0;
}
")
  else()  # simple example
    file(APPEND ${OUTPUT_FILE}
"int main(int argc, char* argv[]) {
  tflite::InitializeTarget();
  
  MicroPrintf(\"${MODEL_NAME} inference example\");
  
  // Initialize the TensorFlow Lite interpreter
  const tflite::Model* model = tflite::GetModel(g_${MODEL_NAME}_model_data);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    MicroPrintf(\"Model schema version %d not supported\", model->version());
    return 1;
  }

  ${MODEL_NAME}OpResolver& op_resolver = get_${MODEL_NAME}_op_resolver();
  
  tflite::MicroInterpreter interpreter(model, op_resolver, g_${MODEL_NAME}_arena, 
                                      k${MODEL_NAME}ModelArenaSize);
  
  if (interpreter.AllocateTensors() != kTfLiteOk) {
    MicroPrintf(\"AllocateTensors() failed\");
    return 1;
  }

  // Print model information
  MicroPrintf(\"Model loaded successfully\");
  MicroPrintf(\"Input tensor count: %d\", interpreter.inputs_size());
  MicroPrintf(\"Output tensor count: %d\", interpreter.outputs_size());
  
  TfLiteTensor* input = interpreter.input(0);
  TfLiteTensor* output = interpreter.output(0);
  
  MicroPrintf(\"Input shape: [%d, %d, %d, %d]\", 
             input->dims->data[0], input->dims->data[1], 
             input->dims->data[2], input->dims->data[3]);
  MicroPrintf(\"Output shape: [%d, %d, %d, %d]\", 
             output->dims->data[0], output->dims->data[1], 
             output->dims->data[2], output->dims->data[3]);

  // TODO: Add your inference code here
  // 1. Populate input tensor with your data
  // 2. Call interpreter.Invoke()
  // 3. Process output tensor results
  
  MicroPrintf(\"${MODEL_NAME} example completed\");
  return 0;
}
")
  endif()
endfunction()