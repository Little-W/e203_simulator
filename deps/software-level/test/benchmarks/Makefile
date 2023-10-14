#=======================================================================
# UCB VLSI FLOW: Makefile for riscv-bmarks
#-----------------------------------------------------------------------
# Yunsup Lee (yunsup@cs.berkeley.edu)
#

XLEN ?= 32
include $(SIM_ROOT_DIR)/make.conf
include $(SOTFWARE_MAKEFILES_DIR)/Makefile.env
src_dir := $(ISA_TEST_DIR)/test_src/
OUT_DIR = $(BUILD_DIR)/benchmark_compiled

default: riscv


src_dir = $(RISCV_BENCHMARK_DIR)

instname = riscv-bmarks
instbasedir = $(UCB_VLSI_HOME)/install

#--------------------------------------------------------------------
# Sources
#--------------------------------------------------------------------

bmarks = \
	fpu-perf \
	median \
	qsort \
	rsort \
	towers \
	vvadd \
	multiply \
	mm \
	coremark \
	dhrystone \
	spmv \
	mt-vvadd \
	mt-matmul \
	pmp \

#--------------------------------------------------------------------
# Build rules
#--------------------------------------------------------------------

#RISCV_GCC_OPTS ?=                               -DPREALLOCATE=1 -mcmodel=medany -static -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf
RISCV_GCC_OPTS ?= -march=rv32imafdc -mabi=ilp32f -DPREALLOCATE=1 -mcmodel=medany -static -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf
RISCV_LINK ?= $(RISCV_GCC) -T $(src_dir)/common/test.ld $(incs)
#RISCV_LINK_OPTS ?= -static -nostdlib -nostartfiles -lgcc -T $(src_dir)/common/test.ld 
RISCV_LINK_OPTS ?= -march=rv32imafdc -mabi=ilp32f --specs=nano.specs --specs=nosys.specs -static -nostartfiles -lgcc -T $(src_dir)/common/test.ld 

incs  += -I$(SOTFWARE_TEST_DIR)/common_libs -I$(src_dir)/common $(addprefix -I$(src_dir)/, $(bmarks))
objs  :=

define compile_template
$(1).riscv: $(wildcard $(src_dir)/$(1)/*) $(wildcard $(src_dir)/common/*)
	$$(CC) $$(incs) $$(RISCV_GCC_OPTS) $$(RISCV_LINK_OPTS) -o $(OUT_DIR)/$$@ $(wildcard $(src_dir)/$(1)/*.c) $(wildcard $(src_dir)/common/*.c) $(wildcard $(src_dir)/common/*.S)
endef

$(foreach bmark,$(bmarks),$(eval $(call compile_template,$(bmark))))

#------------------------------------------------------------
# Build and run benchmarks on riscv simulator

bmarks_riscv_bin  = $(addsuffix .riscv,  $(bmarks))
bmarks_riscv_dump = $(addsuffix .riscv.dump, $(bmarks))
bmarks_riscv_verilog = $(addsuffix .riscv.verilog, $(bmarks))

$(bmarks_riscv_dump): %.riscv.dump: %.riscv
	$(OBJDUMP) --disassemble-all $(OUT_DIR)/$< > $(OUT_DIR)/$@

$(bmarks_riscv_verilog): %.riscv.verilog: %.riscv
	$(OBJCOPY) -O verilog $(OUT_DIR)/$<   $(OUT_DIR)/$<.verilog
	sed -i 's/@800/@000/g' $(OUT_DIR)/$<.verilog
	sed -i 's/@00002FB8/@00002000/g' $(OUT_DIR)/$<.verilog


$(OUT_DIR):
	mkdir -p $(OUT_DIR)
riscv: $(OUT_DIR) $(bmarks_riscv_dump) $(bmarks_riscv_verilog)

