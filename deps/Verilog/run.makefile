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
TEST_NAME     := $(notdir $(patsubst %.dump,%,${TEST_PROGRAM}))
SIM_DIR_NAME     := sim_out
TEST_RUNDIR := test_out

RTL_V_FILES		:= $(wildcard ${VSRC_DIR}/*/*.v ${VSRC_DIR}/*/*/*.v)
TB_V_FILES		:= $(wildcard ${VTB_DIR}/*.v)


# The following portion is depending on the EDA tools you are using, Please add them by yourself according to your EDA vendors
#To-ADD: to add the simulatoin tool
#SIM_TOOL      := vcs
SIM_TOOL      := iverilog

#To-ADD: to add the simulatoin tool options
ifeq ($(SIM_TOOL),vcs)
SIM_OPTIONS   := +v2k -sverilog -q +lint=all,noSVA-NSVU,noVCDE,noUI,noSVA-CE,noSVA-DIU  -debug_access+all -full64 -timescale=1ns/10ps
SIM_OPTIONS   += +incdir+"${VSRC_DIR}/core/"+"${VSRC_DIR}/perips/"+"${VSRC_DIR}/perips/apb_i2c/"
endif
ifeq ($(SIM_TOOL),iverilog)
SIM_OPTIONS   := -o vvp.exec -I "${VSRC_DIR}/core/" -I "${VSRC_DIR}/perips/" -I "${VSRC_DIR}/perips/apb_i2c/" -D DISABLE_SV_ASSERTION=1 -g2005-sv
endif



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
ifeq ($(SIM_TOOL),vcs)
SIM_EXEC      := ${RUN_DIR}/simv +ntb_random_seed_automatic
endif
ifeq ($(SIM_TOOL),iverilog)
SIM_EXEC      := ${IVERILOG_DIR}/vvp ${E203_EXEC_DIR}/vvp.exec -lxt2
SIM_TOOL_EXEC := ${IVERILOG_DIR}/iverilog


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


#To-ADD: to add the waveform tool
ifeq ($(SIM_TOOL),vcs)
WAV_TOOL := verdi
endif
ifeq ($(SIM_TOOL),iverilog)
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
WAV_FILE      := ${TEST_RUNDIR}/tb_top.vcd
endif

all: run

compile.flg: ${RTL_V_FILES} ${TB_V_FILES}
	@-rm -rf compile.flg
	sed -i '1i\`define ${SIM_TOOL}\'  ${VTB_DIR}/tb_top.v
	${SIM_TOOL_EXEC} ${SIM_OPTIONS}  ${RTL_V_FILES} ${TB_V_FILES} ;
	touch compile.flg

compile: compile.flg

wave:
	gvim -p ${PROGRAM}.dump &
	${WAV_TOOL} ${WAV_OPTIONS} ${WAV_INC} ${WAV_RTL} ${WAV_FILE}  &

run: compile
	rm -rf ${SIM_DIR_NAME}
	mkdir ${SIM_DIR_NAME}
	cd ${TEST_RUNDIR}; ${SIM_EXEC} +DUMPWAVE=${DUMPWAVE} +TESTCASE=${PROGRAM} +SIM_TOOL=${SIM_TOOL} 2>&1 | tee ${SIM_DIR_NAME}.log;

test: compile
	if [ ! -e ${TEST_RUNDIR} ] ; then mkdir ${TEST_RUNDIR} ;fi
	cd ${TEST_RUNDIR}; ${SIM_EXEC} +DUMPWAVE=${DUMPWAVE} +TESTCASE=${TEST_PROGRAM} +SIM_TOOL=${SIM_TOOL} 2>&1 | tee ${TEST_NAME}.log
	if [ ${TEST_ALL} -eq 0 ];then   gvim -p ${TEST_PROGRAM}.dump & ${WAV_TOOL} ${WAV_OPTIONS} ${WAV_INC} ${WAV_RTL} ${WAV_FILE} &   fi

.PHONY: run clean all

