# Copyright 2025 TensorFlow Lite Micro CMake Utilities
# 
# This file contains utility functions for building TensorFlow Lite Micro
# projects with CMake, adapted from the original Makefile system.

#==============================================================================
# microlite_test: Create test/benchmark static library targets with data file generation
#
# This function creates a static library target that includes generated C++ arrays
# from input data files (.tflite, .wav, .bmp, .csv, .npy). The generated library
# can be linked with other targets for testing or benchmarking purposes.
#
# Arguments:
#   NAME   - Name of the target library
#   SRCS   - List of C/C++ source files
#   HDRS   - List of C/C++ header files
#   INPUTS - List of input data files to convert to C++ arrays
#
# Generated files are placed in: ${GENERATED_DIR}/<relative_path>/<basename><suffix>.cc
#   .tflite -> _model_data.cc
#   .bmp    -> _image_data.cc
#   .wav    -> _audio_data.cc
#   .csv/.npy -> _test_data.cc
#==============================================================================
function(microlite_test NAME SRCS HDRS INPUTS)
  set(${NAME}_LOCAL_SRCS ${SRCS} ${HDRS})
  set(${NAME}_GENERATED_SRCS)
  set(${NAME}_GENERATE_TARGETS)

  message(STATUS "Creating microlite test target: ${NAME}")
  message(STATUS "  Source files: ${${NAME}_LOCAL_SRCS}")

  # 处理每个输入文件，生成对应的C++数组代码
  foreach(INPUT ${INPUTS})
    message(STATUS "  Processing input file: ${INPUT}")

    # 获取文件信息
    get_filename_component(INPUT_NAME ${INPUT} NAME)
    get_filename_component(INPUT_BASE ${INPUT} NAME_WE)
    file(RELATIVE_PATH INPUT_RELPATH ${TENSORFLOW_ROOT} ${INPUT})
    get_filename_component(INPUT_SUBDIR ${INPUT_RELPATH} DIRECTORY)

    # 根据文件扩展名确定输出后缀
    if (INPUT_NAME MATCHES "\\.tflite$")
      set(OUTPUT_NAME_EXT "_model_data")
    elseif (INPUT_NAME MATCHES "\\.bmp$")
      set(OUTPUT_NAME_EXT "_image_data")
    elseif (INPUT_NAME MATCHES "\\.wav$")
      set(OUTPUT_NAME_EXT "_audio_data")
    elseif (INPUT_NAME MATCHES "\\.(csv|npy)$")
      set(OUTPUT_NAME_EXT "_test_data")
    else()
      message(WARNING "Unknown file extension for ${INPUT_NAME}, using _data suffix")
      set(OUTPUT_NAME_EXT "_data")
    endif()

    # 生成的C++源文件路径
    set(GENERATED_SRC_PATH ${GENERATED_DIR}/${INPUT_SUBDIR}/${INPUT_BASE}${OUTPUT_NAME_EXT}.cc)
    message(STATUS "  Generated file: ${GENERATED_SRC_PATH}")

    # 添加自定义命令生成C++数组文件
    add_custom_command(
      OUTPUT ${GENERATED_SRC_PATH}
      COMMAND python3 ${TENSORFLOW_ROOT}tensorflow/lite/micro/tools/generate_cc_arrays.py 
              ${GENERATED_SUBDIR} ${INPUT_RELPATH}
      WORKING_DIRECTORY ${TENSORFLOW_ROOT}
      DEPENDS ${INPUT}
      COMMENT "Generating C++ array from ${INPUT_NAME}"
      VERBATIM
    )

    list(APPEND ${NAME}_GENERATED_SRCS ${GENERATED_SRC_PATH})

    # 创建代码生成目标
    set(GENERATE_TARGET_NAME ${NAME}_CODEGEN_${INPUT_BASE})
    add_custom_target(${GENERATE_TARGET_NAME} DEPENDS ${GENERATED_SRC_PATH})
    list(APPEND ${NAME}_GENERATE_TARGETS ${GENERATE_TARGET_NAME})
  endforeach()

  message(STATUS "  Generated sources: ${${NAME}_GENERATED_SRCS}")

  # 创建静态库目标
  add_library(${NAME} STATIC
    ${${NAME}_LOCAL_SRCS}
    ${${NAME}_GENERATED_SRCS}
  )

  # 设置依赖关系
  add_dependencies(${NAME} ${${NAME}_GENERATE_TARGETS})

  # 配置目标属性
  target_compile_definitions(${NAME} PRIVATE -Dmain=${NAME}_main)
  
  target_include_directories(${NAME}
    PRIVATE ${INCLUDES}
    PUBLIC ${PUBLIC_INCLUDES}
  )
  
  # 为测试目标设置更宽松的编译选项
  set(TEST_CXXFLAGS ${CXXFLAGS})
  set(TEST_CCFLAGS ${CCFLAGS})
  set(TEST_WARNINGS ${CC_WARNINGS})
  
  # 移除可能导致基准测试失败的严格编译选项
  list(REMOVE_ITEM TEST_CXXFLAGS -Werror)
  list(REMOVE_ITEM TEST_CCFLAGS -Werror)
  list(REMOVE_ITEM TEST_WARNINGS -Werror)
  
  # 添加针对测试代码的警告抑制选项
  list(APPEND TEST_WARNINGS -Wno-return-type -Wno-unused-parameter -Wno-unused-variable)
  
  target_compile_options(${NAME}
    PRIVATE $<$<COMPILE_LANGUAGE:CXX>:${TEST_CXXFLAGS}>
    PRIVATE $<$<COMPILE_LANGUAGE:C>:${TEST_CCFLAGS}>
    PRIVATE ${TEST_WARNINGS}
  )
  
  set_target_properties(${NAME} PROPERTIES CXX_STANDARD 17)
  
  # 链接TFLM库
  target_link_libraries(${NAME} ${MICROLITE_LIB_NAME})
  
  message(STATUS "Microlite test target '${NAME}' created successfully")
