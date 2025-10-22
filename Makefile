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
BENCHMARK_TESTS ?=  ${BUILD_DIR}/benchmark_compiled/
compile_c:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOFTWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
	fi
	make dasm TARGET=${TARGET} SOC=${SOC} PFLOAT=${PFLOAT} C_SRC_DIR=${C_SRC_DIR} SIM_ROOT_DIR=${SIM_ROOT_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}
	@if [ -e ${BUILD_DIR}/c_compiled/${TARGET}.verilog ]; then \
		python3 ${SIM_ROOT_DIR}/deps/tools/split_memory.py ${BUILD_DIR}/c_compiled/${TARGET}.verilog --force; \
		echo "Memory splitting completed"; \
	else \
		echo "tflm.verilog not found, skip memory split"; \
	fi

bin:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOFTWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
	fi
	make bin SOC=${SOC} SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}

qemu:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOFTWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
	fi
	make qemu USE_HB_SDK=0 SOC=${SOC} CORE=e203 SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${C_SRC_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${C_BUILD_DIR}
	
asm:
	@mkdir -p ${C_BUILD_DIR}
	@if [ ! -h ${C_BUILD_DIR}/Makefile ] ; \
	then \
	rm -f ${C_BUILD_DIR}/Makefile; \
	ln -s ${SOFTWARE_MAKEFILES_DIR}/Makefile ${C_BUILD_DIR}/Makefile; \
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
	make compile SIM_ROOT_DIR=${SIM_ROOT_DIR} SIM_TOOL=${SIM_TOOL} SOC=${SOC} SIM_OPTIONS_COMMON=${SIM_OPTIONS_COMMON} -C ${BUILD_DIR} -j36


wave: ${BUILD_DIR}
	make wave SIM_ROOT_DIR=${SIM_ROOT_DIR} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

run:
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

sim: compile_c e203
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR}

test: e203 compile_test_src

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
		make SIM_ROOT_DIR=${SIM_ROOT_DIR} XLEN=${XLEN} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -j$(nproc) -C ${ISA_TEST_DIR}/test_src/;	\
	fi

run_benchmarks: compile_benchmark_src e203 
	$(foreach tst,$(BENCHMARK_TESTS), make test DUMPWAVE=0 SIM_ROOT_DIR=${SIM_ROOT_DIR} TEST_PROGRAM=${tst} SIM_TOOL=${SIM_TOOL} -C ${BUILD_DIR};)

compile_benchmark_src:
	make SIM_ROOT_DIR=${SIM_ROOT_DIR} XLEN=${XLEN} -j$(nproc) -C ${RISCV_BENCHMARK_DIR}
	$(eval SIM_OPTIONS_COMMON := -DNO_TIMEOUT)
coremark_env: 
	@mkdir -p ${BUILD_DIR}/coremark_compiled/
	@if [ ! -h ${BUILD_DIR}/coremark_compiled/Makefile ] ; \
	then \
	rm -f ${BUILD_DIR}/coremark_compiled/Makefile; \
	ln -s ${COREMARK_DIR}/Makefile ${BUILD_DIR}/coremark_compiled/Makefile; \
	fi
	$(eval PROGRAM := ${BUILD_DIR}/coremark_compiled/coremark)
	$(eval SIM_OPTIONS_COMMON := -DNO_TIMEOUT)
	
coremark: coremark_env e203
	make dasm SOC=${SOC} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} SIM_ROOT_DIR=${SIM_ROOT_DIR} -C ${BUILD_DIR}/coremark_compiled/
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} PROGRAM=${PROGRAM} -C ${BUILD_DIR}

dhrystone_env: 
	@mkdir -p ${BUILD_DIR}/dhrystone_compiled/
	@if [ ! -h ${BUILD_DIR}/dhrystone_compiled/Makefile ] ; \
	then \
	rm -f ${BUILD_DIR}/dhrystone_compiled/Makefile; \
	ln -s ${DHRYSTONE_DIR}/Makefile ${BUILD_DIR}/dhrystone_compiled/Makefile; \
	fi
	$(eval PROGRAM := ${BUILD_DIR}/dhrystone_compiled/dhrystone)
	$(eval TARGET := dhrystone)
	$(eval SIM_OPTIONS_COMMON := -DNO_TIMEOUT -DE203_CFG_ITCM_ADDR_WIDTH=20)

	
