#if os(WASI)
import WASILibc

// POSIX mutexes, which Apple's Foundation brings with Darwin, and the WASI C library declares
// only for threaded builds: a page runs one thread, so each call succeeds at once (as the
// locks in WebFoundation's Threading.swift do). SwiftSoup's `Mutex` is built on these. They
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
#endif
