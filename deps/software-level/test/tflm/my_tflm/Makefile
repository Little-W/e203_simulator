# Makefile for TensorFlow Lite Micro

# TFLM 顶层目录
TENSORFLOW_ROOT := $(shell pwd)/tflite-micro/

RELATIVE_MAKEFILE_DIR := tensorflow/lite/micro/tools/make
MAKEFILE_DIR := $(TENSORFLOW_ROOT)$(RELATIVE_MAKEFILE_DIR)

# 下载目录：存放下载的第三方库
DOWNLOADS_DIR := $(MAKEFILE_DIR)/downloads

# 构建目录：存放所有构建产物
BUILD_DIR := build

# 生成目录：存放生成的代码
GENERATED_SUBDIR := gen
GENERATED_DIR := $(BUILD_DIR)/$(GENERATED_SUBDIR)

# 公共头文件目录列表
PUBLIC_INCLUDES := \
  -I$(TENSORFLOW_ROOT) \
  -I$(GENERATED_DIR) \
  -I$(DOWNLOADS_DIR)/flatbuffers/include \
  -I$(DOWNLOADS_DIR)/gemmlowp

# 头文件目录列表
INCLUDES := \
  -I$(DOWNLOADS_DIR) \
  -I$(DOWNLOADS_DIR)/gemmlowp \
  -I$(DOWNLOADS_DIR)/flatbuffers/include \
  -I$(DOWNLOADS_DIR)/kissfft \
  -I$(DOWNLOADS_DIR)/ruy \
  $(PUBLIC_INCLUDES)

# 编译警告相关选项
CC_WARNINGS := \
  -Wsign-compare \
  -Wdouble-promotion \
  -Wunused-variable \
  -Wunused-function \
  -Wswitch \
  -Wvla \
  -Wall \
  -Wextra \
  -Wmissing-field-initializers \
  -Wstrict-aliasing \
  -Wno-unused-parameter \
  -Wno-return-type

# 检查编译器类型，非GNU/Clang编译器添加-Wshadow
# 注意：由于TensorFlow Lite Micro代码中存在shadow警告，暂时禁用此选项
# CC_COMPILER := $(shell $(CC) --version 2>/dev/null | head -n1)
# ifeq ($(findstring gcc,$(CC_COMPILER)),)
# ifeq ($(findstring clang,$(CC_COMPILER)),)
#   CC_WARNINGS += -Wshadow
# endif
# endif

# C/C++通用编译选项
COMMON_FLAGS := \
  -Werror \
  -fno-unwind-tables \
  -ffunction-sections \
  -fdata-sections \
  -fmessage-length=0 \
  -DTF_LITE_DISABLE_X86_NEON

# C++ 编译选项
CXXFLAGS := \
  -std=c++17 \
  -fno-rtti \
  -fno-exceptions \
  -fno-threadsafe-statics \
  -Wnon-virtual-dtor \
  $(COMMON_FLAGS) \
  $(CC_WARNINGS) \
  $(INCLUDES)

# C 编译选项
CCFLAGS := \
  -Wimplicit-function-declaration \
  -std=c17 \
  $(COMMON_FLAGS) \
  $(CC_WARNINGS) \
  $(INCLUDES)

# Release构建添加优化选项
ifeq ($(BUILD_TYPE),Release)
  CXXFLAGS += -DNDEBUG -DTF_LITE_STRIP_ERROR_STRINGS
  CCFLAGS += -DNDEBUG -DTF_LITE_STRIP_ERROR_STRINGS
endif

