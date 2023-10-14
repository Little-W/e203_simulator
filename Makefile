SIM_ROOT_DIR     := ${PWD}
include $(SIM_ROOT_DIR)/make.conf

DUMMY_TEST_PROGRAM     := ${BUILD_DIR}/dummy_test/dummy_test
CORE_NAME = $(shell echo $(CORE) | tr a-z A-Z)
core_name = $(shell echo $(CORE) | tr A-Z a-z)

SELF_TESTS := $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv${XLEN}uc-p*.dump))
ifeq ($(core_name),${E203})
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv32um-p*.dump))
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv32ua-p*.dump))
endif
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv${XLEN}ui-p*.dump))
SELF_TESTS += $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/test_compiled/rv${XLEN}mi-p*.dump))

BENCHMARK_TESTS := $(patsubst %.dump,%,$(wildcard ${BUILD_DIR}/benchmark_compiled/*.dump))

compile_c:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOTFWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
	fi
	make dasm USE_HBIRD_SDK=${USE_HBIRD_SDK} TARGET=${TARGET} SOC=${SOC} C_SRC_DIR=${C_SRC_DIR} CORE=e203 SIM_ROOT_DIR=${SIM_ROOT_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}

bin:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOTFWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
	fi
	make bin USE_HBIRD_SDK=${USE_HBIRD_SDK} SOC=${SOC} CORE=e203 SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}

qemu:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOTFWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
	fi
	make qemu USE_HBIRD_SDK=0 SOC=${SOC} CORE=e203 SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}
	
asm:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOTFWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
	fi
	make asm USE_HB_SDK=0 SOC=${SOC} CORE=e203 SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}
	@mv $(C_SRC_DIR)/*.S* $(C_BUILD_DIR)

e203:
	@mkdir -p ${BUILD_DIR}
	@if [ ! -h ${BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${BUILD_DIR}/Makefile; \
	ln -s ${HARDWARE_DEPS_ROOT}/Makefile ${BUILD_DIR}/Makefile; \
	fi
	@if [ ! -d ${BUILD_DIR}/${CORE}_tb/ ] ; \
	then	\
	mkdir -p ${BUILD_DIR}/${CORE}_tb/; \
	cp -rf ${HARDWARE_SRC_DIR}/${CORE}/${SOC}/tb/ ${BUILD_DIR}/${CORE}_tb/tb; \
	cp -rf ${HARDWARE_SRC_DIR}/${CORE}/${SOC}/tb_verilator ${BUILD_DIR}/${CORE}_tb/tb_verilator; \
	fi
	make compile SIM_ROOT_DIR=${SIM_ROOT_DIR} SIM_TOOL=${SIM_TOOL} SOC=${SOC} -C ${BUILD_DIR}


wave: ${BUILD_DIR}
	make wave SIM_ROOT_DIR=${SIM_ROOT_DIR} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

run:
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

sim: compile_c e203
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

test: e203

	@if [ ! -e ${BUILD_DIR}/test_compiled ] ; \
	then	\
		echo ;	\
		echo "****************************************" ;	\
		echo '    do "make compile_test_src" first';	\
		echo "****************************************" ;	\
		echo ;	\
	else	\
		make test SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR} ;	\
	fi

compile_test_src:
	@if [ ! -e ${TEST_PROGRAM} ] ; \
	then	\
		make SIM_ROOT_DIR=${SIM_ROOT_DIR} XLEN=${XLEN} -j$(nproc) -C ${ISA_TEST_DIR}/test_src/;	\
	fi

run_benchmarks: e203
	if [ ! -e ${BUILD_DIR}/benchmark_compiled ] ; \
	then	\
		echo -e "\n" ;	\
		echo "****************************************" ;	\
		echo '    do "make compile_test_src" first';	\
		echo "****************************************" ;	\
		echo -e "\n" ;	\
	else	\
		$(foreach tst,$(BENCHMARK_TESTS), make test DUMPWAVE=0 SIM_ROOT_DIR=${SIM_ROOT_DIR} TEST_PROGRAM=${tst} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR};)\
	fi
compile_benchmark_src:
	make SIM_ROOT_DIR=${SIM_ROOT_DIR} XLEN=${XLEN} -j$(nproc) -C ${RISCV_BENCHMARK_DIR}

test_all: e203
	@if [ ! -e ${BUILD_DIR}/test_compiled ] ; \
	then	\
		echo -e "\n" ;	\
		echo "****************************************" ;	\
		echo '    do "make compile_test_src" first';	\
		echo "****************************************" ;	\
		echo -e "\n" ;	\
	else	\
		$(foreach tst,$(SELF_TESTS), make test DUMPWAVE=0 SIM_ROOT_DIR=${SIM_ROOT_DIR} TEST_PROGRAM=${tst} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR};)\
		rm -rf ${BUILD_DIR}/regress.res ;\
		find ${BUILD_DIR}/test_out/ -name "rv${XLEN}*.log" -exec ${SIM_ROOT_DIR}/deps/tools/find_test_fail.csh {} >> ${BUILD_DIR}/regress.res \;; cat ${BUILD_DIR}/regress.res ;	\
	fi

debug_env: compile_c
	@rm -f ${BUILD_DIR}/Makefile
	@ln -s ${HARDWARE_DEPS_ROOT}/Makefile ${BUILD_DIR}/Makefile
	
debug_sim: debug_env compile_c
	@if [ ! -d ${BUILD_DIR}/${CORE}_tb/ ] ; \
	then	\
	mkdir -p ${BUILD_DIR}/${CORE}_tb/; \
	cp -rf ${HARDWARE_SRC_DIR}/${CORE}/${SOC}/tb/ ${BUILD_DIR}/${CORE}_tb/tb; \
	cp -rf ${HARDWARE_SRC_DIR}/${CORE}/${SOC}/tb_verilator ${BUILD_DIR}/${CORE}_tb/tb_verilator; \
	fi
	make debug_sim SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM=${DUMMY_TEST_PROGRAM} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

debug_openocd: 
	make debug_openocd SIM_ROOT_DIR=${SIM_ROOT_DIR} -C ${BUILD_DIR}

debug_gdb: 
	@mkdir -p ${BUILD_DIR}
	@rm -f ${BUILD_DIR}/Makefile
	@ln -s ${HARDWARE_DEPS_ROOT}/Makefile ${BUILD_DIR}/Makefile
	make debug_gdb SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} PROGRAM=${PROGRAM} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

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

.PHONY: compile run install clean all e203 sim asm test test_all qemu compile_c compile_test_src debug_gdb debug_openocd debug_sim compile_benchmark_src

