SIM_ROOT_DIR     := ${PWD}
BUILD_DIR      := ${PWD}/build

TEST_SRCDIR := ${PWD}/test_src
C_SRC_DIR := ${PWD}/csrc
C_BUILD_DIR := ${BUILD_DIR}/c_compiled

PROGRAM_NAME     := main
PROGRAM     := ${BUILD_DIR}/c_compiled/${PROGRAM_NAME}

TEST_PROGRAM_NAME     := rv32mi-p-breakpoint
TEST_PROGRAM     := ${BUILD_DIR}/test_compiled/${TEST_PROGRAM_NAME}

E203_SRC := ${PWD}/deps/Verilog/e203_veri_src

IVERILOG_DIR := ${PWD}/deps/Verilog/iverilog/bin
SIM_TOOL          := verilator

ifeq ($(SIM_TOOL),iverilog)
E203_EXEC_DIR := ${BUILD_DIR}/e203_exec_iverilog
EXEC_POST_PROC := @cp -f ${BUILD_DIR}/vvp.exec ${E203_EXEC_DIR}
endif
ifeq ($(SIM_TOOL),verilator)
E203_EXEC_DIR := ${BUILD_DIR}/e203_exec_verilator
EXEC_POST_PROC := @cp -f ${BUILD_DIR}/verilator_build/Vtb_top ${E203_EXEC_DIR}
endif

DUMPWAVE     := 1

CORE        := e203
CFG         := ${CORE}_config

USE_HB_SDK := 1

CORE_NAME = $(shell echo $(CORE) | tr a-z A-Z)
core_name = $(shell echo $(CORE) | tr A-Z a-z)

SELF_TESTS := $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv32uc-p*.dump))
ifeq ($(core_name),${E203})
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv32um-p*.dump))
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD}/ ${BUILD_DIR}/e203_src_tmp_DIR}/test_compiled/rv32ua-p*.dump))
endif

SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv32ui-p*.dump))
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv32mi-p*.dump))

include ${PWD}/deps/C/test_src/Makefile

compile_c:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make dasm USE_HBIRD_SDK=${USE_HBIRD_SDK} SOC=hbirdv2 CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} -C ${C_BUILD_DIR}

bin:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make bin USE_HBIRD_SDK=${USE_HBIRD_SDK} SOC=hbirdv2 CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} -C ${C_BUILD_DIR}

qemu:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make qemu USE_HBIRD_SDK=0 SOC=hbirdv2 CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} -C ${C_BUILD_DIR}
	
asm:
	@mkdir -p ${C_BUILD_DIR}
	@rm -f $(C_BUILD_DIR)/Makefile
	@ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make asm USE_HB_SDK=0 SOC=hbirdv2 CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} -C ${C_BUILD_DIR}
	@mv $(C_SRC_DIR)/*.S* $(C_BUILD_DIR)

e203:
	@mkdir -p ${BUILD_DIR}
	@rm -rf ${E203_EXEC_DIR}
	@mkdir -p ${E203_EXEC_DIR}
	@rm -f ${BUILD_DIR}/Makefile
	@ln -s ${SIM_ROOT_DIR}/deps/Verilog/run.makefile ${BUILD_DIR}/Makefile
	@cp -rf ${E203_SRC}/ ${BUILD_DIR}/e203_src_tmp
	make compile BUILD_DIR=${BUILD_DIR} SIM_TOOL=${SIM_TOOL} IVERILOG_DIR=${IVERILOG_DIR} -C ${BUILD_DIR}
	${EXEC_POST_PROC}

wave: ${BUILD_DIR}
	make wave IVERILOG_DIR=${IVERILOG_DIR} TESTCASE=${PROGRAM_DIR} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}

run:
	make run IVERILOG_DIR=${IVERILOG_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM_DIR=${PROGRAM_DIR} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} E203_EXEC_DIR=${E203_EXEC_DIR} -C ${BUILD_DIR}

sim: compile_c e203
	make run IVERILOG_DIR=${IVERILOG_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM_DIR=${PROGRAM_DIR} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} E203_EXEC_DIR=${E203_EXEC_DIR} -C ${BUILD_DIR}

test: e203

	@if [ ! -e ${BUILD_DIR}/test_compiled ] ; \
	then	\
		echo -e "\n" ;	\
		echo "****************************************" ;	\
		echo '    do "make compile_test_src" first';	\
		echo "****************************************" ;	\
		echo -e "\n" ;	\
	else	\
		make test IVERILOG_DIR=${IVERILOG_DIR} DUMPWAVE=${DUMPWAVE} TEST_PROGRAM=${TEST_PROGRAM} SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} E203_EXEC_DIR=${E203_EXEC_DIR} -C ${BUILD_DIR} ;	\
	fi



test_all: e203
	@if [ ! -e ${BUILD_DIR}/test_compiled ] ; \
	then	\
		echo -e "\n" ;	\
		echo "****************************************" ;	\
		echo '    do "make compile_test_src" first';	\
		echo "****************************************" ;	\
		echo -e "\n" ;	\
	else	\
		$(foreach tst,$(SELF_TESTS), make test DUMPWAVE=0 IVERILOG_DIR=${IVERILOG_DIR} TEST_PROGRAM=${tst} TEST_ALL=1 SIM_TOOL=${SIM_TOOL} BUILD_DIR=${BUILD_DIR} E203_EXEC_DIR=${E203_EXEC_DIR} -C ${BUILD_DIR};)\
		rm -rf ${BUILD_DIR}/regress.res ;\
		find ${BUILD_DIR}/test_out/ -name "rv32*.log" -exec ${SIM_ROOT_DIR}/deps/C/tools/find_test_fail.csh {} >> ${BUILD_DIR}/regress.res \;; cat ${BUILD_DIR}/regress.res ;	\
	fi


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

.PHONY: compile run install clean all e203 sim asm test test_all qemu compile_c compile_test_src

