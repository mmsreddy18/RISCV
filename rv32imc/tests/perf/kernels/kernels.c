/* Small integer kernels for CPI-stack analysis. One kernel per build (-DK=<id>).
 * Built for the core (freestanding) and, with -DHOST, natively to compute the expected checksum. */
#ifdef HOST
#include <stdio.h>
#define ROI_ON()
#define ROI_OFF()
static void out_hex(unsigned v) { printf("%08x\n", v); }
#else
#define ROI_ON()  (*(volatile unsigned *)0x10000008u = 1)
#define ROI_OFF() (*(volatile unsigned *)0x1000000Cu = 1)
static void out_hex(unsigned v)
{
    for (int i = 28; i >= 0; i -= 4) { unsigned d = (v >> i) & 15; *(volatile unsigned *)0x10000004u = d < 10 ? '0' + d : 'a' + d - 10; }
    *(volatile unsigned *)0x10000004u = '\n';
}
#endif

static unsigned lcg_state = 12345;
static unsigned lcg(void) { lcg_state = lcg_state * 1664525u + 1013904223u; return lcg_state; }

#define MATMUL 1
#define BSORT  2
#define CRC32  3
#define MEMCPY 4
#define FIR    5
#define LIST   6
#define GCD    7
#define SIEVE  8
#define FIB    9

#if K == MATMUL
#define N 16
static int A[N][N], B[N][N], C[N][N];
static unsigned run(void)
{
    for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) { A[i][j] = (int)(lcg() & 0xff) - 128; B[i][j] = (int)(lcg() & 0xff) - 128; }
    ROI_ON();
    for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) { int s = 0; for (int k = 0; k < N; k++) s += A[i][k] * B[k][j]; C[i][j] = s; }
    ROI_OFF();
    unsigned h = 0; for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) h = h * 31 + (unsigned)C[i][j];
    return h;
}
#elif K == BSORT
#define N 128
static int V[N];
static unsigned run(void)
{
    for (int i = 0; i < N; i++) V[i] = (int)(lcg() >> 8);
    ROI_ON();
    for (int i = 0; i < N - 1; i++) for (int j = 0; j < N - 1 - i; j++) if (V[j] > V[j + 1]) { int t = V[j]; V[j] = V[j + 1]; V[j + 1] = t; }
    ROI_OFF();
    unsigned h = 0; for (int i = 0; i < N; i++) h = h * 33 + (unsigned)V[i];
    return h;
}
#elif K == CRC32
#define N 1024
static unsigned char buf[N];
static unsigned run(void)
{
    for (int i = 0; i < N; i++) buf[i] = (unsigned char)lcg();
    ROI_ON();
    unsigned crc = 0xffffffffu;
    for (int i = 0; i < N; i++) { crc ^= buf[i]; for (int b = 0; b < 8; b++) crc = (crc >> 1) ^ (0xEDB88320u & -(crc & 1)); }
    ROI_OFF();
    return ~crc;
}
#elif K == MEMCPY
#define N 512
static unsigned src[N], dst[N];
static unsigned run(void)
{
    for (int i = 0; i < N; i++) src[i] = lcg();
    ROI_ON();
    for (int r = 0; r < 4; r++) for (int i = 0; i < N; i++) dst[i] = src[i];
    ROI_OFF();
    unsigned h = 0; for (int i = 0; i < N; i++) h = h * 31 + dst[i];
    return h;
}
#elif K == FIR
#define NS 256
#define NT 32
static short x[NS + NT], h[NT];
static int y[NS];
static unsigned run(void)
{
    for (int i = 0; i < NS + NT; i++) x[i] = (short)lcg();
    for (int i = 0; i < NT; i++) h[i] = (short)(lcg() >> 4);
    ROI_ON();
    for (int n = 0; n < NS; n++) { int acc = 0; for (int t = 0; t < NT; t++) acc += x[n + t] * h[t]; y[n] = acc >> 8; }
    ROI_OFF();
    unsigned s = 0; for (int i = 0; i < NS; i++) s = s * 31 + (unsigned)y[i];
    return s;
}
#elif K == LIST
#define N 256
struct node { struct node *next; unsigned val; };
static struct node nodes[N];
static unsigned perm[N];
static unsigned run(void)
{
    for (unsigned i = 0; i < N; i++) perm[i] = i;
    for (unsigned i = N - 1; i > 0; i--) { unsigned j = lcg() % (i + 1); unsigned t = perm[i]; perm[i] = perm[j]; perm[j] = t; }
    for (unsigned i = 0; i < N; i++) { nodes[perm[i]].next = &nodes[perm[(i + 1) % N]]; nodes[perm[i]].val = lcg(); }
    ROI_ON();
    unsigned sum = 0; struct node *p = &nodes[perm[0]];
    for (int r = 0; r < 20 * N; r++) { sum += p->val; p = p->next; }
    ROI_OFF();
    return sum;
}
#elif K == GCD
static unsigned run(void)
{
    unsigned s = 0;
    unsigned a[200], b[200];
    for (int i = 0; i < 200; i++) { a[i] = (lcg() >> 4) | 1; b[i] = (lcg() >> 8) | 1; }
    ROI_ON();
    for (int i = 0; i < 200; i++) { unsigned x = a[i], y = b[i]; while (y) { unsigned t = x % y; x = y; y = t; } s += x; }
    ROI_OFF();
    return s;
}
#elif K == SIEVE
#define N 2048
static unsigned char comp[N];
static unsigned run(void)
{
    ROI_ON();
    for (int i = 2; i * i < N; i++) if (!comp[i]) for (int j = i * i; j < N; j += i) comp[j] = 1;
    ROI_OFF();
    unsigned c = 0; for (int i = 2; i < N; i++) c += !comp[i];
    return c;
}
#elif K == FIB
static unsigned fib(unsigned n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
static unsigned run(void)
{
    ROI_ON();
    unsigned r = fib(18);
    ROI_OFF();
    return r;
}
#endif

int main(void) { out_hex(run()); return 0; }
