// A file that imports Foundation and SwiftUI and names Foundation's types through the sugar
// that needs one declaration of each name, as IceCubes' Models writes `[URL]()`: an empty array,
// dictionary or optional of the type, in expression position. Each name is WebFoundation's or,
// re-exported name by name, FoundationEssentials' (decision 0017), and every module that reaches
// either brings the same one. Compiled by `scripts/build-wasm.sh Examples/Launches` in CI; two
// declarations of a name here are a build error.
import Foundation
import SwiftUI

enum SugarImports {
    static var urls = [URL]()
    static var byName = [String: URL]()

    static func check() -> String {
        let none = URL?.none
        let blobs = [Data](), pending = [String: Data]()
        let encoders = [JSONEncoder](), decoders = [JSONDecoder]()
        let parts = [URLComponents](), items = [URLQueryItem]()
        let dates = [Date](), ids = [UUID](), spans = [TimeInterval]()
        let failures = [any LocalizedError]()
        let calendars = [Calendar](), zones = [TimeZone](), locales = [Locale]()
        let paths = [IndexPath](), order = SortOrder?.none
        let squared = pow(Decimal(3), 2)
        // FoundationEssentials' operators on its own types, which come through WebFoundation.
        var later = Date() + 60
        later -= 30
        later += 1
        let earlier = later - 10
        var half = Decimal(1) / Decimal(2)
        half /= 1
        let counts: [Int] = [urls.count, byName.count, blobs.count, pending.count, encoders.count, decoders.count,
                      parts.count, items.count, dates.count, ids.count, spans.count, failures.count,
                      calendars.count, zones.count, locales.count, paths.count]
        return "\(none == nil) \(order == nil) \(counts.reduce(0, +)) \(squared) \(half) \(earlier < later) \(ProcessInfo.processInfo.processIdentifier > 0)"
    }
}
