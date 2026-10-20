#ifndef PORT_STRING_H
#define PORT_STRING_H
#include <stddef.h>
char *strcpy(char *d, const char *s);
int strcmp(const char *a, const char *b);
void *memcpy(void *d, const void *s, size_t n);
void *memset(void *d, int c, size_t n);
size_t strlen(const char *s);
#endif
