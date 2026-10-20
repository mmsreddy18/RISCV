OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text.init) *(.text*) *(.rodata*) *(.srodata*) }
  . = 0x10000;
  .data : { *(.sdata*) *(.data*) }
  .bss  : { *(.sbss*) *(.bss*) *(COMMON) }
  _stack_top = 0x3fff0;
}
