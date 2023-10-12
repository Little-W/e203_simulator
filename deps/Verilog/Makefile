include ${SIM_ROOT_DIR}/deps/C/makefiles/Makefile.conf
ARCH := $(shell uname -m)

RUN_DIR      := ${PWD}
BUILD_DIR      := ${PWD}/build
PROGRAM_NAME     := main
PROGRAM     := ${BUILD_DIR}/c_compiled/${PROGRAM_NAME}

TEST_PROGRAM_NAME     := rv32mi-p-breakpoint
TEST_PROGRAM     := ${BUILD_DIR}/test_compiled/${TEST_PROGRAM_NAME}

DUMPWAVE     := 1
TEST_ALL := 0
SMIC130LL    := 0
GATE_SIM     := 0
GATE_SDF     := 0
GATE_NOTIME     := 0

VSRC_DIR     := ${BUILD_DIR}/e203_src_tmp/rtl
VTB_DIR      := ${BUILD_DIR}/e203_src_tmp/tb
JTAG_DIR 	 := ${BUILD_DIR}/e203_src_tmp/jtag_vpi
TEST_NAME     := $(notdir $(patsubst %.dump,%,${TEST_PROGRAM}))
SIM_OUT_DIR     := sim_out
TEST_RUNDIR := test_out


# The following portion is depending on the EDA tools you are using, Please add them by yourself according to your EDA vendors
#To-ADD: to add the simulatoin tool
#SIM_TOOL      := vcs
SIM_TOOL      := verilator4
TRUE_SIM_TOOL := $(shell echo ${SIM_TOOL} | grep -o '[^0-9]*')
IVERILOG_DIR := ${SIM_ROOT_DIR}/deps/Verilog/iverilog/bin
VERILATOR_DIR :=  ${SIM_ROOT_DIR}/deps/Verilog/${SIM_TOOL}/bin
VERILATOR_ROOT :=  ${SIM_ROOT_DIR}/deps/Verilog/${SIM_TOOL}/share/verilator/

DEBUG_TRACE := 0

#To-ADD: to add the simulatoin tool options
ifeq ($(TRUE_SIM_TOOL),verilator)
VERILATOR_BUILD_DIR := ${BUILD_DIR}/verilator_build
SIM_OPTIONS   := --Mdir ${VERILATOR_BUILD_DIR} 
SIM_OPTIONS   += --cc +incdir+${VSRC_DIR}/core  -CFLAGS -I${VSRC_DIR}/core +incdir+${VSRC_DIR}/perips/ -CFLAGS -I${VSRC_DIR}/perips
SIM_OPTIONS   += +incdir+${VSRC_DIR}/perips/apb_i2c/ -CFLAGS -I${VSRC_DIR}/perips/apb_i2c/
SIM_OPTIONS   += --exe --trace --trace-structs --trace-params --trace-max-array 1024
SIM_OPTIONS   += -CFLAGS "-Wall -DTOPLEVEL_NAME=tb_top -g -O0" -LDFLAGS "-pthread -lutil -lelf"
SIM_OPTIONS   +=  -Wno-PINCONNECTEMPTY -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT
ifeq ($(SIM_TOOL),verilator5)
SIM_OPTIONS   += --no-timing
endif
SIM_OPTIONS_BACK := --top-module tb_top --exe -DE203_XLEN=32 -DDISABLE_SV_ASSERTION=1
VTB_DIR      := ${BUILD_DIR}/e203_src_tmp/tb_verilator
VERILATOR_CC_FILE := ${VTB_DIR}/tb_top.cc
endif

ifeq ($(TRUE_SIM_TOOL),vcs)
SIM_OPTIONS   := +v2k -sverilog -q +lint=all,noSVA-NSVU,noVCDE,noUI,noSVA-CE,noSVA-DIU  -debug_access+all -full64 -timescale=1ns/10ps
SIM_OPTIONS   += +incdir+"${VSRC_DIR}/core/"+"${VSRC_DIR}/perips/"+"${VSRC_DIR}/perips/apb_i2c/"
endif
ifeq ($(TRUE_SIM_TOOL),iverilog)
SIM_OPTIONS   := -o vvp.exec -I "${VSRC_DIR}/core/" -I "${VSRC_DIR}/perips/" -I "${VSRC_DIR}/perips/apb_i2c/" -D DISABLE_SV_ASSERTION=1 -g2005-sv
endif


