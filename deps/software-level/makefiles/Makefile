include $(SIM_ROOT_DIR)/make.conf

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

include $(SOTFWARE_MAKEFILES_DIR)/gmsl/gmsl
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.misc
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.conf
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.rules
