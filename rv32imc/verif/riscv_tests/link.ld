/* Layout for running riscv-tests on tb_core: code at 0, data at 0x4000, `tohost` at the testbench's result address. */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x0;
  .text.init : { *(.text.init) }
  .text : { *(.text) }
  . = 0x4000;
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
  .tohost 0x10000000 (NOLOAD) : { *(.tohost) }
}
