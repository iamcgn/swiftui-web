// Security's certificate trust types and functions on wasm (Alamofire's server trust
// evaluators), here so that `import Foundation` sees them as it does on Apple platforms. The
// browser checks a server's certificates before a fetch completes and never hands a page a
// challenge, so no trust arrives from a server. An app can still build one from certificates it
// holds: the certificates and policies are kept and read back, but a page can't verify a chain
// itself, so an evaluation answers "not trusted" with an unimplemented status, and no public
// key is read out of a certificate.
#if os(WASI)

/// A certificate, kept as the DER bytes it was made from.
public final class SecCertificate: Hashable, @unchecked Sendable {
    let data: Data
    init(data: Data) { self.data = data }
    public static func == (lhs: SecCertificate, rhs: SecCertificate) -> Bool { lhs.data == rhs.data }
    public func hash(into hasher: inout Hasher) { hasher.combine(data) }
}

/// A key. None is read out of a certificate here, so none exists unless an app keeps one.
public final class SecKey: Hashable, @unchecked Sendable {
    private init() {}
    public static func == (lhs: SecKey, rhs: SecKey) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A trust policy: SSL for a host, basic X.509, or revocation checking.
public final class SecPolicy: Hashable, @unchecked Sendable {
    let kind: String
    let hostname: String?
    init(kind: String, hostname: String? = nil) {
        self.kind = kind
        self.hostname = hostname
    }
    public static func == (lhs: SecPolicy, rhs: SecPolicy) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Trust in a certificate chain (the trust Foundation's protection space names).
public final class SecTrust: Hashable, @unchecked Sendable {
    var certificates: [SecCertificate]
    var policies: [SecPolicy]
    var anchors: [SecCertificate] = []
    var anchorsOnly = false
    init(certificates: [SecCertificate], policies: [SecPolicy]) {
        self.certificates = certificates
        self.policies = policies
    }
    public static func == (lhs: SecTrust, rhs: SecTrust) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// The outcome of a trust evaluation.
public enum SecTrustResultType: UInt32, Sendable {
    case invalid = 0, proceed = 1, confirm = 2, deny = 3, unspecified = 4
    case recoverableTrustFailure = 5, fatalTrustFailure = 6, otherError = 7
}

public let kSecRevocationOCSPMethod: CFOptionFlags = 1 << 0
public let kSecRevocationCRLMethod: CFOptionFlags = 1 << 1
public let kSecRevocationPreferCRL: CFOptionFlags = 1 << 2
public let kSecRevocationRequirePositiveResponse: CFOptionFlags = 1 << 3
public let kSecRevocationNetworkAccessDisabled: CFOptionFlags = 1 << 4
public let kSecRevocationUseAnyAvailableMethod: CFOptionFlags = kSecRevocationOCSPMethod | kSecRevocationCRLMethod

private let unimplemented: OSStatus = -4

/// A certificate from DER data; nil for empty data.
public func SecCertificateCreateWithData(_ allocator: CFAllocator?, _ data: CFData) -> SecCertificate? {
    data.isEmpty ? nil : SecCertificate(data: data)
}

public func SecCertificateCopyData(_ certificate: SecCertificate) -> CFData { certificate.data }

public func SecPolicyCreateSSL(_ server: Bool, _ hostname: CFString?) -> SecPolicy { SecPolicy(kind: "ssl", hostname: hostname) }
public func SecPolicyCreateBasicX509() -> SecPolicy { SecPolicy(kind: "x509") }
public func SecPolicyCreateRevocation(_ revocationFlags: CFOptionFlags) -> SecPolicy? { SecPolicy(kind: "revocation") }

/// Certificates and policies as an app passes them: one, or an array of them.
private func list<Element>(_ value: Any?) -> [Element]? {
    if let one = value as? Element { return [one] }
    if let many = value as? [Any] { return many.compactMap { $0 as? Element } }
    return value == nil ? [] : nil
}

public func SecTrustCreateWithCertificates(_ certificates: Any, _ policies: Any?, _ trust: UnsafeMutablePointer<SecTrust?>) -> OSStatus {
    guard let certificates: [SecCertificate] = list(certificates), !certificates.isEmpty,
          let policies: [SecPolicy] = list(policies) else { return -50 }
    trust.pointee = SecTrust(certificates: certificates, policies: policies)
    return 0
}

public func SecTrustSetPolicies(_ trust: SecTrust, _ policies: Any) -> OSStatus {
    guard let policies: [SecPolicy] = list(policies) else { return -50 }
    trust.policies = policies
    return 0
}

public func SecTrustCopyPolicies(_ trust: SecTrust, _ policies: UnsafeMutablePointer<CFArray?>) -> OSStatus {
    policies.pointee = trust.policies
    return 0
}

public func SecTrustSetAnchorCertificates(_ trust: SecTrust, _ anchorCertificates: CFArray) -> OSStatus {
    trust.anchors = anchorCertificates.compactMap { $0 as? SecCertificate }
    trust.anchorsOnly = true
    return 0
}

public func SecTrustSetAnchorCertificatesOnly(_ trust: SecTrust, _ anchorCertificatesOnly: Bool) -> OSStatus {
    trust.anchorsOnly = anchorCertificatesOnly
    return 0
}

public func SecTrustGetCertificateCount(_ trust: SecTrust) -> CFIndex { trust.certificates.count }

public func SecTrustGetCertificateAtIndex(_ trust: SecTrust, _ ix: CFIndex) -> SecCertificate? {
    trust.certificates.indices.contains(ix) ? trust.certificates[ix] : nil
}

public func SecTrustCopyCertificateChain(_ trust: SecTrust) -> CFArray? { trust.certificates }

/// No key is read out of a certificate here.
public func SecTrustCopyKey(_ trust: SecTrust) -> SecKey? { nil }
public func SecTrustCopyPublicKey(_ trust: SecTrust) -> SecKey? { nil }

/// Not trusted: a page can't verify a chain (the browser verifies a server's).
public func SecTrustEvaluateWithError(_ trust: SecTrust, _ error: UnsafeMutablePointer<CFError?>?) -> Bool {
    error?.pointee = NSError(domain: NSOSStatusErrorDomain, code: Int(unimplemented),
                             userInfo: [NSLocalizedDescriptionKey: "The browser verifies certificate chains; a page can’t evaluate one."])
    return false
}

public func SecTrustEvaluate(_ trust: SecTrust, _ result: UnsafeMutablePointer<SecTrustResultType>) -> OSStatus {
    result.pointee = .otherError
    return unimplemented
}

public func SecTrustGetTrustResult(_ trust: SecTrust, _ result: UnsafeMutablePointer<SecTrustResultType>) -> OSStatus {
    result.pointee = .invalid
    return 0
}
#endif
