// The C half of the `Darwin` shadow (wasm only): the mach clock, declared as Apple's headers
// declare it, so the type and the function `mach_timebase_info` share their name as on iOS.
#ifndef DARWIN_SHIMS_H
#define DARWIN_SHIMS_H

#include <stdint.h>
#include <time.h>

// mach/mach_time.h: absolute time counts nanoseconds, so the timebase is 1/1.
typedef int kern_return_t;
#define KERN_SUCCESS 0

struct mach_timebase_info {
    uint32_t numer;
    uint32_t denom;
};
typedef struct mach_timebase_info *mach_timebase_info_t;
typedef struct mach_timebase_info mach_timebase_info_data_t;

static inline kern_return_t mach_timebase_info(mach_timebase_info_t info) {
    info->numer = 1;
    info->denom = 1;
    return KERN_SUCCESS;
}
static inline uint64_t mach_absolute_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}
static inline uint64_t mach_continuous_time(void) { return mach_absolute_time(); }
static inline uint64_t mach_approximate_time(void) { return mach_absolute_time(); }

#endif
