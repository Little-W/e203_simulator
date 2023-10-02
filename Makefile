SIM_ROOT_DIR     := ${PWD}
BUILD_DIR      := ${PWD}/build
E203_EXEC_DIR := ${BUILD_DIR}/e203_exec

C_SRC_DIR := ${PWD}/csrc/
C_BUILD_DIR := ${BUILD_DIR}/c_compiled

PROGRAM_NAME     := main
PROGRAM_DIR     := ${BUILD_DIR}/c_compiled/${PROGRAM_NAME}
E203_SRC := ${PWD}/deps/Verilog/e203_veri_src

IVERILOG_DIR := ${PWD}/deps/Verilog/iverilog/bin
SIM          := iverilog
DUMPWAVE     := 1

CORE        := e203
CFG         := ${CORE}_config

USE_HBIRD_SDK := 1

CORE_NAME = $(shell echo $(CORE) | tr a-z A-Z)
core_name = $(shell echo $(CORE) | tr A-Z a-z)


compile_c:
	mkdir -p ${C_BUILD_DIR}
	rm -f $(C_BUILD_DIR)/Makefile
	ln -s $(SIM_ROOT_DIR)/deps/C/makefiles/Makefile ${C_BUILD_DIR}
	make dasm USE_HBIRD_SDK=${USE_HBIRD_SDK} SOC=hbirdv2 CORE=e203 DOWNLOAD=ilm SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} -C ${C_BUILD_DIR}

e203:

	mkdir -p ${BUILD_DIR}
	rm -rf ${E203_EXEC_DIR}
	mkdir -p ${E203_EXEC_DIR}
	rm -f ${BUILD_DIR}/Makefile
	ln -s ${SIM_ROOT_DIR}/deps/Verilog/run.makefile ${BUILD_DIR}/Makefile
	cp -rf ${E203_SRC}/ ${BUILD_DIR}/e203_src_tmp
	make compile BUILD_DIR=${BUILD_DIR} SIM_TOOL=${SIM} IVERILOG_DIR=${IVERILOG_DIR} -C ${BUILD_DIR}
	cp -f ${BUILD_DIR}/vvp.exec ${E203_EXEC_DIR}

wave: ${BUILD_DIR}
	make wave IVERILOG_DIR=${IVERILOG_DIR} TESTCASE=${PROGRAM_DIR} SIM_TOOL=${SIM} BUILD_DIR=${BUILD_DIR} -C ${BUILD_DIR}


sim: compile_c e203
	make run IVERILOG_DIR=${IVERILOG_DIR} DUMPWAVE=${DUMPWAVE} TESTCASE=${PROGRAM_DIR} SIM_TOOL=${SIM} BUILD_DIR=${BUILD_DIR} E203_EXEC_DIR=${E203_EXEC_DIR} -C ${BUILD_DIR}

clean:
	rm -rf build
	rm -rf csrc/*.o
	rm -rf csrc/*.o.*
	rm -rf deps/C/SoC/hbirdv2/Common/Source/*.o
	rm -rf deps/C/SoC/hbirdv2/Common/Source/*.o.*
	rm -rf deps/C/SoC/hbirdv2/Common/Source/Drivers/*.o
	rm -rf deps/C/SoC/hbirdv2/Common/Source/Drivers/*.o.*
	rm -rf deps/C/SoC/hbirdv2/Common/Source/GCC/*.o
	rm -rf deps/C/SoC/hbirdv2/Common/Source/GCC/*.o.*
	rm -rf deps/C/SoC/hbirdv2/Common/Source/Stubs/*.o
	rm -rf deps/C/SoC/hbirdv2/Common/Source/Stubs/*.o.*

	rm -rf deps/C/SoC/hbird/Common/Source/*.o
	rm -rf deps/C/SoC/hbird/Common/Source/*.o.*
	rm -rf deps/C/SoC/hbird/Common/Source/Drivers/*.o
	rm -rf deps/C/SoC/hbird/Common/Source/Drivers/*.o.*
	rm -rf deps/C/SoC/hbird/Common/Source/GCC/*.o
	rm -rf deps/C/SoC/hbird/Common/Source/GCC/*.o.*
	rm -rf deps/C/SoC/hbird/Common/Source/Stubs/*.o
	rm -rf deps/C/SoC/hbird/Common/Source/Stubs/*.o.*

.PHONY: compile run install clean all run_test regress regress_prepare regress_run regress_collect

