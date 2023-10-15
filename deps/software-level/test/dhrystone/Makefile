include $(SIM_ROOT_DIR)/make.conf
TARGET = dhrystone
PFLOAT = 1

SRCDIRS = ${DHRYSTONE_DIR} src
INCDIRS = ${DHRYSTONE_DIR} inc

include $(SOTFWARE_MAKEFILES_DIR)/gmsl/gmsl
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.misc
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.conf
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.rules

# Clean generated *.i and *.s
COMMON_FLAGS += -fno-inline -fno-common  -falign-functions=4


