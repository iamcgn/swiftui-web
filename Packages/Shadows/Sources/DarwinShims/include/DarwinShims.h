// The C half of the `Darwin` shadow (wasm only): the declarations Apple's Darwin has beyond the C
// library, as the C headers declare them, so a type and a function can share a name
// (`mach_timebase_info`) as they do on iOS. The wasm target runs one thread: the unfair lock
// records whether it is held and orders nothing.
#ifndef DARWIN_SHIMS_H
#define DARWIN_SHIMS_H

#include <stdint.h>
#include <time.h>

// os/lock.h
typedef struct os_unfair_lock_s {
    uint32_t _os_unfair_lock_opaque;
} os_unfair_lock, *os_unfair_lock_t;

static inline void os_unfair_lock_lock(os_unfair_lock_t lock) { lock->_os_unfair_lock_opaque = 1; }
static inline _Bool os_unfair_lock_trylock(os_unfair_lock_t lock) {
    if (lock->_os_unfair_lock_opaque != 0) return 0;
    lock->_os_unfair_lock_opaque = 1;
    return 1;
}
static inline void os_unfair_lock_unlock(os_unfair_lock_t lock) { lock->_os_unfair_lock_opaque = 0; }
static inline void os_unfair_lock_assert_owner(const os_unfair_lock *lock) {
    if (lock->_os_unfair_lock_opaque == 0) __builtin_trap();
}
static inline void os_unfair_lock_assert_not_owner(const os_unfair_lock *lock) {
    if (lock->_os_unfair_lock_opaque != 0) __builtin_trap();
}

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
