/*
 * Copyright (c) 2019 Nuclei Limited. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the License); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
/******************************************************************************
 * @file     gcc_hbird_ilm.ld
 * @brief    GNU Linker Script for HummingBird RISC-V device in ilm Download Mode
 * @version  V1.0.0
 * @date     14. Jul 2020
 ******************************************************************************/

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ilm     (rxai!w) : ORIGIN = 0x80000000, LENGTH = 128K
    extram  (rxai!w) : ORIGIN = 0x00080000, LENGTH = 512K
    ram     (wxa!ri) : ORIGIN = 0x90000000, LENGTH = 128K
}

SECTIONS
{
    /* Startup and critical code in ILM */
    .init :
    {
        *(.vtable)
        KEEP(*(SORT_NONE(.init)))
    } >ilm AT>ilm

    .ilalign :
    {
        . = ALIGN(4);
        PROVIDE(_ilm_lma = .);
    } >ilm AT>ilm

    .ialign :
    {
        PROVIDE(_ilm = .);
    } >ilm AT>ilm

    /* Basic text sections in ILM */
    .text :
    {
        *(.text.unlikely .text.unlikely.*)
        *(.text.startup .text.startup.*)
        *(.text)
        *(.gnu.linkonce.t.*)
    } >ilm AT>ilm

    /* User text sections in EXTRAM */
    .text_ext :
    {
        *(.text.*)
    } >ilm AT>ilm

    /* 将只保留启动相关 / 关键只读数据放在 ILM */
    .rodata : ALIGN(4)
    {
        . = ALIGN(4);
        *(.rdata)                       /* 小型只读/只写常量，保留在 ILM */
        
        /* Section information for initial (keep in ILM so startup 可访问) */
        . = ALIGN(4);
        __rt_init_start = .;
        KEEP(*(SORT(.rti_fn*)))
        __rt_init_end = .;
        
        /* Section information for finsh shell (keep in ILM) */
        . = ALIGN(4);
        __fsymtab_start = .;
        KEEP(*(FSymTab))
        __fsymtab_end = .;
        . = ALIGN(4);
        __vsymtab_start = .;
        KEEP(*(VSymTab))
        __vsymtab_end = .;
        
        *(.gnu.linkonce.r.*)
    } >ilm AT>ilm

    .fini :
    {
        KEEP(*(SORT_NONE(.fini)))
    } >ilm AT>ilm

    . = ALIGN(4);
    PROVIDE(__etext = .);
    PROVIDE(_etext = .);
    PROVIDE(etext = .);
    PROVIDE(_eilm = .);

    .preinit_array :
    {
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } >ilm AT>ilm

    .init_array :
    {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
        KEEP(*(.init_array EXCLUDE_FILE(*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o) .ctors))
        PROVIDE_HIDDEN(__init_array_end = .);
    } >ilm AT>ilm

    .fini_array :
    {
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
        KEEP(*(.fini_array EXCLUDE_FILE(*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o) .dtors))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } >ilm AT>ilm

    .ctors :
    {
        KEEP(*crtbegin.o(.ctors))
        KEEP(*crtbegin?.o(.ctors))
        KEEP(*(EXCLUDE_FILE(*crtend.o *crtend?.o) .ctors))
        KEEP(*(SORT(.ctors.*)))
        KEEP(*(.ctors))
    } >ilm AT>ilm

    .dtors :
    {
        KEEP(*crtbegin.o(.dtors))
        KEEP(*crtbegin?.o(.dtors))
        KEEP(*(EXCLUDE_FILE(*crtend.o *crtend?.o) .dtors))
        KEEP(*(SORT(.dtors.*)))
        KEEP(*(.dtors))
    } >ilm AT>ilm

    .lalign :
    {
        . = ALIGN(4);
        PROVIDE(_data_lma = .);
    } >ilm AT>ilm

    .dalign :
    {
        . = ALIGN(4);
        PROVIDE(_data = .);
    } >ram AT>ilm

    /* Data sections in RAM */
    .data :
    {
        *(.data .data.*)
        *(.gnu.linkonce.d.*)
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata .sdata.* .sdata*)
        *(.gnu.linkonce.s.*)
        . = ALIGN(4);
        *(.srodata.cst16)
        *(.srodata.cst8)
        *(.srodata.cst4)
        *(.srodata.cst2)
        *(.srodata .srodata.*)
    } >ram AT>ilm

    . = ALIGN(4);
    PROVIDE(_edata = .);
    PROVIDE(edata = .);

    /* 将大块、非必须快速访问的只读数据放到 EXTRAM（VMA/LMA 都在 extram） */
    .rodata_extram : ALIGN(4)
    {
        . = ALIGN(4);
        *(.rodata .rodata.*)             /* 主要只读数据移动到 EXTRAM */
        /* 可按需添加更多只读子节 */
    } >extram AT>extram

    /* 将栈大小固定为 16K（避免原先以剩余空间作为栈） */
    /* 16K = 0x4000 */
    __stack_size = DEFINED(__stack_size) ? __stack_size : 16K;

    /* BSS sections in EXTRAM */
    .bss :
    {
        PROVIDE(_fbss = .);
        PROVIDE(__bss_start = .);
        *(.sbss*)
        *(.gnu.linkonce.sb.*)
        *(.bss .bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON)
        . = ALIGN(4);
        PROVIDE(_end = .);
        PROVIDE(end = .);
        /* 补充常用的 bss 结束符号 */
        PROVIDE(__bss_end = .);
    } >extram AT>extram

    /* 堆放在 RAM，使用 NOLOAD，堆起始紧跟 _edata，堆顶位于 RAM 顶部减去 __stack_size（为栈保留空间） */
    .heap (NOLOAD) :
    {
        . = ALIGN(4);
        /* 起始地址紧跟 .bss/.data/_edata 之后 */
        PROVIDE(__heap_start = .);
        PROVIDE(_heap_start = __heap_start);
        PROVIDE(heap_start = __heap_start);
        /* newlib 及部分 BSP 可能使用的别名 */
        PROVIDE(__malloc_sbrk_base = __heap_start);
        PROVIDE(__malloc_heap_start = __heap_start);

        /* 将位置推进到 RAM 顶部，留出 __stack_size 作为栈 */
        . = ORIGIN(ram) + LENGTH(ram) - __stack_size;
        . = ALIGN(4);
        PROVIDE(__heap_end = .);
        PROVIDE(_heap_end = __heap_end);
        PROVIDE(heap_end = __heap_end);
        /* 兼容 CMSIS/ARM 风格的别名 */
        PROVIDE(__HeapBase = __heap_start);
        PROVIDE(__HeapLimit = __heap_end);
        PROVIDE(__heap_limit = __heap_end);
        PROVIDE(__malloc_heap_end = __heap_end);

        /* 计算堆大小 */
        PROVIDE(__heap_size = __heap_end - __heap_start);
        PROVIDE(_heap_size = __heap_size);
    } >ram

    /* 栈仍在 RAM，固定大小为上面定义的 __stack_size（16K） */
    .stack (NOLOAD) :
    {
        /* place stack at top of RAM, size is __stack_size defined above */
        . = ORIGIN(ram) + LENGTH(ram) - __stack_size;
        PROVIDE(_stack_start = .);
        /* move to top */
        . = ORIGIN(ram) + LENGTH(ram);
        PROVIDE(_stack_end = .);
        /* initial stack pointer at top */
        PROVIDE(_sp = _stack_end);
        /* expose computed size (alias to the fixed value) */
        PROVIDE(__stack_size = __stack_size);
        PROVIDE(__StackLimit = _stack_start);
        PROVIDE(__StackTop = _stack_end);
        /* 兼容更多命名 */
        PROVIDE(__stack_limit = __StackLimit);
        PROVIDE(__stack_top = __StackTop);
    } >ram

    /* 断言：确保还有可用堆空间，避免运行时越界 */
    ASSERT(__heap_end > __heap_start, "No heap space left in RAM, .data/.bss too large or RAM too small")

}
