
include $(SIM_ROOT_DIR)/make.conf
TARGET = coremark
PFLOAT = 1

SRCDIRS = ${COREMARK_DIR} src
INCDIRS = ${COREMARK_DIR} inc

include $(SOTFWARE_MAKEFILES_DIR)/gmsl/gmsl
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.misc
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.conf
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.rules


#COMMON_FLAGS += -flto -funroll-all-loops -finline-limit=600 -ftree-dominator-opts -fno-if-conversion2 -fselective-scheduling -fno-code-hoisting -fno-common -funroll-loops -finline-functions -falign-functions=4 -falign-jumps=4 -falign-loops=4
#COMMON_FLAGS := -funroll-loops -fpeel-loops -fgcse-sm -fgcse-las
# Optimize just for code size
COMMON_FLAGS += -fno-inline -fno-common  -falign-functions=4

#COMMON_FLAGS += -DFLAGS_STR=\""$(COMMON_FLAGS)"\"
COMMON_FLAGS += -DITERATIONS=500 -DPERFORMANCE_RUN=1