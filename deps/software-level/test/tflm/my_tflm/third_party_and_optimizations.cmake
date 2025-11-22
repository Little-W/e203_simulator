# third_party_and_optimizations.cmake
# 管理 TensorFlow Lite Micro 的第三方库和优化内核设置

# 包含 NMSIS 配置
include(${CMAKE_CURRENT_LIST_DIR}/nmsis_config.cmake)

# 处理优化内核目录
if(OPTIMIZED_KERNEL_DIR)
  set(PATH_TO_OPTIMIZED_KERNELS ${OPTIMIZED_KERNEL_DIR_PREFIX}/${OPTIMIZED_KERNEL_DIR})
  set(PATH_TO_SIGNAL_OPTIMIZED_KERNELS ${OPTIMIZED_SIGNAL_KERNEL_DIR_PREFIX}/${OPTIMIZED_KERNEL_DIR})
  
  # 检查优化内核目录是否存在
  if(EXISTS ${PATH_TO_OPTIMIZED_KERNELS})
    message(STATUS "Using optimized kernels from: ${PATH_TO_OPTIMIZED_KERNELS}")
    
    # 配置 NMSIS-NN 优化内核（如果启用）
    configure_nmsis_nn()
    
    # 添加优化内核目录下的所有第三方内核源文件
    file(GLOB_RECURSE OPTIMIZED_THIRD_PARTY_KERNEL_SRCS 
      ${PATH_TO_OPTIMIZED_KERNELS}/*.cc
      ${PATH_TO_OPTIMIZED_KERNELS}/*.c
    )
    list(APPEND THIRD_PARTY_KERNEL_CC_SRCS ${OPTIMIZED_THIRD_PARTY_KERNEL_SRCS})
    message(STATUS "Added ${OPTIMIZED_KERNEL_DIR} third-party kernel sources: ${OPTIMIZED_THIRD_PARTY_KERNEL_SRCS}")
    
    # 使用Python脚本特化内核源文件（类似Makefile中的specialize_files.py）
    execute_process(
      COMMAND python3 ${MAKEFILE_DIR}/specialize_files.py --base_files "${MICROLITE_CC_KERNEL_SRCS}" --specialize_directory ${PATH_TO_OPTIMIZED_KERNELS}
      OUTPUT_VARIABLE SPECIALIZED_KERNEL_SRCS
      RESULT_VARIABLE SPECIALIZE_RESULT
      WORKING_DIRECTORY ${TENSORFLOW_ROOT}
    )
    
    if(SPECIALIZE_RESULT EQUAL 0)
      message(STATUS "SPECIALIZED_KERNEL_SRCS raw: ${SPECIALIZED_KERNEL_SRCS}")
      string(REPLACE "\n" " " SPECIALIZED_KERNEL_SRCS_CLEAN "${SPECIALIZED_KERNEL_SRCS}")
      string(REPLACE "\r" " " SPECIALIZED_KERNEL_SRCS_CLEAN "${SPECIALIZED_KERNEL_SRCS_CLEAN}")
      string(REPLACE "\t" " " SPECIALIZED_KERNEL_SRCS_CLEAN "${SPECIALIZED_KERNEL_SRCS_CLEAN}")
      string(REPLACE "  " " " SPECIALIZED_KERNEL_SRCS_CLEAN "${SPECIALIZED_KERNEL_SRCS_CLEAN}")
      string(REPLACE " " ";" MICROLITE_CC_KERNEL_SRCS "${SPECIALIZED_KERNEL_SRCS_CLEAN}")
      string(STRIP "${MICROLITE_CC_KERNEL_SRCS}" MICROLITE_CC_KERNEL_SRCS)
      message(STATUS "MICROLITE_CC_KERNEL_SRCS list: ${MICROLITE_CC_KERNEL_SRCS}")
    endif()
    
    # 添加优化内核头文件
    file(GLOB OPTIMIZED_KERNEL_HDRS ${PATH_TO_OPTIMIZED_KERNELS}/*.h)
    list(APPEND MICROLITE_CC_HDRS ${OPTIMIZED_KERNEL_HDRS})
    
    # 添加优化内核目录下的所有源文件
    file(GLOB OPTIMIZED_KERNEL_CC_SRCS ${PATH_TO_OPTIMIZED_KERNELS}/*.cc)
    file(GLOB OPTIMIZED_KERNEL_C_SRCS ${PATH_TO_OPTIMIZED_KERNELS}/*.c)
    file(GLOB OPTIMIZED_KERNEL_ASM_SRCS ${PATH_TO_OPTIMIZED_KERNELS}/*.S)
    list(APPEND MICROLITE_CC_KERNEL_SRCS 
      ${OPTIMIZED_KERNEL_CC_SRCS} 
      ${OPTIMIZED_KERNEL_C_SRCS} 
      ${OPTIMIZED_KERNEL_ASM_SRCS}
    )
    
    # 处理信号处理优化内核（针对xtensa等）
    if(OPTIMIZED_KERNEL_DIR STREQUAL "xtensa" AND EXISTS ${PATH_TO_SIGNAL_OPTIMIZED_KERNELS})
      execute_process(
        COMMAND python3 ${MAKEFILE_DIR}/specialize_files.py --base_files "${MICROLITE_CC_SIGNAL_KERNEL_SRCS}" --specialize_directory ${PATH_TO_SIGNAL_OPTIMIZED_KERNELS}
        OUTPUT_VARIABLE SPECIALIZED_SIGNAL_KERNEL_SRCS
        RESULT_VARIABLE SPECIALIZE_SIGNAL_RESULT
        WORKING_DIRECTORY ${TENSORFLOW_ROOT}
      )
      
      if(SPECIALIZE_SIGNAL_RESULT EQUAL 0)
        string(REPLACE " " ";" MICROLITE_CC_SIGNAL_KERNEL_SRCS ${SPECIALIZED_SIGNAL_KERNEL_SRCS})
        string(STRIP "${MICROLITE_CC_SIGNAL_KERNEL_SRCS}" MICROLITE_CC_SIGNAL_KERNEL_SRCS)
      endif()
      
      # 添加汇编文件和头文件
      file(GLOB SIGNAL_OPTIMIZED_ASM ${PATH_TO_SIGNAL_OPTIMIZED_KERNELS}/*.S)
      file(GLOB SIGNAL_OPTIMIZED_HDRS ${PATH_TO_SIGNAL_OPTIMIZED_KERNELS}/*.h)
      list(APPEND MICROLITE_CC_KERNEL_SRCS ${SIGNAL_OPTIMIZED_ASM})
      list(APPEND MICROLITE_CC_HDRS ${SIGNAL_OPTIMIZED_HDRS})
    endif()
  else()
    message(WARNING "OPTIMIZED_KERNEL_DIR specified but directory does not exist: ${PATH_TO_OPTIMIZED_KERNELS}")
  endif()
endif()

# 处理协处理器
if(CO_PROCESSOR)
  set(PATH_TO_COPROCESSOR_KERNELS ${TENSORFLOW_ROOT}tensorflow/lite/micro/kernels/${CO_PROCESSOR})
  
  if(EXISTS ${PATH_TO_COPROCESSOR_KERNELS})
    message(STATUS "Using co-processor kernels from: ${PATH_TO_COPROCESSOR_KERNELS}")
    
    execute_process(
      COMMAND python3 ${MAKEFILE_DIR}/specialize_files.py --base_files "${MICROLITE_CC_KERNEL_SRCS}" --specialize_directory ${PATH_TO_COPROCESSOR_KERNELS}
      OUTPUT_VARIABLE SPECIALIZED_COPROCESSOR_SRCS
      RESULT_VARIABLE SPECIALIZE_COPROCESSOR_RESULT
      WORKING_DIRECTORY ${TENSORFLOW_ROOT}
    )
    
    if(SPECIALIZE_COPROCESSOR_RESULT EQUAL 0)
      string(REPLACE " " ";" MICROLITE_CC_KERNEL_SRCS ${SPECIALIZED_COPROCESSOR_SRCS})
      string(STRIP "${MICROLITE_CC_KERNEL_SRCS}" MICROLITE_CC_KERNEL_SRCS)
    endif()
  else()
    message(WARNING "CO_PROCESSOR specified but directory does not exist: ${PATH_TO_COPROCESSOR_KERNELS}")
  endif()
endif()

# 处理目标特定的源文件
set(PATH_TO_TARGET_SRCS ${TENSORFLOW_ROOT}tensorflow/lite/micro/${CMAKE_SYSTEM_NAME})
if(EXISTS ${PATH_TO_TARGET_SRCS})
  execute_process(
    COMMAND python3 ${MAKEFILE_DIR}/specialize_files.py --base_files "${MICROLITE_CC_SRCS}" --specialize_directory ${PATH_TO_TARGET_SRCS}
    OUTPUT_VARIABLE SPECIALIZED_TARGET_SRCS
    RESULT_VARIABLE SPECIALIZE_TARGET_RESULT
    WORKING_DIRECTORY ${TENSORFLOW_ROOT}
  )
  
  if(SPECIALIZE_TARGET_RESULT EQUAL 0)
    string(REPLACE " " ";" MICROLITE_CC_SRCS ${SPECIALIZED_TARGET_SRCS})
    string(STRIP "${MICROLITE_CC_SRCS}" MICROLITE_CC_SRCS)
  endif()
endif()

# 添加第三方库头文件和源文件（类似Makefile中的THIRD_PARTY_CC_HDRS和THIRD_PARTY_CC_SRCS）
list(APPEND THIRD_PARTY_CC_HDRS
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/allocator.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/array.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/base.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/buffer.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/buffer_ref.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/code_generator.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/code_generators.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/default_allocator.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/detached_buffer.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/file_manager.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/flatbuffer_builder.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/flatbuffers.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/flex_flat_util.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/flexbuffers.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/grpc.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/hash.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/idl.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/minireflect.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/reflection.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/reflection_generated.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/registry.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/stl_emulation.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/string.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/struct.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/table.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/util.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/vector.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/vector_downward.h
  ${DOWNLOADS_DIR}/flatbuffers/include/flatbuffers/verifier.h
  ${DOWNLOADS_DIR}/gemmlowp/fixedpoint/fixedpoint.h
  ${DOWNLOADS_DIR}/gemmlowp/fixedpoint/fixedpoint_neon.h
  ${DOWNLOADS_DIR}/gemmlowp/fixedpoint/fixedpoint_sse.h
  ${DOWNLOADS_DIR}/gemmlowp/internal/detect_platform.h
  ${DOWNLOADS_DIR}/gemmlowp/LICENSE
  ${DOWNLOADS_DIR}/kissfft/COPYING
  ${DOWNLOADS_DIR}/kissfft/kiss_fft.c
  ${DOWNLOADS_DIR}/kissfft/kiss_fft.h
  ${DOWNLOADS_DIR}/kissfft/_kiss_fft_guts.h
  ${DOWNLOADS_DIR}/kissfft/tools/kiss_fftr.c
  ${DOWNLOADS_DIR}/kissfft/tools/kiss_fftr.h
  ${DOWNLOADS_DIR}/ruy/ruy/profiler/instrumentation.h
)

# 确保变量在父作用域可见
set(THIRD_PARTY_CC_HDRS ${THIRD_PARTY_CC_HDRS} PARENT_SCOPE)
set(THIRD_PARTY_KERNEL_CC_SRCS ${THIRD_PARTY_KERNEL_CC_SRCS} PARENT_SCOPE)
set(MICROLITE_CC_KERNEL_SRCS ${MICROLITE_CC_KERNEL_SRCS} PARENT_SCOPE)
set(MICROLITE_CC_HDRS ${MICROLITE_CC_HDRS} PARENT_SCOPE)
set(MICROLITE_CC_SRCS ${MICROLITE_CC_SRCS} PARENT_SCOPE)
set(MICROLITE_LIBS ${MICROLITE_LIBS} PARENT_SCOPE)
set(INCLUDES ${INCLUDES} PARENT_SCOPE)