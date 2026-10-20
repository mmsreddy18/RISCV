/* Freestanding helpers the compiler may call. Built with -fno-tree-loop-distribute-patterns
 * so these loops are not turned back into calls to themselves. */
#include <stddef.h>
void *memcpy(void *d, const void *s, size_t n)
{ unsigned char *dd = d; const unsigned char *ss = s; while (n--) *dd++ = *ss++; return d; }
void *memset(void *d, int c, size_t n)
{ unsigned char *dd = d; while (n--) *dd++ = (unsigned char)c; return d; }
int memcmp(const void *a, const void *b, size_t n)
{ const unsigned char *x = a, *y = b; while (n--) { if (*x != *y) return *x - *y; x++; y++; } return 0; }
size_t strlen(const char *s) { size_t n = 0; while (*s++) n++; return n; }
