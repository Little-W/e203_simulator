cmake_minimum_required(VERSION 3.18)

project(tflite-micro)

# TFLM 顶层目录
set(TENSORFLOW_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/tflite-micro/)

set(RELATIVE_MAKEFILE_DIR tensorflow/lite/micro/tools/make)
set(MAKEFILE_DIR ${TENSORFLOW_ROOT}${RELATIVE_MAKEFILE_DIR})

# 下载目录：存放下载的第三方库
set(DOWNLOADS_DIR ${MAKEFILE_DIR}/downloads)

# 生成目录：存放生成的代码
set(GENERATED_SUBDIR gen)
set(GENERATED_DIR ${TENSORFLOW_ROOT}${GENERATED_SUBDIR})

# 优化内核目录设置，类似Makefile中的OPTIMIZED_KERNEL_DIR
set(OPTIMIZED_KERNEL_DIR "nmsis_nn" CACHE STRING "Specify which specialized kernel implementation should be pulled in")
set(OPTIMIZED_KERNEL_DIR_PREFIX ${TENSORFLOW_ROOT}tensorflow/lite/micro/kernels)
set(OPTIMIZED_SIGNAL_KERNEL_DIR_PREFIX ${TENSORFLOW_ROOT}signal/micro/kernels)

# 协处理器设置，类似Makefile中的CO_PROCESSOR
set(CO_PROCESSOR "" CACHE STRING "Specify which co-processor's kernel implementation should be pulled in")

# 内核优化设置，类似Makefile中的OPTIMIZE_KERNELS_FOR
set(OPTIMIZE_KERNELS_FOR "KERNELS_OPTIMIZED_FOR_SPEED" CACHE STRING "Optimize kernels for speed or memory")
set_property(CACHE OPTIMIZE_KERNELS_FOR PROPERTY STRINGS KERNELS_OPTIMIZED_FOR_SPEED KERNELS_OPTIMIZED_FOR_SIZE)

# 外部目录设置
set(EXTERNAL_DIR "" CACHE STRING "External directory for additional code paths")

# ----- 修改: 使用 RISC-V 默认配置，移除 ARM/Cortex-M 特定配置 -----
# 原来用于 Cortex-M 的 TARGET_ARCH / FLOAT / CORE 等已移除
set(DEFAULT_RISCV_ARCH "rv32imac" CACHE STRING "Default RISC-V ISA for builds")
set(DEFAULT_RISCV_ABI  "ilp32"   CACHE STRING "Default RISC-V ABI for builds")

set(TARGET_ARCH ${DEFAULT_RISCV_ARCH} CACHE STRING "Target architecture (RISC-V ISA)")
set(RISCV_ABI ${DEFAULT_RISCV_ABI} CACHE STRING "RISC-V ABI")
set(TOOLCHAIN "gcc" CACHE STRING "Toolchain to use (gcc or riscv toolchain)")

# 保留用于 -march 的变量
set(GCC_TARGET_ARCH ${TARGET_ARCH})
# 保留字符类型选项，默认为 unsigned（与原行为一致）
set(SIGNED_CHAR false)

message(STATUS "Target Architecture (RISC-V): ${TARGET_ARCH}")
message(STATUS "RISC-V ABI: ${RISCV_ABI}")
message(STATUS "Toolchain: ${TOOLCHAIN}")

# 公共头文件目录列表，用于将传递给编译 TFLM 目标的 include_directories 中
set(PUBLIC_INCLUDES
  ${TENSORFLOW_ROOT}
  ${GENERATED_DIR}
  ${DOWNLOADS_DIR}/flatbuffers/include
  ${DOWNLOADS_DIR}/gemmlowp
)

# message(STATUS "PUBLIC_INCLUDES: ${PUBLIC_INCLUDES}")

# 头文件目录列表
set(INCLUDES
  ${DOWNLOADS_DIR}
  ${DOWNLOADS_DIR}/gemmlowp
  ${DOWNLOADS_DIR}/flatbuffers/include
  ${DOWNLOADS_DIR}/kissfft
  ${DOWNLOADS_DIR}/ruy
  ${PUBLIC_INCLUDES}
)

# 编译警告相关选项
set(CC_WARNINGS
  -Wsign-compare
  -Wdouble-promotion
  -Wunused-variable
  -Wunused-function
  -Wswitch
  -Wvla
  -Wall
  -Wextra
  -Wmissing-field-initializers
  -Wstrict-aliasing
  -Wno-unused-parameter
)

