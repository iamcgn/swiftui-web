// `import Dispatch` on wasm (decision 0021): the wasm SDK has no Dispatch module, and packages
// apps pin import it by name (TelemetryDeck, Alamofire, Apollo). WebFoundation's stand-in
// (`DispatchQueue`, groups, semaphores, timer sources) is what it means here.
#if os(WASI)
@_exported import WebFoundation
#endif
