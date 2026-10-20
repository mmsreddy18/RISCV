/* Harvard layout: code in ITCM (0x0), read-only data + data + bss + stack in DTCM (0x20000..0x3ffff) */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text.init) *(.text*) }
  . = 0x20000;
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.sdata*) *(.data*) }
  .bss  : { *(.sbss*) *(.bss*) *(COMMON) }
  _stack_top = 0x3fff0;
}
