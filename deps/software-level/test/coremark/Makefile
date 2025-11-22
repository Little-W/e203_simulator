USE_OPEN_GNU_GCC = 0
SRCDIRS = ${COREMARK_DIR} src
INCDIRS = ${COREMARK_DIR} inc

COMMON_FLAGS := -O1 -flto -funroll-all-loops -finline-limit=600 -ftree-dominator-opts -fno-if-conversion2 -fselective-scheduling -fno-code-hoisting -fno-common -funroll-loops -finline-functions -falign-functions=4 -falign-jumps=4 -falign-loops=4
#COMMON_FLAGS := -O3 -funroll-loops -fpeel-loops -fgcse-sm -fgcse-las
# Optimize just for code size
#COMMON_FLAGS := -Os -flto

COMMON_FLAGS += -DFLAGS_STR=\""$(COMMON_FLAGS)"\"
COMMON_FLAGS += -DITERATIONS=100 -DPERFORMANCE_RUN=1

include $(SIM_ROOT_DIR)/make.conf
TARGET = coremark
PFLOAT = 1
include $(SOFTWARE_MAKEFILES_DIR)/Makefile

