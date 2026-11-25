// Apple's `Darwin` for wasm: the C library (WASILibc), and what Darwin declares beyond it that
// packages call in their `#if canImport(Darwin)` branches, which are their iOS code
// (combine-schedulers declares its timer's `Lock` over the unfair lock only there, which fails
// Mlem). Darwin's locks, atomics and clock constants are WebFoundation's, which Apple's
// Foundation brings with it from Darwin: they are re-exported by name, so a file that imports
// both modules sees one declaration of each. The mach clock is the C half (DarwinShims), where a
// type and a function share the name `mach_timebase_info` as they do in Apple's headers.
// SwiftUIWeb's own sources test for Apple's with `canImport(Darwin) && !os(WASI)`.
#if os(WASI)
@_exported import WASILibc
@_exported import DarwinShims

// os/lock.h, libkern/OSAtomic.h
@_exported import func WebFoundation.OSAtomicAdd32
@_exported import func WebFoundation.OSAtomicAdd32Barrier
@_exported import func WebFoundation.OSAtomicAdd64
@_exported import func WebFoundation.OSAtomicAdd64Barrier
@_exported import func WebFoundation.OSAtomicAnd32
@_exported import func WebFoundation.OSAtomicAnd32Barrier
@_exported import func WebFoundation.OSAtomicAnd32Orig
@_exported import func WebFoundation.OSAtomicAnd32OrigBarrier
@_exported import func WebFoundation.OSAtomicCompareAndSwap32
@_exported import func WebFoundation.OSAtomicCompareAndSwap32Barrier
@_exported import func WebFoundation.OSAtomicCompareAndSwap64
@_exported import func WebFoundation.OSAtomicCompareAndSwap64Barrier
@_exported import func WebFoundation.OSAtomicCompareAndSwapInt
@_exported import func WebFoundation.OSAtomicCompareAndSwapIntBarrier
@_exported import func WebFoundation.OSAtomicCompareAndSwapLong
@_exported import func WebFoundation.OSAtomicCompareAndSwapLongBarrier
@_exported import func WebFoundation.OSAtomicCompareAndSwapPtr
@_exported import func WebFoundation.OSAtomicCompareAndSwapPtrBarrier
@_exported import func WebFoundation.OSAtomicDecrement32
@_exported import func WebFoundation.OSAtomicDecrement32Barrier
@_exported import func WebFoundation.OSAtomicDecrement64
@_exported import func WebFoundation.OSAtomicDecrement64Barrier
@_exported import func WebFoundation.OSAtomicIncrement32
@_exported import func WebFoundation.OSAtomicIncrement32Barrier
@_exported import func WebFoundation.OSAtomicIncrement64
@_exported import func WebFoundation.OSAtomicIncrement64Barrier
@_exported import func WebFoundation.OSAtomicOr32
@_exported import func WebFoundation.OSAtomicOr32Barrier
@_exported import func WebFoundation.OSAtomicOr32Orig
@_exported import func WebFoundation.OSAtomicOr32OrigBarrier
@_exported import func WebFoundation.OSAtomicTestAndClear
@_exported import func WebFoundation.OSAtomicTestAndClearBarrier
@_exported import func WebFoundation.OSAtomicTestAndSet
@_exported import func WebFoundation.OSAtomicTestAndSetBarrier
@_exported import func WebFoundation.OSAtomicXor32
@_exported import func WebFoundation.OSAtomicXor32Barrier
@_exported import func WebFoundation.OSAtomicXor32Orig
@_exported import func WebFoundation.OSAtomicXor32OrigBarrier
@_exported import func WebFoundation.OSMemoryBarrier
@_exported import typealias WebFoundation.OSSpinLock
@_exported import func WebFoundation.OSSpinLockLock
@_exported import func WebFoundation.OSSpinLockTry
@_exported import func WebFoundation.OSSpinLockUnlock
@_exported import var WebFoundation.OS_SPINLOCK_INIT
@_exported import typealias WebFoundation.os_unfair_lock
@_exported import func WebFoundation.os_unfair_lock_assert_not_owner
@_exported import func WebFoundation.os_unfair_lock_assert_owner
@_exported import func WebFoundation.os_unfair_lock_lock
@_exported import struct WebFoundation.os_unfair_lock_s
@_exported import typealias WebFoundation.os_unfair_lock_t
@_exported import func WebFoundation.os_unfair_lock_trylock
@_exported import func WebFoundation.os_unfair_lock_unlock

// pthread.h: the mutexes and read-write locks the WASI C library declares only for threaded builds
@_exported import var WebFoundation.PTHREAD_MUTEX_DEFAULT
@_exported import var WebFoundation.PTHREAD_MUTEX_ERRORCHECK
@_exported import var WebFoundation.PTHREAD_MUTEX_NORMAL
@_exported import var WebFoundation.PTHREAD_MUTEX_RECURSIVE
@_exported import func WebFoundation.pthread_mutex_destroy
@_exported import func WebFoundation.pthread_mutex_init
@_exported import func WebFoundation.pthread_mutex_lock
@_exported import func WebFoundation.pthread_mutex_trylock
@_exported import func WebFoundation.pthread_mutex_unlock
@_exported import func WebFoundation.pthread_mutexattr_destroy
@_exported import func WebFoundation.pthread_mutexattr_init
@_exported import func WebFoundation.pthread_mutexattr_settype
@_exported import func WebFoundation.pthread_rwlock_destroy
@_exported import func WebFoundation.pthread_rwlock_init
@_exported import func WebFoundation.pthread_rwlock_rdlock
@_exported import func WebFoundation.pthread_rwlock_tryrdlock
@_exported import func WebFoundation.pthread_rwlock_trywrlock
@_exported import func WebFoundation.pthread_rwlock_unlock
@_exported import func WebFoundation.pthread_rwlock_wrlock

// mach/clock_types.h
@_exported import var WebFoundation.NSEC_PER_SEC
@_exported import var WebFoundation.NSEC_PER_MSEC
@_exported import var WebFoundation.NSEC_PER_USEC
@_exported import var WebFoundation.USEC_PER_SEC
@_exported import var WebFoundation.MSEC_PER_SEC
#endif
