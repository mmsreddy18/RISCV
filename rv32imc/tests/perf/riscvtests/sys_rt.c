/* Minimal bare-metal runtime for the riscv-tests benchmarks on rv32imc_sys.
 * ROI markers = MMIO 0x1000_0008 (start) / 0x1000_000C (stop). No HTIF, no CSR counters. */
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#define MMIO(o) (*(volatile uint32_t *)(0x10000000u + (o)))
void setStats(int enable) { if (enable) MMIO(8) = 1; else MMIO(0xC) = 1; }
void __attribute__((noreturn)) tohost_exit(uintptr_t code) { MMIO(0) = (uint32_t)((code << 1) | 1); for (;;); }
int printf(const char *f, ...) { (void)f; return 0; }
int puts(const char *s) { (void)s; return 0; }
void *memcpy(void *d, const void *s, size_t n)
{ unsigned char *dd = d; const unsigned char *ss = s; while (n--) *dd++ = *ss++; return d; }
void *memset(void *d, int c, size_t n)
{ unsigned char *dd = d; while (n--) *dd++ = (unsigned char)c; return d; }
int memcmp(const void *a, const void *b, size_t n)
{ const unsigned char *x = a, *y = b; while (n--) { if (*x != *y) return *x - *y; x++; y++; } return 0; }
size_t strlen(const char *s) { size_t n = 0; while (*s++) n++; return n; }
char *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++)); return r; }
int strcmp(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *(unsigned char *)a - *(unsigned char *)b; }
