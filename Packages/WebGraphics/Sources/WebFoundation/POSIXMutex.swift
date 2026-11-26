#if os(WASI)
import WASILibc

// POSIX mutexes and read-write locks, which Apple's Foundation brings with Darwin, and the WASI C library declares
// only for threaded builds: a page runs one thread, so each call succeeds at once (as the
// locks in WebFoundation's Threading.swift do). SwiftSoup's `Mutex` is built on these, and
// swift-log's `ReadWriteLock` (in the releases from before it checked for a threaded runtime,
// which Clendar pins) on the read-write ones. They
// are here, not in the Foundation shadow, because UIKit and SwiftUI re-export Foundation too:
// Resolver's iOS branch imports only UIKit and SwiftUI and locks with them (MakeItSo).
// The attributes are taken untyped: callers pass nil or their own attribute value, which the
// attribute calls below accept and leave as they are (combine-schedulers and Resolver ask for
// an error-checking or a recursive mutex, which one thread cannot tell from a plain one).
@discardableResult
public func pthread_mutex_init(_ mutex: UnsafeMutablePointer<pthread_mutex_t>?, _ attributes: UnsafeRawPointer?) -> Int32 { 0 }
@discardableResult
public func pthread_mutex_destroy(_ mutex: UnsafeMutablePointer<pthread_mutex_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_mutex_lock(_ mutex: UnsafeMutablePointer<pthread_mutex_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_mutex_trylock(_ mutex: UnsafeMutablePointer<pthread_mutex_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_mutex_unlock(_ mutex: UnsafeMutablePointer<pthread_mutex_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_mutexattr_init(_ attributes: UnsafeMutableRawPointer?) -> Int32 { 0 }
@discardableResult
public func pthread_mutexattr_destroy(_ attributes: UnsafeMutableRawPointer?) -> Int32 { 0 }
@discardableResult
public func pthread_mutexattr_settype(_ attributes: UnsafeMutableRawPointer?, _ type: Int32) -> Int32 { 0 }
public var PTHREAD_MUTEX_NORMAL: Int32 { 0 }
public var PTHREAD_MUTEX_RECURSIVE: Int32 { 1 }
public var PTHREAD_MUTEX_ERRORCHECK: Int32 { 2 }
public var PTHREAD_MUTEX_DEFAULT: Int32 { 0 }

@discardableResult
public func pthread_rwlock_init(_ lock: UnsafeMutablePointer<pthread_rwlock_t>?, _ attributes: UnsafeRawPointer?) -> Int32 { 0 }
@discardableResult
public func pthread_rwlock_destroy(_ lock: UnsafeMutablePointer<pthread_rwlock_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_rwlock_rdlock(_ lock: UnsafeMutablePointer<pthread_rwlock_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_rwlock_tryrdlock(_ lock: UnsafeMutablePointer<pthread_rwlock_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_rwlock_wrlock(_ lock: UnsafeMutablePointer<pthread_rwlock_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_rwlock_trywrlock(_ lock: UnsafeMutablePointer<pthread_rwlock_t>?) -> Int32 { 0 }
@discardableResult
public func pthread_rwlock_unlock(_ lock: UnsafeMutablePointer<pthread_rwlock_t>?) -> Int32 { 0 }
// Darwin's length of each `utsname` field, which code reading `uname`'s machine name passes as
// the byte count (Mlem's device model). The WASI C library's fields are shorter, so this is
// their length here, and a read of that many bytes stays inside the field.
public var _SYS_NAMELEN: Int32 { Int32(MemoryLayout.size(ofValue: utsname().machine)) }
#endif
