OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text.init) *(.text*) }
  . = 0x4000;
  .data : { *(.data*) *(.bss*) }
  . = 0x3BFFC;
  .hj : { *(.hj) }          /* c.jr at 0x3BFFC: the word after it (0x3C000) is an error word */
  . = 0x3BFFE;
  .hs : { *(.hs) }          /* 32-bit instruction straddling 0x3BFFC|0x3C000 */
}
