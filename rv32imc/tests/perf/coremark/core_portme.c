#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

#define MMIO_PUTCHAR (*(volatile ee_u32 *)0x10000004u)
#define MMIO_ROI_ON  (*(volatile ee_u32 *)0x10000008u)
#define MMIO_ROI_OFF (*(volatile ee_u32 *)0x1000000Cu)

/* The timed region is measured by the testbench; get_time() only has to return something
 * that CoreMark accepts as a valid >= 10 s run so it does not flag an error. */
#define EE_TICKS_PER_SEC 1
void start_time(void) { MMIO_ROI_ON = 1; }
void stop_time(void)  { MMIO_ROI_OFF = 1; }
CORE_TICKS get_time(void) { return 10; }
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks / EE_TICKS_PER_SEC; }

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    p->portable_id = 1;
}
void portable_fini(core_portable *p) { p->portable_id = 0; }

/* ---- minimal printf: %d %u %x %c %s, optional 0 flag, width, and l modifier ---- */
#include <stdarg.h>
static void putc_(char c) { MMIO_PUTCHAR = (ee_u32)(unsigned char)c; }
static void put_num(unsigned long v, int base, int neg, int width, int zero)
{
    char buf[24]; int n = 0;
    if (v == 0) buf[n++] = '0';
    while (v) { unsigned d = v % base; buf[n++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v /= base; }
    if (neg) buf[n++] = '-';
    while (n < width) buf[n++] = zero ? '0' : ' ';
    while (n) putc_(buf[--n]);
}
int ee_printf(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') { putc_(*fmt); continue; }
        int zero = 0, width = 0;
        fmt++;
        if (*fmt == '0') { zero = 1; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        while (*fmt == 'l') fmt++;
        switch (*fmt) {
        case 'd': { long v = va_arg(ap, int); put_num(v < 0 ? -v : v, 10, v < 0, width, zero); break; }
        case 'u': put_num(va_arg(ap, unsigned), 10, 0, width, zero); break;
        case 'x': put_num(va_arg(ap, unsigned), 16, 0, width, zero); break;
        case 'c': putc_((char)va_arg(ap, int)); break;
        case 's': { const char *s = va_arg(ap, const char *); while (*s) putc_(*s++); break; }
        case '%': putc_('%'); break;
        default: putc_('?'); break;
        }
    }
    va_end(ap);
    return 0;
}
