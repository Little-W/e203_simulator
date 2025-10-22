ifndef CONF_DEFINED
include $(SIM_ROOT_DIR)/make.conf
endif


SIMULATION ?= 0
V ?=
SILENT ?=
RTOS ?=
PFLOAT ?= 0
NEWLIB ?= nano
NOGC ?= 0
BANNER ?=


EXTRA_MKS := $(wildcard Makefile.local $(SOFTWARE_MAKEFILES_DIR)/Makefile.global)
ifneq ("$(strip $(EXTRA_MKS))", "")
$(info Obtaining addtional make variables from $(EXTRA_MKS))
include $(EXTRA_MKS)
endif

HBIRD_SDK_NMSIS = $(SOTFWARE_LIBS_DIR)/NMSIS
HBIRD_SDK_SOC = $(SOTFWARE_LIBS_DIR)/SoC/$(SOC)

include $(SOFTWARE_MAKEFILES_DIR)/gmsl/gmsl
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.files
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.soc
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.misc
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.conf
include $(SOFTWARE_MAKEFILES_DIR)/Makefile.rules
