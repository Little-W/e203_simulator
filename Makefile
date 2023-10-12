SIM_ROOT_DIR     := ${PWD}
BUILD_DIR      := ${PWD}/build

TEST_SRCDIR := ${PWD}/test_src
C_SRC_DIR := ${PWD}/csrc
C_BUILD_DIR := ${BUILD_DIR}/c_compiled

PROGRAM_NAME     := main
PROGRAM     := ${BUILD_DIR}/c_compiled/${PROGRAM_NAME}

TEST_PROGRAM_NAME     := rv32mi-p-breakpoint
TEST_PROGRAM     := ${BUILD_DIR}/test_compiled/${TEST_PROGRAM_NAME}

DUMMY_TEST_PROGRAM     := ${BUILD_DIR}/dummy_test/dummy_test
DEBUG_TRACE := 0

SIM_TOOL          := verilator5

DUMPWAVE     := 1


CORE        := e203
CFG         := ${CORE}_config
XLEN	    := 32
SOC := hbirdv2

E203_SRC := ${PWD}/deps/Verilog/e203_src/

USE_OPEN_GNU_GCC := 0
USE_HB_SDK := 1

CORE_NAME = $(shell echo $(CORE) | tr a-z A-Z)
core_name = $(shell echo $(CORE) | tr A-Z a-z)

SELF_TESTS := $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv${XLEN}uc-p*.dump))
ifeq ($(core_name),${E203})
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv32um-p*.dump))
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD}/ ${BUILD_DIR}/e203_src_tmp_DIR}/test_compiled/rv32ua-p*.dump))
endif

SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv${XLEN}ui-p*.dump))
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv${XLEN}mi-p*.dump))


compile_c:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make dasm USE_HBIRD_SDK=${USE_HBIRD_SDK} SOC=${SOC} CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} TARGET=${PROGRAM_NAME} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}

bin:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make bin USE_HBIRD_SDK=${USE_HBIRD_SDK} SOC=${SOC} CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}

qemu:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make qemu USE_HBIRD_SDK=0 SOC=${SOC} CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}
	
asm:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make asm USE_HB_SDK=0 SOC=${SOC} CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}
	@mv $(C_SRC_DIR)/*.S* $(C_BUILD_DIR)

e203:
	@mkdir -p ${BUILD_DIR}
	@rm -f ${BUILD_DIR}/Makefile
	@ln -s ${SIM_ROOT_DIR}/deps/Verilog/Makefile ${BUILD_DIR}/Makefile
	@rm -rf ${BUILD_DIR}/e203_src_tmp
	@cp -rf ${E203_SRC}/${SOC} ${BUILD_DIR}/e203_src_tmp
	@cp -rf ${E203_SRC}/jtag_vpi/ ${BUILD_DIR}/e203_src_tmp
	make compile SIM_ROOT_DIR=${SIM_ROOT_DIR} BUILD_DIR=${BUILD_DIR} SIM_TOOL=${SIM_TOOL} SOC=${SOC} -C ${BUILD_DIR}


wave: ${BUILD_DIR}
	make wave SIM_ROOT_DIR=${SIM_ROOT_DIR} TESTCASE=${PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}

run:
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM=${PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}

sim: compile_c e203
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM=${PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}

test: e203

	@if [ ! -e ${BUILD_DIR}/test_compiled ] ; \
	then	\
		echo ;	\
		echo "****************************************" ;	\
		echo '    do "make compile_test_src" first';	\
		echo "****************************************" ;	\
		echo ;	\
	else	\
		make test DUMPWAVE=${DUMPWAVE} TEST_PROGRAM=${TEST_PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR} ;	\
	fi

compile_test_src:
	make SIM_ROOT_DIR=${SIM_ROOT_DIR} BUILD_DIR=${BUILD_DIR} XLEN=${XLEN} -j$(nproc) -C ${PWD}/deps/C/test_src/

test_all: e203
	@if [ ! -e ${BUILD_DIR}/test_compiled ] ; \
	then	\
		echo  ;	\
		echo "****************************************" ;	\
		echo '    do "make compile_test_src" first';	\
		echo "****************************************" ;	\
		echo ;	\
	else	\
		$(foreach tst,$(SELF_TESTS), make test DUMPWAVE=0 TEST_PROGRAM=${tst} TEST_ALL=1 SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR};)\
		rm -rf ${BUILD_DIR}/regress.res ;\
		find ${BUILD_DIR}/test_out/ -name "rv${XLEN}*.log" -exec ${SIM_ROOT_DIR}/deps/C/tools/find_test_fail.csh {} >> ${BUILD_DIR}/regress.res \;; cat ${BUILD_DIR}/regress.res ;	\
	fi

debug_env:
	@mkdir -p ${BUILD_DIR}/dummy_test
	@rm -f ${BUILD_DIR}/Makefile
	@ln -s ${SIM_ROOT_DIR}/deps/Verilog/Makefile ${BUILD_DIR}/Makefile
	@cp -f ${SIM_ROOT_DIR}/deps/C/test_src/dummy_test.c ${BUILD_DIR}/dummy_test
	$(eval C_SRC_DIR = ${BUILD_DIR}/dummy_test)
	$(eval C_BUILD_DIR := ${BUILD_DIR}/dummy_test)
	$(eval PROGRAM := DUMMY_TEST_PROGRAM)
	$(eval PROGRAM_NAME := dummy_test)
debug_sim: debug_env compile_c
	@cp -rf ${E203_SRC}/${SOC} ${BUILD_DIR}/e203_src_tmp
	@cp -rf ${E203_SRC}/jtag_vpi ${BUILD_DIR}/e203_src_tmp
	make debug_sim SIM_ROOT_DIR=${SIM_ROOT_DIR} DEBUG_TRACE=${DEBUG_TRACE} DUMPWAVE=${DUMPWAVE} PROGRAM=${DUMMY_TEST_PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}

debug_openocd: 
	make debug_openocd SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM=${DUMMY_TEST_PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}

debug_gdb: 
	@mkdir -p ${BUILD_DIR}
	@rm -f ${BUILD_DIR}/Makefile
	@ln -s ${SIM_ROOT_DIR}/deps/Verilog/Makefile ${BUILD_DIR}/Makefile
	@cp -rf ${E203_SRC}/ ${BUILD_DIR}/e203_src_tmp
	make debug_gdb SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM=${DUMMY_TEST_PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}

clean:
	@rm -rf build
	@rm -rf csrc/*.o
	@rm -rf csrc/*.o.*
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/*.o
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/*.o.*
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/Drivers/*.o
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/Drivers/*.o.*
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/GCC/*.o
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/GCC/*.o.*
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/Stubs/*.o
	@rm -rf deps/C/SoC/hbirdv2/Common/Source/Stubs/*.o.*

	@rm -rf deps/C/SoC/hbird/Common/Source/*.o
	@rm -rf deps/C/SoC/hbird/Common/Source/*.o.*
	@rm -rf deps/C/SoC/hbird/Common/Source/Drivers/*.o
	@rm -rf deps/C/SoC/hbird/Common/Source/Drivers/*.o.*
	@rm -rf deps/C/SoC/hbird/Common/Source/GCC/*.o
	@rm -rf deps/C/SoC/hbird/Common/Source/GCC/*.o.*
	@rm -rf deps/C/SoC/hbird/Common/Source/Stubs/*.o
	@rm -rf deps/C/SoC/hbird/Common/Source/Stubs/*.o.*
	@echo " Clean done."

.PHONY: compile run install clean all e203 sim asm test test_all qemu compile_c compile_test_src debug_gdb debug_openocd debug_sim

