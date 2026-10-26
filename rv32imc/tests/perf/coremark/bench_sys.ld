/* rv32imc_sys layout: code in the instruction memory (0x0, 32 KiB), read-only data + data + bss + stack in the
   data memory (0x10000, 32 KiB). */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text.init) *(.text*) }
  . = 0x10000;
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.sdata*) *(.data*) }
  .bss  : { *(.sbss*) *(.bss*) *(COMMON) }
  _stack_top = 0x17ff0;
}
