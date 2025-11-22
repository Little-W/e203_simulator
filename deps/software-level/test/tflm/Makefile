SRCDIRS = ${TFLM_DIR}/src src
INCDIRS = ${TFLM_DIR}/inc ${TFLM_DIR}/my_tflm/tflite-micro inc
LIBDIRS = ${TFLM_DIR}/my_tflm/build
LDLIBS = -lm \
		-lperson_detection_benchmark \
		-lmy_model \
		-lkeyword_benchmark \
	 	-lperson_detection_test \
    	-ltflite-micro 

EXT_LDFLAGS :=  -u _isatty -u _open -u _write -u _sbrk -u _read -u _close -u _fstat -u _lseek -u errno -u __unorddf2 \
 -u __errno -u __dso_handle -u _kill -u _getpid -u __unordsf2 -u __addsf3 -u __ltsf2 -u __eqsf2 -u puts
 
COMMON_FLAGS := -O0
# COMMON_FLAGS := -O3 -funroll-loops -fpeel-loops -fgcse-sm -fgcse-las
# Optimize just for code size
#COMMON_FLAGS := -Os -flto
COMMON_FLAGS += -DMY_MODEL_TEST -DUSE_SIM_FREQ

include $(SIM_ROOT_DIR)/make.conf
TARGET = tflm
# PFLOAT = 1
include $(SOFTWARE_MAKEFILES_DIR)/Makefile

