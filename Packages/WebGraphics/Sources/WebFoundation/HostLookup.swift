// The C resolver calls that packages reach through Apple's Foundation (which re-exports
// Darwin) and the wasm SDK's libc leaves out: `gethostbyname` and `inet_ntoa`. RevenueCat
// resolves its API host this way to tell a blocked request from a network failure. A page
// can't resolve names itself (the browser resolves them as it fetches), so a lookup finds
// nothing, the answer a resolver gives for an unknown name, and the caller carries on as
// it does then; `inet_ntoa` formats an address as Darwin's does.
#if os(WASI)
import WASILibc

/// An entry from the host database, as `<netdb.h>` declares it.
public struct hostent {
    public var h_name: UnsafeMutablePointer<CChar>?
    public var h_aliases: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    public var h_addrtype: Int32
    public var h_length: Int32
    public var h_addr_list: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>!

    public init() {
        h_name = nil; h_aliases = nil; h_addrtype = 0; h_length = 0; h_addr_list = nil
    }
}

/// `h_errno`'s value when the name isn't found.
public let HOST_NOT_FOUND: Int32 = 1

/// Looks a host name up: a page has no resolver of its own, so nothing is found.
public func gethostbyname(_ name: UnsafePointer<CChar>!) -> UnsafeMutablePointer<hostent>! { nil }

/// Looks a host name up for an address family: nothing is found, as for `gethostbyname`.
public func gethostbyname2(_ name: UnsafePointer<CChar>!, _ family: Int32) -> UnsafeMutablePointer<hostent>! { nil }

/// The text `inet_ntoa` answers: one buffer, overwritten by each call, as C's is.
nonisolated(unsafe) private let _inetNtoaBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: 16)

/// An IPv4 address as dotted-decimal text ("192.0.2.1"). The address is in network byte order;
/// the text lives in one buffer that the next call overwrites.
public func inet_ntoa(_ address: in_addr) -> UnsafeMutablePointer<CChar>! {
    let value = UInt32(bigEndian: address.s_addr)
    let text = "\(value >> 24).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    let bytes = Array(text.utf8CString)
    for (i, byte) in bytes.enumerated() { _inetNtoaBuffer[i] = byte }
    return _inetNtoaBuffer
}
#endif