# 不是 clang 或 GCC 系列编译器，附加 -Wshadow
if (NOT CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  list(APPEND CC_WARNINGS -Wshadow)
endif()

# 额外定义，基于优化内核目录和协处理器设置
set(ADDITIONAL_DEFINES)
# list(APPEND ADDITIONAL_DEFINES -DCMSIS_NN)
if(OPTIMIZED_KERNEL_DIR)
  string(TOUPPER ${OPTIMIZED_KERNEL_DIR} OPTIMIZED_KERNEL_DIR_UPPER)
  list(APPEND ADDITIONAL_DEFINES -D${OPTIMIZED_KERNEL_DIR_UPPER})
endif()

if(CO_PROCESSOR)
  string(TOUPPER ${CO_PROCESSOR} CO_PROCESSOR_UPPER)
  list(APPEND ADDITIONAL_DEFINES -D${CO_PROCESSOR_UPPER})
endif()

if(OPTIMIZE_KERNELS_FOR)
  string(TOUPPER ${OPTIMIZE_KERNELS_FOR} OPTIMIZE_KERNELS_FOR_UPPER)
  list(APPEND ADDITIONAL_DEFINES -D${OPTIMIZE_KERNELS_FOR_UPPER})
endif()

# Cortex-M 平台编译选项替换为 RISC-V 平台选项
set(PLATFORM_FLAGS)
if(TARGET_ARCH MATCHES "rv.*")
  list(APPEND PLATFORM_FLAGS
    -DTF_LITE_MCU_DEBUG_LOG
    -Wno-type-limits
    -Wno-unused-private-field
    -fomit-frame-pointer
    -MD
  )

  # 对于 GCC 工具链，使用 -march 和 -mabi
  if(TOOLCHAIN STREQUAL "gcc")
    list(APPEND PLATFORM_FLAGS -march=${GCC_TARGET_ARCH})
    list(APPEND PLATFORM_FLAGS -mabi=${RISCV_ABI})
  endif()

  # 字符类型设置（保留原先逻辑）
  if(SIGNED_CHAR)
    list(APPEND PLATFORM_FLAGS -fsigned-char)
  else()
    list(APPEND PLATFORM_FLAGS -funsigned-char)
  endif()
endif()

# C/C++通用编译选项
set(COMMON_FLAGS
  -Os
  # 兼容 NMSIS 源文件：关闭建议添加括号的警告并避免将其视为错误
  -Wno-parentheses
  -Wno-error=parentheses
  -Wno-unused-variable
  -fno-unwind-tables
  -fno-asynchronous-unwind-tables
  -ffunction-sections
  -fdata-sections
  -fmessage-length=0
  -funsigned-char
  -fno-delete-null-pointer-checks
  -fomit-frame-pointer
  -Wvla
  -Wall
  -Wextra
  -Wsign-compare
  -Wdouble-promotion
  -Wno-shadow
  -Wunused-variable
  -Wmissing-field-initializers
  -Wno-unused-parameter
  -Wno-write-strings
  -Wunused-function
  -Wno-unused-function
  # -DTF_LITE_STATIC_MEMORY
  -DTF_LITE_DISABLE_X86_NEON
  ${ADDITIONAL_DEFINES}
  ${PLATFORM_FLAGS}
)

message(STATUS "Additional defines: ${ADDITIONAL_DEFINES}")

# C++ 编译选项
set(CXXFLAGS
  -std=c++17
  -fno-rtti
  -fno-exceptions
  -fno-threadsafe-statics
  -fno-use-cxa-atexit
  -fpermissive
  -Wnon-virtual-dtor
  ${COMMON_FLAGS}
  ${PLATFORM_FLAGS}
)

# C 编译选项
set(CCFLAGS
  -Wimplicit-function-declaration
  -std=c17
  ${COMMON_FLAGS}
)

# 如果当前构建类型是 release，则添加 -DNDEBUG
if (CMAKE_BUILD_TYPE STREQUAL "Release")
  list(APPEND CXXFLAGS -DNDEBUG -DTF_LITE_STRIP_ERROR_STRINGS)
  list(APPEND CCFLAGS -DNDEBUG -DTF_LITE_STRIP_ERROR_STRINGS)
endif()

# MICROLITE_BENCHMARK_SRCS := ...
set(MICROLITE_BENCHMARK_SRCS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/benchmarks/*benchmark.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/tools/benchmarking/*benchmark.cc
)

# 包含基础源代码定义
include(${CMAKE_CURRENT_SOURCE_DIR}/tflm_basic_src.cmake)

# TFL_CC_SRCS := ...
file(GLOB_RECURSE TFL_CC_SRCS
  ${TENSORFLOW_ROOT}tensorflow/**/*.cc
  ${TENSORFLOW_ROOT}tensorflow/*.c
)

# 排除 ${TENSORFLOW_ROOT}tensorflow/lite/experimental/*.*
list(FILTER TFL_CC_SRCS EXCLUDE REGEX "${TENSORFLOW_ROOT}tensorflow/lite/experimental/.*")
# 排除 ${TENSORFLOW_ROOT}tensorflow/lite/micro/*.*
list(FILTER TFL_CC_SRCS EXCLUDE REGEX "${TENSORFLOW_ROOT}tensorflow/lite/micro/.*")
# message(STATUS "TFL_CC_SRCS: ${TFL_CC_SRCS}")

# TFL_CC_HDRS := ...
file(GLOB_RECURSE TFL_CC_HDRS
  ${TENSORFLOW_ROOT}tensorflow/**/*.h
)

# 排除 ${TENSORFLOW_ROOT}tensorflow/lite/experimental/*.*
list(FILTER TFL_CC_HDRS EXCLUDE REGEX "${TENSORFLOW_ROOT}tensorflow/lite/experimental/.*")
# 排除 ${TENSORFLOW_ROOT}tensorflow/lite/micro/*.*
list(FILTER TFL_CC_HDRS EXCLUDE REGEX "${TENSORFLOW_ROOT}tensorflow/lite/micro/.*")
message(STATUS "TFL_CC_HDRS: ${TFL_CC_HDRS}")

# 追加 MICROLITE_CC_BASE_SRCS
file(GLOB MICROLITE_CC_BASE_SRCS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/*.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/arena_allocator/*.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/memory_planner/*.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/tflite_bridge/*.cc
)
# 过滤 tensorflow/lite/micro/micro_time.cc，避免与用户自定义实现冲突
list(FILTER MICROLITE_CC_BASE_SRCS EXCLUDE REGEX "${TENSORFLOW_ROOT}tensorflow/lite/micro/micro_time.cc")

# 添加 RISC-V 平台特定的 debug_log 实现
list(APPEND MICROLITE_CC_BASE_SRCS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/riscv32_generic/debug_log.cc
)

list(APPEND MICROLITE_CC_BASE_SRCS ${TFL_CC_SRCS})

# 初始化第三方库变量
set(THIRD_PARTY_CC_SRCS)
set(THIRD_PARTY_KERNEL_CC_SRCS)

# 处理第三方库和优化内核设置
include(${CMAKE_CURRENT_SOURCE_DIR}/third_party_and_optimizations.cmake)

file(GLOB MICROLITE_CC_HDRS
  ${TENSORFLOW_ROOT}signal/micro/kernels/*.h
  ${TENSORFLOW_ROOT}signal/src/*.h
  ${TENSORFLOW_ROOT}tensorflow/**/*.h
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/benchmarks/*model_data.h
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/kernels/*.h
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/arena_allocator/*.h
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/memory_planner/*.h
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/tflite_bridge/*.h
  ${TENSORFLOW_ROOT}LICENSE
)

# MICROLITE_CC_SRCS := $(filter-out $(MICROLITE_TEST_SRCS), $(MICROLITE_CC_BASE_SRCS))
set(MICROLITE_CC_SRCS ${MICROLITE_CC_BASE_SRCS})
list(REMOVE_ITEM MICROLITE_CC_SRCS ${MICROLITE_TEST_SRCS})

# MICROLITE_CC_SRCS := $(filter-out $(MICROLITE_BENCHMARK_SRCS), $(MICROLITE_CC_SRCS))
set(MICROLITE_CC_SRCS ${MICROLITE_CC_SRCS})
list(REMOVE_ITEM MICROLITE_CC_SRCS ${MICROLITE_BENCHMARK_SRCS})

# MICROLITE_CC_KERNEL_SRCS += $(MICROLITE_CC_SIGNAL_KERNEL_SRCS)
list(APPEND MICROLITE_CC_KERNEL_SRCS ${MICROLITE_CC_SIGNAL_KERNEL_SRCS})

# 第三方库头文件和源文件已在 third_party_and_optimizations.cmake 中定义

# TFLM 库文件名
set(MICROLITE_LIB_NAME "tflite-micro")

# declare tflite-micro static library
add_library(${MICROLITE_LIB_NAME} STATIC
  ${MICROLITE_CC_SRCS}
  ${MICROLITE_CC_HDRS}
  ${MICROLITE_CC_KERNEL_SRCS}
  ${THIRD_PARTY_CC_SRCS}
  ${THIRD_PARTY_KERNEL_CC_SRCS}
)

target_include_directories(${MICROLITE_LIB_NAME}
  PRIVATE ${INCLUDES}
  PUBLIC ${PUBLIC_INCLUDES}
)

target_compile_options(${MICROLITE_LIB_NAME}
  PRIVATE $<$<COMPILE_LANGUAGE:CXX>:${CXXFLAGS}>
  PRIVATE $<$<COMPILE_LANGUAGE:C>:${CCFLAGS}>
  PRIVATE ${CC_WARNINGS}
)

# 设置编译的C++标准为C++17
set_target_properties(${MICROLITE_LIB_NAME} PROPERTIES
  CXX_STANDARD 17
)

# 包含工具函数
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake_utils.cmake)
include(${CMAKE_CURRENT_SOURCE_DIR}/model_integration.cmake)

# Declare keyword_benchmark
# KEYWORD_BENCHMARK_SRCS :=
set(KEYWORD_BENCHMARK_SRCS ${TENSORFLOW_ROOT}tensorflow/lite/micro/benchmarks/keyword_benchmark.cc)

# KEYWORD_BENCHMARK_GENERATOR_INPUTS :=
set(KEYWORD_BENCHMARK_GENERATOR_INPUTS ${TENSORFLOW_ROOT}tensorflow/lite/micro/models/keyword_scrambled.tflite)

# KEYWORD_BENCHMARK_HDRS :=
set(KEYWORD_BENCHMARK_HDRS ${TENSORFLOW_ROOT}tensorflow/lite/micro/benchmarks/micro_benchmark.h)

microlite_test(keyword_benchmark
  "${KEYWORD_BENCHMARK_SRCS}"
  "${KEYWORD_BENCHMARK_HDRS}"
  "${KEYWORD_BENCHMARK_GENERATOR_INPUTS}"
)

# Declare person_detection_benchmark
# PERSON_DETECTION_BENCHMARK_SRCS :=
set(PERSON_DETECTION_BENCHMARK_SRCS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/benchmarks/person_detection_benchmark.cc
)

# PERSON_DETECTION_BENCHMARK_HDRS :=
set(PERSON_DETECTION_BENCHMARK_HDRS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/model_settings.h
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/benchmarks/micro_benchmark.h
)

# PERSON_DETECTION_BENCHMARK_GENERATOR_INPUTS :=
set(PERSON_DETECTION_BENCHMARK_GENERATOR_INPUTS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/testdata/person.bmp
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/testdata/no_person.bmp
)

# PERSON_DETECTION_BENCHMARK_GENERATOR_INPUTS +=
list(APPEND PERSON_DETECTION_BENCHMARK_GENERATOR_INPUTS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/models/person_detect.tflite
)

microlite_test(person_detection_benchmark
  "${PERSON_DETECTION_BENCHMARK_SRCS}"
  "${PERSON_DETECTION_BENCHMARK_HDRS}"
  "${PERSON_DETECTION_BENCHMARK_GENERATOR_INPUTS}"
)

# Declare person_detection_test
# PERSON_DETECTION_TEST_SRCS :=
set(PERSON_DETECTION_TEST_SRCS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/main.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/person_detection_test.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/main_functions.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/detection_responder.cc
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/image_provider.cc
  )

# PERSON_DETECTION_TEST_HDRS :=
set(PERSON_DETECTION_TEST_HDRS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/model_settings.h
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/testing/micro_test.h
)

# PERSON_DETECTION_TEST_GENERATOR_INPUTS :=
set(PERSON_DETECTION_TEST_GENERATOR_INPUTS
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/testdata/person.bmp
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/examples/person_detection/testdata/no_person.bmp
  ${TENSORFLOW_ROOT}tensorflow/lite/micro/models/person_detect.tflite
)

microlite_test(person_detection_test
  "${PERSON_DETECTION_TEST_SRCS}"
  "${PERSON_DETECTION_TEST_HDRS}"
  "${PERSON_DETECTION_TEST_GENERATOR_INPUTS}"
)

# Declare my_model library and example
# MY_MODEL_SRCS :=
set(MY_MODEL_SRCS
  ${TENSORFLOW_ROOT}my_model/my_model.cc
  ${TENSORFLOW_ROOT}my_model/example_usage.cc
  ${TENSORFLOW_ROOT}my_model/model_settings.cc
  ${TENSORFLOW_ROOT}my_model/model_interface.cc
)

# MY_MODEL_HDRS :=
set(MY_MODEL_HDRS
  ${TENSORFLOW_ROOT}my_model/my_model.h
  ${TENSORFLOW_ROOT}my_model/model_settings.h
  ${TENSORFLOW_ROOT}my_model/model_interface.h
)

# MY_MODEL_GENERATOR_INPUTS :=
set(MY_MODEL_GENERATOR_INPUTS
  ${TENSORFLOW_ROOT}my_model/testdata/Z_test.bmp
  ${TENSORFLOW_ROOT}my_model/testdata/W_test.bmp
  ${TENSORFLOW_ROOT}my_model/models/justure_detect.tflite
)

# 创建 my_model 测试目标
microlite_test(my_model
  "${MY_MODEL_SRCS}"
  "${MY_MODEL_HDRS}"
  "${MY_MODEL_GENERATOR_INPUTS}"
)