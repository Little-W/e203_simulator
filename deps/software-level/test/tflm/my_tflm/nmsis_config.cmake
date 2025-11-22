# nmsis_config.cmake
# 专门处理 NMSIS 和 NMSIS-NN 相关配置

# 处理 NMSIS-NN 优化内核
function(configure_nmsis_nn)
    if(NOT OPTIMIZED_KERNEL_DIR STREQUAL "nmsis_nn")
        return()
    endif()
    
    message(STATUS "Configuring NMSIS-NN optimization...")
    
    # 设置 NMSIS 和 NMSIS-NN 路径（兼容通用 架构 构建）
    set(NMSIS_DEFAULT_DOWNLOAD_PATH ${DOWNLOADS_DIR}/nmsis)
    set(NMSIS_PATH ${NMSIS_DEFAULT_DOWNLOAD_PATH})
    set(NMSIS_NN_DEFAULT_DOWNLOAD_PATH ${DOWNLOADS_DIR}/nmsis/NN)
    set(NMSIS_NN_PATH ${NMSIS_NN_DEFAULT_DOWNLOAD_PATH})
    
    # 默认排除 DSP，只有显式开启才包含 DSP 相关头文件/源文件
    set(USE_NMSIS_DSP OFF CACHE BOOL "Enable NMSIS DSP headers/sources (default OFF)")
    if(USE_NMSIS_DSP AND EXISTS ${NMSIS_PATH}/DSP)
        file(GLOB_RECURSE NMSIS_DSP_HEADERS ${NMSIS_PATH}/DSP/Include/*.h)
        list(APPEND THIRD_PARTY_CC_HDRS ${NMSIS_DSP_HEADERS})
        file(GLOB_RECURSE NMSIS_DSP_SOURCES ${NMSIS_PATH}/DSP/Source/*.c)
        list(APPEND THIRD_PARTY_KERNEL_CC_SRCS ${NMSIS_DSP_SOURCES})
        list(APPEND INCLUDES ${NMSIS_PATH}/DSP/Include)
        set(NMSIS_HAS_DSP TRUE)
    else()
        if(EXISTS ${NMSIS_PATH}/DSP)
            message(STATUS "NMSIS DSP detected at ${NMSIS_PATH}/DSP but skipped (USE_NMSIS_DSP is OFF).")
        endif()
    endif()
    
    # 添加 NMSIS-NN 源文件（如果没有预编译库）
    if(NOT NMSIS_NN_LIBS)
        file(GLOB_RECURSE NMSIS_NN_SOURCES ${NMSIS_NN_PATH}/Source/*.c)
        list(APPEND THIRD_PARTY_KERNEL_CC_SRCS ${NMSIS_NN_SOURCES})
        message(STATUS "Added NMSIS-NN source files from: ${NMSIS_NN_PATH}/Source")
    else()
        # 如果有预编译库，添加到链接库中
        list(APPEND MICROLITE_LIBS ${NMSIS_NN_LIBS})
        message(STATUS "Using pre-compiled NMSIS-NN libraries: ${NMSIS_NN_LIBS}")
        set(MICROLITE_LIBS ${MICROLITE_LIBS} PARENT_SCOPE)
    endif()
    
    # 添加 NMSIS-NN 头文件
    file(GLOB_RECURSE NMSIS_NN_HEADERS ${NMSIS_NN_PATH}/Include/*.h)
    list(APPEND THIRD_PARTY_CC_HDRS ${NMSIS_NN_HEADERS})
    
    # 添加 NMSIS Core 头文件（所有编译器特定实现）
    # 注意：目录结构为 nmsis/Core/Include
    file(GLOB NMSIS_CORE_HEADERS ${NMSIS_PATH}/Core/Include/*.h)
    list(APPEND THIRD_PARTY_CC_HDRS ${NMSIS_CORE_HEADERS})
    
    # 添加许可证文件
    list(APPEND THIRD_PARTY_CC_HDRS 
        ${NMSIS_PATH}/LICENSE
        ${NMSIS_NN_PATH}/LICENSE
    )
    
    # 添加包含目录（类似 Makefile 中的 INCLUDES）
    list(APPEND INCLUDES 
        ${NMSIS_PATH}
        ${NMSIS_NN_PATH}
        ${NMSIS_PATH}/Core/Include
        ${NMSIS_NN_PATH}/Include
    )
    
    # 可选：添加 RISC-V 设备特定的包含目录（如果定义了 RISCV_CPU）
    if(RISCV_CPU)
        list(APPEND INCLUDES 
            ${NMSIS_PATH}/RISC-V/Device/${RISCV_CPU}/Include
        )
    endif()
    
    message(STATUS "NMSIS-NN configuration:")
    message(STATUS "  NMSIS_PATH: ${NMSIS_PATH}")
    message(STATUS "  NMSIS_NN_PATH: ${NMSIS_NN_PATH}")
    message(STATUS "  NMSIS-NN headers: ${NMSIS_NN_HEADERS}")
    if(NMSIS_HAS_DSP)
        message(STATUS "  DSP detected: ${NMSIS_PATH}/DSP (headers/sources added)")
    endif()
    if(EXISTS ${NMSIS_PATH}/Core)
        message(STATUS "  Core detected: ${NMSIS_PATH}/Core")
    endif()
    if(EXISTS ${NMSIS_PATH}/NN)
        message(STATUS "  NN detected: ${NMSIS_PATH}/NN")
    endif()
    
    # 将变量传递到父作用域
    set(THIRD_PARTY_CC_HDRS ${THIRD_PARTY_CC_HDRS} PARENT_SCOPE)
    set(THIRD_PARTY_KERNEL_CC_SRCS ${THIRD_PARTY_KERNEL_CC_SRCS} PARENT_SCOPE)
    set(INCLUDES ${INCLUDES} PARENT_SCOPE)
endfunction()