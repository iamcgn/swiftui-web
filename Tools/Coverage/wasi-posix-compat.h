/* POSIX calls that wasi-libc leaves out because WASI has no way to make them. The sweep
   force-includes this header into a C target that calls one without declaring it, so the
   package builds unmodified and the call fails at run time the way it does on a system
   without the capability. Upstream tree-sitter's own WASI build makes its one `dup` call
   (a debug graph printer) do nothing; Runestone's vendored copy predates that guard. */
#ifndef SWIFTUIWEB_WASI_POSIX_COMPAT_H
#define SWIFTUIWEB_WASI_POSIX_COMPAT_H
#if defined(__wasi__)
#include <errno.h>
static inline int dup(int fd) { (void)fd; errno = ENOSYS; return -1; }
#endif
#endif