endfunction()

#==============================================================================
# microlite_executable: Create executable targets with data file generation
#
# This function creates an executable target that includes generated C++ arrays
# from input data files. Similar to microlite_test but creates an executable
# instead of a static library.
#
# Arguments:
#   NAME   - Name of the target executable
#   SRCS   - List of C/C++ source files
#   HDRS   - List of C/C++ header files
#   INPUTS - List of input data files to convert to C++ arrays
#
# Generated files are placed in: ${GENERATED_DIR}/<relative_path>/<basename><suffix>.cc
#==============================================================================
function(microlite_executable NAME SRCS HDRS INPUTS)
  set(${NAME}_LOCAL_SRCS ${SRCS} ${HDRS})
  set(${NAME}_GENERATED_SRCS)
  set(${NAME}_GENERATE_TARGETS)

  message(STATUS "Creating microlite executable target: ${NAME}")
  message(STATUS "  Source files: ${${NAME}_LOCAL_SRCS}")

  # 处理每个输入文件，生成对应的C++数组代码
  foreach(INPUT ${INPUTS})
    message(STATUS "  Processing input file: ${INPUT}")

    # 获取文件信息
    get_filename_component(INPUT_NAME ${INPUT} NAME)
    get_filename_component(INPUT_BASE ${INPUT} NAME_WE)
    file(RELATIVE_PATH INPUT_RELPATH ${TENSORFLOW_ROOT} ${INPUT})
    get_filename_component(INPUT_SUBDIR ${INPUT_RELPATH} DIRECTORY)

    # 根据文件扩展名确定输出后缀
    if (INPUT_NAME MATCHES "\\.tflite$")
      set(OUTPUT_NAME_EXT "_model_data")
    elseif (INPUT_NAME MATCHES "\\.bmp$")
      set(OUTPUT_NAME_EXT "_image_data")
    elseif (INPUT_NAME MATCHES "\\.wav$")
      set(OUTPUT_NAME_EXT "_audio_data")
    elseif (INPUT_NAME MATCHES "\\.(csv|npy)$")
      set(OUTPUT_NAME_EXT "_test_data")
    else()
      message(WARNING "Unknown file extension for ${INPUT_NAME}, using _data suffix")
      set(OUTPUT_NAME_EXT "_data")
    endif()

    # 生成的C++源文件路径
    set(GENERATED_SRC_PATH ${GENERATED_DIR}/${INPUT_SUBDIR}/${INPUT_BASE}${OUTPUT_NAME_EXT}.cc)
    message(STATUS "  Generated file: ${GENERATED_SRC_PATH}")

    # 添加自定义命令生成C++数组文件
    add_custom_command(
      OUTPUT ${GENERATED_SRC_PATH}
      COMMAND python3 ${TENSORFLOW_ROOT}tensorflow/lite/micro/tools/generate_cc_arrays.py 
              ${GENERATED_SUBDIR} ${INPUT_RELPATH}
      WORKING_DIRECTORY ${TENSORFLOW_ROOT}
      DEPENDS ${INPUT}
      COMMENT "Generating C++ array from ${INPUT_NAME}"
      VERBATIM
    )

    list(APPEND ${NAME}_GENERATED_SRCS ${GENERATED_SRC_PATH})

    # 创建代码生成目标
    set(GENERATE_TARGET_NAME ${NAME}_CODEGEN_${INPUT_BASE})
    add_custom_target(${GENERATE_TARGET_NAME} DEPENDS ${GENERATED_SRC_PATH})
    list(APPEND ${NAME}_GENERATE_TARGETS ${GENERATE_TARGET_NAME})
  endforeach()

  message(STATUS "  Generated sources: ${${NAME}_GENERATED_SRCS}")

  # 创建可执行目标
  add_executable(${NAME}
    ${${NAME}_LOCAL_SRCS}
    ${${NAME}_GENERATED_SRCS}
  )

  # 设置依赖关系
  add_dependencies(${NAME} ${${NAME}_GENERATE_TARGETS})

  # 配置目标属性
  target_include_directories(${NAME}
    PRIVATE ${INCLUDES}
    PUBLIC ${PUBLIC_INCLUDES}
  )
  
  target_compile_options(${NAME}
    PRIVATE $<$<COMPILE_LANGUAGE:CXX>:${CXXFLAGS}>
    PRIVATE $<$<COMPILE_LANGUAGE:C>:${CCFLAGS}>
    PRIVATE ${CC_WARNINGS}
  )
  
  set_target_properties(${NAME} PROPERTIES CXX_STANDARD 17)
  
  # 链接TFLM库
  target_link_libraries(${NAME} ${MICROLITE_LIB_NAME})
  
  message(STATUS "Microlite executable target '${NAME}' created successfully")
endfunction()