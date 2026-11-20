// `FoundationNetworking` on wasm: the module Linux's Foundation keeps URLSession in, which
// packages import beside Foundation when it can be imported (`#if canImport(FoundationNetworking)`,
// swift-openapi-urlsession, Alamofire's Linux paths). The types are WebFoundation's, the ones
// `import Foundation` already gives; a file that imports them one by one
// (`import class FoundationNetworking.URLSession`) finds the names declared here.
#if os(WASI)
@_exported import Foundation
import WebFoundation

public typealias URLSession = WebFoundation.URLSession
public typealias URLSessionConfiguration = WebFoundation.URLSessionConfiguration
public typealias URLSessionTask = WebFoundation.URLSessionTask
public typealias URLSessionDataTask = WebFoundation.URLSessionDataTask
public typealias URLSessionUploadTask = WebFoundation.URLSessionUploadTask
public typealias URLSessionDownloadTask = WebFoundation.URLSessionDownloadTask
public typealias URLSessionTaskMetrics = WebFoundation.URLSessionTaskMetrics
public typealias URLSessionTaskTransactionMetrics = WebFoundation.URLSessionTaskTransactionMetrics
#if canImport(ObjectiveC)
// With the runtime the delegate protocols are the Foundation module's (URLSessionDelegates.swift).
public typealias URLSessionDelegate = Foundation.URLSessionDelegate
public typealias URLSessionTaskDelegate = Foundation.URLSessionTaskDelegate
public typealias URLSessionDataDelegate = Foundation.URLSessionDataDelegate
public typealias URLSessionDownloadDelegate = Foundation.URLSessionDownloadDelegate
#else
public typealias URLSessionDelegate = WebFoundation.URLSessionDelegate
public typealias URLSessionTaskDelegate = WebFoundation.URLSessionTaskDelegate
public typealias URLSessionDataDelegate = WebFoundation.URLSessionDataDelegate
public typealias URLSessionDownloadDelegate = WebFoundation.URLSessionDownloadDelegate
#endif
public typealias URLRequest = WebFoundation.URLRequest
public typealias URLResponse = WebFoundation.URLResponse
public typealias HTTPURLResponse = WebFoundation.HTTPURLResponse
public typealias URLCache = WebFoundation.URLCache
public typealias CachedURLResponse = WebFoundation.CachedURLResponse
public typealias URLCredential = WebFoundation.URLCredential
public typealias URLCredentialStorage = WebFoundation.URLCredentialStorage
public typealias URLProtectionSpace = WebFoundation.URLProtectionSpace
public typealias URLAuthenticationChallenge = WebFoundation.URLAuthenticationChallenge
public typealias URLAuthenticationChallengeSender = WebFoundation.URLAuthenticationChallengeSender
public typealias HTTPCookie = WebFoundation.HTTPCookie
public typealias HTTPCookieStorage = WebFoundation.HTTPCookieStorage
public typealias HTTPCookiePropertyKey = WebFoundation.HTTPCookiePropertyKey
#endif