# MICROLITE_BENCHMARK_SRCS
MICROLITE_BENCHMARK_SRCS := \
  $(wildcard $(TENSORFLOW_ROOT)tensorflow/lite/micro/benchmarks/*benchmark.cc) \
  $(wildcard $(TENSORFLOW_ROOT)tensorflow/lite/micro/tools/benchmarking/*benchmark.cc)

# MICROLITE_TEST_SRCS
MICROLITE_TEST_SRCS := \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/fake_micro_context_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/flatbuffer_utils_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/hexdump_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/memory_arena_threshold_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/memory_helpers_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_allocator_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_allocation_info_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_interpreter_context_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_log_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_interpreter_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_mutable_op_resolver_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_resource_variable_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_time_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/micro_utils_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/recording_micro_allocator_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/span_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/static_vector_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/arena_allocator/non_persistent_arena_buffer_allocator_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/arena_allocator/persistent_arena_buffer_allocator_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/arena_allocator/recording_single_arena_buffer_allocator_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/arena_allocator/single_arena_buffer_allocator_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/testing_helpers_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/memory_planner/greedy_memory_planner_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/memory_planner/linear_memory_planner_test.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/memory_planner/non_persistent_buffer_planner_shim_test.cc

# MICROLITE_CC_KERNEL_SRCS
MICROLITE_CC_KERNEL_SRCS := \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/activations.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/activations_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/add.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/add_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/add_n.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/arg_min_max.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/assign_variable.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/batch_matmul.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/batch_matmul_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/batch_to_space_nd.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/broadcast_args.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/broadcast_to.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/call_once.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/cast.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/ceil.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/circular_buffer.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/circular_buffer_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/comparisons.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/concatenation.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/conv.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/conv_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/cumsum.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/decompress.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/decompress_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/depth_to_space.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/depthwise_conv.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/depthwise_conv_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/dequantize.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/dequantize_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/detection_postprocess.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/div.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/elementwise.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/elu.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/embedding_lookup.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/ethosu.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/exp.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/expand_dims.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/fill.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/floor.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/floor_div.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/floor_mod.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/fully_connected.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/fully_connected_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/gather.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/gather_nd.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/hard_swish.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/hard_swish_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/if.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/kernel_runner.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/kernel_util.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/l2norm.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/l2_pool_2d.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/leaky_relu.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/leaky_relu_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/logical.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/logical_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/logistic.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/logistic_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/log_softmax.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/lstm_eval.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/lstm_eval_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/maximum_minimum.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/micro_tensor_utils.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/mirror_pad.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/mul.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/mul_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/neg.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/pack.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/pad.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/pad_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/pooling.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/pooling_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/prelu.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/prelu_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/quantize.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/quantize_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/read_variable.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/reduce.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/reduce_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/reshape.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/reshape_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/resize_bilinear.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/resize_nearest_neighbor.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/round.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/select.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/shape.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/slice.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/softmax.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/softmax_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/space_to_batch_nd.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/space_to_depth.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/split.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/split_v.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/squared_difference.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/squeeze.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/strided_slice.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/strided_slice_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/sub.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/sub_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/svdf.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/svdf_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/tanh.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/transpose.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/transpose_common.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/transpose_conv.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/unidirectional_sequence_lstm.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/unpack.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/var_handle.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/while.cc \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/kernels/zeros_like.cc

# MICROLITE_CC_SIGNAL_KERNEL_SRCS
MICROLITE_CC_SIGNAL_KERNEL_SRCS := \
  $(TENSORFLOW_ROOT)signal/src/kiss_fft_wrappers/kiss_fft_float.cc \
  $(TENSORFLOW_ROOT)signal/src/kiss_fft_wrappers/kiss_fft_int16.cc \
  $(TENSORFLOW_ROOT)signal/src/kiss_fft_wrappers/kiss_fft_int32.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/delay.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/energy.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/fft_auto_scale_kernel.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/fft_auto_scale_common.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/filter_bank.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/filter_bank_log.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/filter_bank_square_root.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/filter_bank_square_root_common.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/filter_bank_spectral_subtraction.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/framer.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/irfft.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/rfft.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/stacker.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/overlap_add.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/pcan.cc \
  $(TENSORFLOW_ROOT)signal/micro/kernels/window.cc \
  $(TENSORFLOW_ROOT)signal/src/circular_buffer.cc \
  $(TENSORFLOW_ROOT)signal/src/energy.cc \
  $(TENSORFLOW_ROOT)signal/src/fft_auto_scale.cc \
  $(TENSORFLOW_ROOT)signal/src/filter_bank.cc \
  $(TENSORFLOW_ROOT)signal/src/filter_bank_log.cc \
  $(TENSORFLOW_ROOT)signal/src/filter_bank_square_root.cc \
  $(TENSORFLOW_ROOT)signal/src/filter_bank_spectral_subtraction.cc \
  $(TENSORFLOW_ROOT)signal/src/irfft_float.cc \
  $(TENSORFLOW_ROOT)signal/src/irfft_int16.cc \
  $(TENSORFLOW_ROOT)signal/src/irfft_int32.cc \
  $(TENSORFLOW_ROOT)signal/src/log.cc \
  $(TENSORFLOW_ROOT)signal/src/max_abs.cc \
  $(TENSORFLOW_ROOT)signal/src/msb_32.cc \
  $(TENSORFLOW_ROOT)signal/src/msb_64.cc \
  $(TENSORFLOW_ROOT)signal/src/overlap_add.cc \
  $(TENSORFLOW_ROOT)signal/src/pcan_argc_fixed.cc \
  $(TENSORFLOW_ROOT)signal/src/rfft_float.cc \
  $(TENSORFLOW_ROOT)signal/src/rfft_int16.cc \
  $(TENSORFLOW_ROOT)signal/src/rfft_int32.cc \
  $(TENSORFLOW_ROOT)signal/src/square_root_32.cc \
  $(TENSORFLOW_ROOT)signal/src/square_root_64.cc \
  $(TENSORFLOW_ROOT)signal/src/window.cc

# TFL_CC_SRCS - 递归查找所有.cc和.c文件，排除experimental和micro目录
TFL_CC_SRCS := $(shell find $(TENSORFLOW_ROOT)tensorflow -name "*.cc" -o -name "*.c" | grep -v "/experimental/" | grep -v "/micro/")

# MICROLITE_CC_BASE_SRCS
MICROLITE_CC_BASE_SRCS := \
  $(wildcard $(TENSORFLOW_ROOT)tensorflow/lite/micro/*.cc) \
  $(wildcard $(TENSORFLOW_ROOT)tensorflow/lite/micro/arena_allocator/*.cc) \
  $(wildcard $(TENSORFLOW_ROOT)tensorflow/lite/micro/memory_planner/*.cc) \
  $(wildcard $(TENSORFLOW_ROOT)tensorflow/lite/micro/tflite_bridge/*.cc) \
  $(TFL_CC_SRCS)

# MICROLITE_CC_SRCS - 排除测试和基准测试文件
MICROLITE_CC_SRCS := $(filter-out $(MICROLITE_TEST_SRCS), $(MICROLITE_CC_BASE_SRCS))
MICROLITE_CC_SRCS := $(filter-out $(MICROLITE_BENCHMARK_SRCS), $(MICROLITE_CC_SRCS))

# 添加信号处理内核源文件
MICROLITE_CC_KERNEL_SRCS += $(MICROLITE_CC_SIGNAL_KERNEL_SRCS)

# TFLM 库文件名
MICROLITE_LIB_NAME := $(BUILD_DIR)/libtflite-micro.a

# 生成目标文件列表 - 将目标文件放到build目录中
MICROLITE_OBJS := $(patsubst %.cc,$(BUILD_DIR)/%.o,$(MICROLITE_CC_SRCS))
MICROLITE_OBJS += $(patsubst %.c,$(BUILD_DIR)/%.o,$(filter %.c,$(MICROLITE_CC_SRCS)))
MICROLITE_KERNEL_OBJS := $(patsubst %.cc,$(BUILD_DIR)/%.o,$(MICROLITE_CC_KERNEL_SRCS))

# 默认目标
all: $(MICROLITE_LIB_NAME) keyword_benchmark person_detection_benchmark

# 生成数据文件目标
generate_all_data: $(KEYWORD_BENCHMARK_GENERATED) $(PERSON_DETECTION_GENERATED)

# 创建生成目录
$(GENERATED_DIR):
	mkdir -p $@

# 创建构建目录结构
$(BUILD_DIR):
	mkdir -p $@

# 编译C++源文件到build目录
$(BUILD_DIR)/%.o: %.cc | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# 编译C源文件到build目录
$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CCFLAGS) -c $< -o $@

# 创建TFLM静态库
$(MICROLITE_LIB_NAME): $(MICROLITE_OBJS) $(MICROLITE_KERNEL_OBJS) | $(BUILD_DIR)
	ar rcs $@ $^

# 数据生成函数
define generate_cc_array
	@echo "Generating C++ for: $(1)..."
	@mkdir -p $(dir $(2))
	cd $(TENSORFLOW_ROOT) && python3 tensorflow/lite/micro/tools/generate_cc_arrays.py ../$(BUILD_DIR)/$(GENERATED_SUBDIR) $(3)
endef

# Keyword Benchmark
KEYWORD_BENCHMARK_SRCS := $(TENSORFLOW_ROOT)tensorflow/lite/micro/benchmarks/keyword_benchmark.cc
KEYWORD_BENCHMARK_INPUTS := $(TENSORFLOW_ROOT)tensorflow/lite/micro/models/keyword_scrambled.tflite
KEYWORD_BENCHMARK_GENERATED := $(GENERATED_DIR)/tensorflow/lite/micro/models/keyword_scrambled_model_data.cc

$(KEYWORD_BENCHMARK_GENERATED): $(KEYWORD_BENCHMARK_INPUTS) | $(GENERATED_DIR)
	$(call generate_cc_array,$<,$@,tensorflow/lite/micro/models/keyword_scrambled.tflite)

# 编译基准测试为目标文件
$(BUILD_DIR)/keyword_benchmark.o: $(KEYWORD_BENCHMARK_SRCS) $(KEYWORD_BENCHMARK_GENERATED) | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -Dmain=keyword_benchmark_main -c $(KEYWORD_BENCHMARK_SRCS) -o $@

$(BUILD_DIR)/keyword_benchmark_data.o: $(KEYWORD_BENCHMARK_GENERATED) | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $(KEYWORD_BENCHMARK_GENERATED) -o $@

keyword_benchmark: $(MICROLITE_LIB_NAME) $(BUILD_DIR)/keyword_benchmark.o $(BUILD_DIR)/keyword_benchmark_data.o | $(BUILD_DIR)
	$(CXX) $(BUILD_DIR)/keyword_benchmark.o $(BUILD_DIR)/keyword_benchmark_data.o -L$(BUILD_DIR) -ltflite-micro -o $(BUILD_DIR)/$@

# Person Detection Benchmark
PERSON_DETECTION_BENCHMARK_SRCS := $(TENSORFLOW_ROOT)tensorflow/lite/micro/benchmarks/person_detection_benchmark.cc
PERSON_DETECTION_BENCHMARK_INPUTS := \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/examples/person_detection/testdata/person.bmp \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/examples/person_detection/testdata/no_person.bmp \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/models/person_detect.tflite

PERSON_DETECTION_GENERATED := \
  $(GENERATED_DIR)/tensorflow/lite/micro/examples/person_detection/testdata/person_image_data.cc \
  $(GENERATED_DIR)/tensorflow/lite/micro/examples/person_detection/testdata/no_person_image_data.cc \
  $(GENERATED_DIR)/tensorflow/lite/micro/models/person_detect_model_data.cc

$(GENERATED_DIR)/tensorflow/lite/micro/examples/person_detection/testdata/person_image_data.cc: $(TENSORFLOW_ROOT)tensorflow/lite/micro/examples/person_detection/testdata/person.bmp | $(GENERATED_DIR)
	$(call generate_cc_array,$<,$@,tensorflow/lite/micro/examples/person_detection/testdata/person.bmp)

$(GENERATED_DIR)/tensorflow/lite/micro/examples/person_detection/testdata/no_person_image_data.cc: $(TENSORFLOW_ROOT)tensorflow/lite/micro/examples/person_detection/testdata/no_person.bmp | $(GENERATED_DIR)
	$(call generate_cc_array,$<,$@,tensorflow/lite/micro/examples/person_detection/testdata/no_person.bmp)

$(GENERATED_DIR)/tensorflow/lite/micro/models/person_detect_model_data.cc: $(TENSORFLOW_ROOT)tensorflow/lite/micro/models/person_detect.tflite | $(GENERATED_DIR)
	$(call generate_cc_array,$<,$@,tensorflow/lite/micro/models/person_detect.tflite)

# 确保生成文件的依赖关系
.PHONY: generate_data
generate_data: $(KEYWORD_BENCHMARK_GENERATED) $(PERSON_DETECTION_GENERATED)

person_detection_benchmark: $(MICROLITE_LIB_NAME) $(PERSON_DETECTION_GENERATED) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -Dmain=person_detection_benchmark_main $(PERSON_DETECTION_BENCHMARK_SRCS) $(PERSON_DETECTION_GENERATED) -L$(BUILD_DIR) -ltflite-micro -o $(BUILD_DIR)/$@

# 清理目标
clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean generate_data generate_all_data