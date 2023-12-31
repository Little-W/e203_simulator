#=======================================================================
# Makefile for riscv-tests/isa
#-----------------------------------------------------------------------

XLEN ?= 32

include $(SIM_ROOT_DIR)/make.conf
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.conf
src_dir := $(ISA_TEST_DIR)/test_src/
OUT_DIR = $(BUILD_DIR)/test_compiled

include $(src_dir)/rv64ui/Makefrag
include $(src_dir)/rv64uc/Makefrag
include $(src_dir)/rv64um/Makefrag
include $(src_dir)/rv64ua/Makefrag
include $(src_dir)/rv64uf/Makefrag
include $(src_dir)/rv64ud/Makefrag
include $(src_dir)/rv64si/Makefrag
include $(src_dir)/rv64mi/Makefrag
include $(src_dir)/rv32ui/Makefrag
include $(src_dir)/rv32uc/Makefrag
include $(src_dir)/rv32um/Makefrag
include $(src_dir)/rv32ua/Makefrag
include $(src_dir)/rv32uf/Makefrag
include $(src_dir)/rv32ud/Makefrag
include $(src_dir)/rv32si/Makefrag
include $(src_dir)/rv32mi/Makefrag
#include $(src_dir)/rv32imc_0/Makefrag
#include $(src_dir)/rv32imc_1/Makefrag
#include $(src_dir)/rv32imc_2/Makefrag

RISCV_GCC_FLAGS ?= -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles

vpath %.S $(src_dir)
vpath %.c $(src_dir)

default: compile_test_src

#------------------------------------------------------------
# Build assembly tests

%.dump: % 
	$(OBJDUMP) --disassemble-all $(OUT_DIR)/$< > $(OUT_DIR)/$@
	$(OBJCOPY) -O verilog $(OUT_DIR)/$<   $(OUT_DIR)/$<.verilog
	sed -i 's/@800/@000/g' $(OUT_DIR)/$<.verilog
	sed -i 's/@00002FB8/@00002000/g' $(OUT_DIR)/$<.verilog

define compile_template

$$($(1)_p_tests): $(1)-p-%: $(1)/%.S
	$$(CC) $(2) $$(RISCV_GCC_FLAGS) -I $(ISA_TEST_DIR)/test_libs -I $(SOTFWARE_TEST_DIR)/common_libs  -T $(ISA_TEST_DIR)/test_libs/link.ld $$< -o $(OUT_DIR)/$$@
$(1)_tests += $$($(1)_p_tests)

$(1)_tests_dump = $$(addsuffix .dump, $$($(1)_tests))

$(1): $$($(1)_tests_dump)

.PHONY: $(1)

tests += $$($(1)_tests)

endef

ifeq ($(USE_OPEN_GNU_GCC),1)
$(eval $(call compile_template,rv32ui,-march=rv32imafdc_zifencei -mabi=ilp32))
$(eval $(call compile_template,rv32uc,-march=rv32imafdc_zifencei -mabi=ilp32))
$(eval $(call compile_template,rv32um,-march=rv32imafdc_zifencei -mabi=ilp32))
$(eval $(call compile_template,rv32ua,-march=rv32imafdc_zifencei -mabi=ilp32))
$(eval $(call compile_template,rv32uf,-march=rv32imafdc_zifencei -mabi=ilp32))
$(eval $(call compile_template,rv32ud,-march=rv32imafdc_zifencei -mabi=ilp32))
#$(eval $(call compile_template,rv32si,-march=rv32imafdc -mabi=ilp32))
$(eval $(call compile_template,rv32mi,-march=rv32imafdc_zifencei -mabi=ilp32))
#$(eval $(call compile_template,rv32imc_0,-march=rv32imafdc -mabi=ilp32))
#$(eval $(call compile_template,rv32imc_1,-march=rv32imafdc -mabi=ilp32))
#$(eval $(call compile_template,rv32imc_2,-march=rv32imafdc -mabi=ilp32))
else
$(eval $(call compile_template,rv32ui,-march=rv32imafdc -mabi=ilp32))
$(eval $(call compile_template,rv32uc,-march=rv32imafdc -mabi=ilp32))
$(eval $(call compile_template,rv32um,-march=rv32imafdc -mabi=ilp32))
$(eval $(call compile_template,rv32ua,-march=rv32imafdc -mabi=ilp32))
$(eval $(call compile_template,rv32uf,-march=rv32imafdc -mabi=ilp32))
$(eval $(call compile_template,rv32ud,-march=rv32imafdc -mabi=ilp32))
#$(eval $(call compile_template,rv32si,-march=rv32imafdc -mabi=ilp32))
$(eval $(call compile_template,rv32mi,-march=rv32imafdc -mabi=ilp32))
#$(eval $(call compile_template,rv32imc_0,-march=rv32imafdc -mabi=ilp32))
#$(eval $(call compile_template,rv32imc_1,-march=rv32imafdc -mabi=ilp32))
#$(eval $(call compile_template,rv32imc_2,-march=rv32imafdc -mabi=ilp32))
endif
ifeq ($(XLEN),64)
$(eval $(call compile_template,rv64ui,-march=rv64imafdc -mabi=lp64))
$(eval $(call compile_template,rv64uc,-march=rv64imafdc -mabi=lp64))
$(eval $(call compile_template,rv64um,-march=rv64imafdc -mabi=lp64))
$(eval $(call compile_template,rv64ua,-march=rv64imafdc -mabi=lp64))
$(eval $(call compile_template,rv64uf,-march=rv64imafdc -mabi=lp64))
$(eval $(call compile_template,rv64ud,-march=rv64imafdc -mabi=lp64))
$(eval $(call compile_template,rv64si,-march=rv64imafdc -mabi=lp64))
$(eval $(call compile_template,rv64mi,-march=rv64imafdc -mabi=lp64))
endif

tests_verilog = $(addsuffix .verilog, $(tests))
tests_dump = $(addsuffix .dump, $(tests))
tests_hex = $(addsuffix .hex, $(tests))



$(OUT_DIR):
	mkdir -p $(OUT_DIR)

compile_test_src: $(OUT_DIR) $(tests_dump)

