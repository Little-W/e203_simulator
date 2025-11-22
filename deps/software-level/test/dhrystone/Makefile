include $(SIM_ROOT_DIR)/make.conf
TARGET = dhrystone
PFLOAT = 1

SRCDIRS = ${DHRYSTONE_DIR} src
INCDIRS = ${DHRYSTONE_DIR} inc

include $(SOFTWARE_MAKEFILES_DIR)/gmsl/gmsl
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.misc
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.conf
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.rules

# Clean generated *.i and *.s
COMMON_FLAGS += -fno-inline -fno-common  -falign-functions=4


