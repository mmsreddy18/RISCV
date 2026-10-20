OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS { . = 0x40000; .text : { *(.text.init) *(.text*) } }
