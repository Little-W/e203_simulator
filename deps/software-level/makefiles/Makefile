ifndef CONF_DEFINED
include $(SIM_ROOT_DIR)/make.conf
endif


SIMULATION ?= 0
V ?=
SILENT ?=
RTOS ?=
PFLOAT ?= 0
NEWLIB ?= nano
NOGC ?=
BANNER ?=


EXTRA_MKS := $(wildcard Makefile.local $(SOTFWARE_MAKEFILES_DIR)/Makefile.global)
ifneq ("$(strip $(EXTRA_MKS))", "")
$(info Obtaining addtional make variables from $(EXTRA_MKS))
include $(EXTRA_MKS)
endif

HBIRD_SDK_NMSIS = $(SOTFWARE_LIBS_DIR)/NMSIS
HBIRD_SDK_SOC = $(SOTFWARE_LIBS_DIR)/SoC/$(SOC)

include $(SOTFWARE_MAKEFILES_DIR)/gmsl/gmsl
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.files
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.soc
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.misc
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.conf
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.rules
