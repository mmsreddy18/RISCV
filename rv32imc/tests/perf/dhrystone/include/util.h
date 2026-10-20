/* Port shim: replaces riscv-tests' benchmarks/common/util.h. No CSRs exist on this core, so the
 * "cycle counter" is fake (it only has to make Dhrystone's time check pass); real timing comes from
 * the testbench, which snapshots its counters on the setStats() marker stores. */
#ifndef __UTIL_H
#define __UTIL_H
#include <stdint.h>
void setStats(int enable);
static inline long port_fake_cycle(void) { static long t; t += 1000000; return t; }
#define read_csr(r) port_fake_cycle()
#endif
