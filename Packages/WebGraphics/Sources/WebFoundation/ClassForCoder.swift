// `classForCoder()` on a class, as Apple's Foundation answers it for every NSObject subclass (a
// root-class method): apps register cells with it (`tableView.register(UITableViewCell
// .classForCoder(), forCellReuseIdentifier:)`, AcknowList). swift-corelibs-foundation on Linux
// has only the instance property. On wasm the root classes declare it themselves (SwiftFoundation's
// NSObject; ObjectiveCBridging.swift with the runtime).
#if !canImport(Darwin) && !os(WASI)
import Foundation

extension NSObject {
    public class func classForCoder() -> AnyClass { self }
}
#endif
