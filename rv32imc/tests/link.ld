OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text.init) *(.text*) }
  . = 0x4000;
  .data : { *(.data*) *(.bss*) }
}
