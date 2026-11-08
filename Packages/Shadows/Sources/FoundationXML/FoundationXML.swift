// `FoundationXML` on wasm: the module Linux's Foundation keeps XMLParser in, which packages
// import beside Foundation when it can be imported (`#if canImport(FoundationXML)`: FeedKit,
// XMLCoder). The parser is WebFoundation's, the one `import Foundation` already gives; a file
// that imports it by name (`import class FoundationXML.XMLParser`) finds the names declared here.
#if os(WASI)
@_exported import Foundation
import WebFoundation

public typealias XMLParser = WebFoundation.XMLParser
public typealias XMLParserDelegate = WebFoundation.XMLParserDelegate
#endif
