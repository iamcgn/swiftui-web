// How feed readers reach XMLParser off Apple platforms: the module beside Foundation
// (`#if canImport(FoundationXML)`, as FeedKit writes), and the class by name. On wasm both
// have to find WebFoundation's parser without an ambiguity; compiled by
// `scripts/build-wasm.sh Examples/Launches` in CI, so one is a build error.
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if os(WASI)
import class FoundationXML.XMLParser
#endif

final class XMLImports: NSObject, XMLParserDelegate {
    private(set) var titles: [String] = []
    private var text = ""

    static func titles(in feed: Data) -> [String] {
        let reader = XMLImports()
        let parser = XMLParser(data: feed)
        parser.delegate = reader
        return parser.parse() ? reader.titles : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "title" { titles.append(text) }
    }
}