RTL_V_FILES		:= $(wildcard ${VSRC_DIR}/*/*.v ${VSRC_DIR}/*/*/*.v)
TB_V_FILES		:= $(wildcard ${VTB_DIR}/*.v)

ifeq ($(SMIC130LL),1)
SIM_OPTIONS   += +define+SMIC130_LL
endif
ifeq ($(GATE_SIM),1)
SIM_OPTIONS   += +define+GATE_SIM  +lint=noIWU,noOUDPE,noPCUDPE
endif
ifeq ($(GATE_SDF),1)
SIM_OPTIONS   += +define+GATE_SDF
endif
ifeq ($(GATE_NOTIME),1)
SIM_OPTIONS   += +nospecify +notimingcheck
endif
ifeq ($(GATE_SDF_MAX),1)
SIM_OPTIONS   += +define+SIM_MAX
endif
ifeq ($(GATE_SDF_MIN),1)
SIM_OPTIONS   += +define+SIM_MIN
endif

#To-ADD: to add the simulatoin executable
ifeq ($(TRUE_SIM_TOOL),verilator)

ifeq ($(wildcard $(VERILATOR_DIR)),)

	ifeq ($(ARCH),x86_64)
	ifeq ($(SIM_TOOL),verilator4)
		shell := $(shell wget https://bitbucket.org/little-w/e203_simulator/downloads/x86_64_verilator-4.228.tar.xz)
		shell := $(shell rm -rf ../deps/Verilog/$(SIM_TOOL))
		shell := $(shell mkdir -p ../deps/Verilog/$(SIM_TOOL) && mv x86_64_verilator-4.228.tar.xz ../deps/Verilog/$(SIM_TOOL) && cd ../deps/Verilog/$(SIM_TOOL) && tar -xvf x86_64_verilator-4.228.tar.xz && rm x86_64_verilator-4.228.tar.xz)
	else
		shell := $(shell wget https://bitbucket.org/little-w/e203_simulator/downloads/x86_64_verilator-5.016.tar.xz)
		shell := $(shell rm -rf ../deps/Verilog/$(SIM_TOOL))
		shell := $(shell mkdir -p ../deps/Verilog/$(SIM_TOOL) && mv x86_64_verilator-5.016.tar.xz ../deps/Verilog/$(SIM_TOOL) && cd ../deps/Verilog/$(SIM_TOOL) && tar -xvf x86_64_verilator-5.016.tar.xz && rm x86_64_verilator-5.016.tar.xz)
	endif
	else ifeq ($(ARCH),aarch64)
	ifeq ($(SIM_TOOL),verilator4)
		shell := $(shell wget https://bitbucket.org/little-w/e203_simulator/downloads/arm64_verilator-4.228.tar.xz)
		shell := $(shell rm -rf ../deps/Verilog/$(SIM_TOOL))
		shell := $(shell mkdir -p ../deps/Verilog/$(SIM_TOOL) && mv arm64_verilator-4.228.tar.xz ../deps/Verilog/$(SIM_TOOL) && cd ../deps/Verilog/$(SIM_TOOL) && tar -xvf arm64_verilator-4.228.tar.xz && rm arm64_verilator-4.228.tar.xz)
	else
		shell := $(shell wget https://bitbucket.org/little-w/e203_simulator/downloads/arm64_verilator-5.016.tar.xz)
		shell := $(shell rm -rf ../deps/Verilog/$(SIM_TOOL))
		shell := $(shell mkdir -p ../deps/Verilog/$(SIM_TOOL) && mv arm64_verilator-5.016.tar.xz ../deps/Verilog/$(SIM_TOOL) && cd ../deps/Verilog/$(SIM_TOOL) && tar -xvf arm64_verilator-5.016.tar.xz && rm arm64_verilator-5.016.tar.xz)
	endif
	else
		$(error Unsupported architecture: $(ARCH))
	endif

endif

SIM_TOOL_EXEC      := ${VERILATOR_DIR}/verilator
E203_EXEC_DIR := ${BUILD_DIR}/e203_exec_verilator
ifeq ($(ARCH),x86_64)
VERILATOR_COMPILE_CMD := make -f Vtb_top.mk -C ${VERILATOR_BUILD_DIR} -j$(nproc)
else ifeq ($(ARCH),aarch64)
VERILATOR_COMPILE_CMD := make -f Vtb_top.mk -C ${VERILATOR_BUILD_DIR} -j4
endif
SIM_EXEC := ${E203_EXEC_DIR}/Vtb_top
SIM_CMD := ${SIM_EXEC}  -t +itcm_init=${PROGRAM}
ifeq ($(DEBUG_TRACE),1)
DEBUG_CMD := ${SIM_EXEC} -t +itcm_init=${PROGRAM}
else
DEBUG_CMD := ${SIM_EXEC} +itcm_init=${PROGRAM}
endif
ifeq ($(TEST_ALL),0)
TEST_CMD := ${SIM_EXEC}  -t +itcm_init=${TEST_PROGRAM} | tee ${TEST_NAME}.log
else
TEST_CMD := ${SIM_EXEC} +itcm_init=${TEST_PROGRAM} | tee ${TEST_NAME}.log
endif

EXEC_POST_PROC := @cp -f ${BUILD_DIR}/verilator_build/Vtb_top ${E203_EXEC_DIR}

endif

ifeq ($(TRUE_SIM_TOOL),vcs)
SIM_EXEC      := ${RUN_DIR}/simv +ntb_random_seed_automatic
E203_EXEC_DIR := ${BUILD_DIR}/e203_exec_iverilog
endif
ifeq ($(TRUE_SIM_TOOL),iverilog)
SIM_EXEC      := ${IVERILOG_DIR}/vvp ${E203_EXEC_DIR}/vvp.exec -lxt2
SIM_TOOL_EXEC := ${IVERILOG_DIR}/iverilog
SIM_CMD := ${SIM_EXEC} +DUMPWAVE=${DUMPWAVE} +TESTCASE=${PROGRAM} +SIM_TOOL=${TRUE_SIM_TOOL} 2>&1 | tee ${SIM_OUT_DIR}.log
TEST_CMD := ${SIM_EXEC} +DUMPWAVE=${DUMPWAVE} +TESTCASE=${TEST_PROGRAM} +SIM_TOOL=${TRUE_SIM_TOOL} 2>&1 | tee ${TEST_NAME}.log

EXEC_POST_PROC := @cp -f ${BUILD_DIR}/vvp.exec ${E203_EXEC_DIR}

ifeq ($(wildcard $(IVERILOG_DIR)),)

	ifeq ($(ARCH),x86_64)
		shell := $(shell wget https://bitbucket.org/little-w/e203_simulator/downloads/iverilog12.0_x86_64.tar.xz)
		shell := $(shell rm -rf ../deps/Verilog/iverilog)
		shell := $(shell mkdir -p ../deps/Verilog/iverilog && mv iverilog12.0_x86_64.tar.xz ../deps/Verilog/iverilog && cd ../deps/Verilog/iverilog && tar -xvf iverilog12.0_x86_64.tar.xz && rm iverilog12.0_x86_64.tar.xz)
	else ifeq ($(ARCH),aarch64)
		shell := $(shell wget https://bitbucket.org/little-w/e203_simulator/downloads/iverilog12.0_arm64.tar.xz)
		shell := $(shell rm -rf ../deps/Verilog/iverilog)
		shell := $(shell mkdir -p ../deps/Verilog/iverilog && mv iverilog12.0_arm64.tar.xz ../deps/Verilog/iverilog && cd ../deps/Verilog/iverilog && tar -xvf iverilog12.0_arm64.tar.xz && rm iverilog12.0_arm64.tar.xz)
	else
		$(error Unsupported architecture: $(ARCH))
	endif

endif

endif


#To-ADD: to add the waveform toolSIM_TOOL_EXEC
ifeq ($(TRUE_SIM_TOOL),vcs)
WAV_TOOL := verdi
endif
ifeq ($(TRUE_SIM_TOOL),iverilog)
WAV_TOOL := gtkwave
endif
ifeq ($(TRUE_SIM_TOOL),verilator)
WAV_TOOL := gtkwave
endif
#To-ADD: to add the waveform tool options
ifeq ($(WAV_TOOL),verdi)
WAV_OPTIONS   := +v2k -sverilog
endif
ifeq ($(WAV_TOOL),gtkwave)
WAV_OPTIONS   :=
endif

ifeq ($(SMIC130LL),1)
WAV_OPTIONS   += +define+SMIC130_LL
endif
ifeq ($(GATE_SIM),1)
WAV_OPTIONS   += +define+GATE_SIM
endif
ifeq ($(GATE_SDF),1)
WAV_OPTIONS   += +define+GATE_SDF
endif


#To-ADD: to add the include dir
ifeq ($(WAV_TOOL),verdi)
WAV_INC      := +incdir+"${VSRC_DIR}/core/"+"${VSRC_DIR}/perips/"+"${VSRC_DIR}/perips/apb_i2c/"
endif
ifeq ($(WAV_TOOL),gtkwave)
WAV_INC      :=
endif

#To-ADD: to add RTL and TB files
ifeq ($(WAV_TOOL),verdi)
WAV_RTL      := ${RTL_V_FILES} ${TB_V_FILES}
endif
ifeq ($(WAV_TOOL),gtkwave)
WAV_RTL      :=
endif

#To-ADD: to add the waveform file
ifeq ($(WAV_TOOL),verdi)
WAV_FILE      := -ssf ${TEST_RUNDIR}/tb_top.fsdb
endif
ifeq ($(WAV_TOOL),gtkwave)
TEST_WAV_FILE      := ${TEST_RUNDIR}/tb_top.vcd
SIM_WAV_FILE 	   := ${SIM_OUT_DIR}/tb_top.vcd
endif

all: run

compile.flg: ${RTL_V_FILES} ${TB_V_FILES}
	@-rm -rf compile.flg
	@rm -rf ${E203_EXEC_DIR}
	@mkdir -p ${E203_EXEC_DIR}
	@sed -i '1i\`define ${SIM_TOOL}\'  ${VTB_DIR}/tb_top.v
	${SIM_TOOL_EXEC} ${SIM_OPTIONS}  ${RTL_V_FILES} ${TB_V_FILES} ${VERILATOR_CC_FILE} ${SIM_OPTIONS_BACK}
	${VERILATOR_COMPILE_CMD}
	${EXEC_POST_PROC}
	@touch compile.flg

compile: compile.flg

wave:
	gvim -p ${PROGRAM}.dump &
	${WAV_TOOL} ${WAV_OPTIONS} ${WAV_INC} ${WAV_RTL} ${SIM_WAV_FILE}  &

run: compile
	@rm -rf ${SIM_OUT_DIR}
	@mkdir ${SIM_OUT_DIR}
	@cd ${SIM_OUT_DIR};${SIM_CMD}

test: compile
	@if [ ! -e ${TEST_RUNDIR} ] ;	\
	then 	\
		mkdir ${TEST_RUNDIR} ;	\
	fi
	cd ${TEST_RUNDIR};${TEST_CMD}
	@if [ ${TEST_ALL} -eq 0 ];	\
	then	\
		gvim -p ${TEST_PROGRAM}.dump & ${WAV_TOOL} ${WAV_OPTIONS} ${WAV_INC} ${WAV_RTL} ${TEST_WAV_FILE} &   \
	fi

debug_env:
	$(eval SIM_OPTIONS  += +incdir+${JTAG_DIR} -CFLAGS -I${JTAG_DIR})
	$(eval SIM_OPTIONS  += -CFLAGS -I${VERILATOR_ROOT}/include/)
	$(eval SIM_OPTIONS  += -CFLAGS -I${VERILATOR_ROOT}/include/vltstd/)
	$(eval VERILATOR_CC_FILE  += ${JTAG_DIR}/jtag_common.c)
	$(eval VERILATOR_CC_FILE  += ${JTAG_DIR}/jtagServer.cpp)
	$(eval VERILATOR_CC_FILE  += ${VERILATOR_ROOT}/include/verilated.cpp)
	$(eval VERILATOR_CC_FILE  += ${VERILATOR_ROOT}/include/verilated_vcd_c.cpp)
	$(eval SIM_OPTIONS_BACK  += -DJTAGVPI=1 -CFLAGS -DJTAGVPI=1)


debug_sim: debug_env compile
	@rm -rf ${SIM_OUT_DIR}
	@mkdir ${SIM_OUT_DIR}
	@cd ${SIM_OUT_DIR};${DEBUG_CMD}

debug_openocd: 
	${OPENOCD} -s ${JTAG_DIR} -f hbird-e203.cfg

debug_gdb: 
	${GDB} -ex "set remotetimeout 2000" -ex "target extended-remote localhost:3333"  -ex "info reg" ${PROGRAM}.elf

.PHONY: run 