dhrystone: dhrystone_env e203 compile_c
	make dasm TARGET=${TARGET} SOC=${SOC} SIM_ROOT_DIR=${SIM_ROOT_DIR} USE_OPEN_GNU_GCC=${USE_OPEN_GNU_GCC} -C ${BUILD_DIR}/dhrystone_compiled/
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} PROGRAM=${PROGRAM} -C ${BUILD_DIR}


test_all: e203 compile_test_src
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
	make clean SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${COREMARK_DIR} -C ${SOFTWARE_MAKEFILES_DIR}
		make clean SIM_ROOT_DIR=${SIM_ROOT_DIR} C_SRC_DIR=${DHRYSTONE_DIR} -C ${SOFTWARE_MAKEFILES_DIR}
	make clean SIM_ROOT_DIR=${SIM_ROOT_DIR} SOC=${SOC} C_SRC_DIR=${C_SRC_DIR} CORE=e203 -C ${SOFTWARE_MAKEFILES_DIR}
	@rm -rf build
	@echo "Clean done."

tflm_env: 
	@mkdir -p ${BUILD_DIR}/tflm_compiled/
	@if [ ! -h ${BUILD_DIR}/tflm_compiled/Makefile ] ; \
	then \
	rm -f ${BUILD_DIR}/tflm_compiled/Makefile; \
	ln -s ${TFLM_DIR}/Makefile ${BUILD_DIR}/tflm_compiled/Makefile; \
	fi
	@mkdir -p ${BUILD_DIR}/tflm_compiled/tflm_libs
	@{ \
		export PATH="${RISCV_GCC_ROOT}/bin/:$$PATH"; \
		cd ${BUILD_DIR}/tflm_compiled/tflm_libs && \
		cmake -DCMAKE_BUILD_TYPE=Debug -DTARGET_ARCH=rv32imac -DRISCV_ABI=ilp32 -DTOOLCHAIN=gcc \
		      -DCMAKE_C_COMPILER=riscv64-unknown-elf-gcc -DCMAKE_CXX_COMPILER=riscv64-unknown-elf-g++ ${TFLM_DIR}/my_tflm && \
		cmake --build . -- -j$$(nproc); \
	}
	$(eval PROGRAM := ${BUILD_DIR}/tflm_compiled/tflm)
	$(eval SIM_OPTIONS_COMMON := -DNO_TIMEOUT)

tflm: tflm_env e203
	$(eval SIM_OPTIONS_COMMON := -DNO_TIMEOUT)
	make dasm SOC=${SOC} SIM_ROOT_DIR=${SIM_ROOT_DIR} -C ${BUILD_DIR}/tflm_compiled/ -j$$(nproc)
	@if [ -e ${BUILD_DIR}/tflm_compiled/tflm.verilog ]; then \
		python3 ${SIM_ROOT_DIR}/deps/tools/split_memory.py ${BUILD_DIR}/tflm_compiled/tflm.verilog --force; \
		echo "Memory splitting completed"; \
	else \
		echo "tflm.verilog not found, skip memory split"; \
	fi
	${SIZE} --format=berkeley ${BUILD_DIR}/tflm_compiled/tflm.elf 
	make run SIM_ROOT_DIR=${SIM_ROOT_DIR} DUMPWAVE=${DUMPWAVE} SIM_TOOL=${SIM_TOOL} PROGRAM=${PROGRAM} -C ${BUILD_DIR} -j$$(nproc)
	

.PHONY: compile run install clean all e203 sim asm test test_all qemu compile_c compile_test_src debug_gdb debug_openocd debug_sim compile_benchmark_src dhrystone coremark tflm tflm_env

