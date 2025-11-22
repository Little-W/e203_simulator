# platform_config.cmake
# 管理 TensorFlow Lite Micro 的平台配置和内核优化设置

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

# Cortex-M 平台特定的定义
if(CORE)
  list(APPEND ADDITIONAL_DEFINES -DCPU_${CORE}=1)
endif()

if(ARM_CPU)
  list(APPEND ADDITIONAL_DEFINES -D${ARM_CPU})
  list(APPEND ADDITIONAL_DEFINES -DCMSIS_DEVICE_ARM_CORTEX_M_XX_HEADER_FILE=\"${ARM_CPU}.h\")
endif()

# Cortex-M55 和 Cortex-M85 使用 PMU 计数器
if(ARM_CPU MATCHES "ARMCM55|ARMCM85")
  list(APPEND ADDITIONAL_DEFINES -DARM_MODEL_USE_PMU_COUNTERS)
endif()

# Cortex-M 平台编译选项
set(PLATFORM_FLAGS)
if(TARGET_ARCH MATCHES "cortex-m.*")
  list(APPEND PLATFORM_FLAGS
    -DTF_LITE_MCU_DEBUG_LOG
    -mthumb
    -mfloat-abi=${FLOAT}
    -mlittle-endian
    -Wno-type-limits
    -Wno-unused-private-field
    -fomit-frame-pointer
    -MD
  )
  
  # GCC 特定的 CPU 和 FPU 选项
  if(TOOLCHAIN STREQUAL "gcc")
    list(APPEND PLATFORM_FLAGS -mcpu=${GCC_TARGET_ARCH})
    
    if(TARGET_ARCH STREQUAL "cortex-m4" OR TARGET_ARCH STREQUAL "cortex-m7")
      list(APPEND PLATFORM_FLAGS -mfpu=fpv4-sp-d16)
    elseif(FPU)
      list(APPEND PLATFORM_FLAGS -mfpu=${FPU})
    else()
      list(APPEND PLATFORM_FLAGS -mfpu=auto)
    endif()
  endif()
  
  # 字符类型设置
  if(SIGNED_CHAR)
    list(APPEND PLATFORM_FLAGS -fsigned-char)
  else()
    list(APPEND PLATFORM_FLAGS -funsigned-char)
  endif()
endif()

# C/C++通用编译选项
set(COMMON_FLAGS
  -Werror
  -fno-unwind-tables
  -fno-asynchronous-unwind-tables
  -ffunction-sections
  -fdata-sections
  -fmessage-length=0
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
  -Wnon-virtual-dtor
  ${COMMON_FLAGS}
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

# 确保变量在父作用域可见
set(ADDITIONAL_DEFINES ${ADDITIONAL_DEFINES} PARENT_SCOPE)
set(PLATFORM_FLAGS ${PLATFORM_FLAGS} PARENT_SCOPE)
set(COMMON_FLAGS ${COMMON_FLAGS} PARENT_SCOPE)
set(CXXFLAGS ${CXXFLAGS} PARENT_SCOPE)
set(CCFLAGS ${CCFLAGS} PARENT_SCOPE)