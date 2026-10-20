#include <stdarg.h>
#include <stddef.h>
#define MMIO_PUTCHAR (*(volatile unsigned *)0x10000004u)
#define MMIO_ROI_ON  (*(volatile unsigned *)0x10000008u)
#define MMIO_ROI_OFF (*(volatile unsigned *)0x1000000Cu)

void setStats(int enable) { if (enable) MMIO_ROI_ON = 1; else MMIO_ROI_OFF = 1; }

static void putc_(char c) { MMIO_PUTCHAR = (unsigned char)c; }
static void put_num(unsigned long v, int base, int neg)
{
    char buf[24]; int n = 0;
    if (v == 0) buf[n++] = '0';
    while (v) { unsigned d = v % base; buf[n++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v /= base; }
    if (neg) buf[n++] = '-';
    while (n) putc_(buf[--n]);
}
static int vp(const char *fmt, va_list ap)
{
    for (; *fmt; fmt++) {
        if (*fmt != '%') { putc_(*fmt); continue; }
        fmt++;
        while (*fmt == 'l') fmt++;
        switch (*fmt) {
        case 'd': { long v = va_arg(ap, int); put_num(v < 0 ? -v : v, 10, v < 0); break; }
        case 'u': put_num(va_arg(ap, unsigned), 10, 0); break;
        case 'x': put_num(va_arg(ap, unsigned), 16, 0); break;
        case 'c': putc_((char)va_arg(ap, int)); break;
        case 's': { const char *s = va_arg(ap, const char *); while (*s) putc_(*s++); break; }
        default: putc_('?'); break;
        }
    }
    return 0;
}
int printf(const char *fmt, ...) { va_list ap; va_start(ap, fmt); vp(fmt, ap); va_end(ap); return 0; }
void debug_printf(const char *fmt, ...) { va_list ap; va_start(ap, fmt); vp(fmt, ap); va_end(ap); }

/* strcpy/strcmp run inside the timed Dhrystone loop, so their quality matters a lot.
 * Default: plain byte loops. With -DFAST_STR: word-at-a-time fast path when both pointers are
 * word aligned (the structure production libc string routines use), byte loop for the tail. */
#ifndef FAST_STR
char *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++)) ; return r; }
int strcmp(const char *a, const char *b)
{ while (*a && *a == *b) { a++; b++; } return (unsigned char)*a - (unsigned char)*b; }
#else
#define HAS_ZERO(w) (((w) - 0x01010101u) & ~(w) & 0x80808080u)
char *strcpy(char *d, const char *s)
{
    char *r = d;
    if ((((unsigned)d | (unsigned)s) & 3) == 0) {
        for (;;) {
            unsigned w = *(const unsigned *)s;
            if (HAS_ZERO(w)) break;
            *(unsigned *)d = w; d += 4; s += 4;
        }
    }
    while ((*d++ = *s++)) ;
    return r;
}
int strcmp(const char *a, const char *b)
{
    if ((((unsigned)a | (unsigned)b) & 3) == 0) {
        for (;;) {
            unsigned x = *(const unsigned *)a, y = *(const unsigned *)b;
            if (x != y || HAS_ZERO(x)) break;
            a += 4; b += 4;
        }
    }
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}
#endif
void *memcpy(void *d, const void *s, size_t n)
{ unsigned char *dd = d; const unsigned char *ss = s; while (n--) *dd++ = *ss++; return d; }
void *memset(void *d, int c, size_t n)
{ unsigned char *dd = d; while (n--) *dd++ = (unsigned char)c; return d; }
size_t strlen(const char *s) { size_t n = 0; while (*s++) n++; return n; }
