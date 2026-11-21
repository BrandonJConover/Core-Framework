/*
 * Prefix header for the RSCEngine target (GCC_PREFIX_HEADER).
 *
 * system() is unavailable on iOS, but rsc-c calls it to open wiki links in a
 * desktop browser. Pull in stdlib.h first so its declaration is untouched, then
 * route later calls to a stub in rsc_sdl_shim.c.
 */
#ifndef RSC_IOS_PREFIX_H
#define RSC_IOS_PREFIX_H

#include <stdlib.h>

int rsc_ios_system(const char *command);
#define system(command) rsc_ios_system(command)

#endif
