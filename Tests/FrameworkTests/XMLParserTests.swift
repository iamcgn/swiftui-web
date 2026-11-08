// XMLParser as feed readers use it: elements, attributes, text with references, CDATA,
// comments and processing instructions in order, namespaces when processed, and the codes a
// malformed document stops with. The cases run against Foundation on macOS and Linux too.
import Testing
import WebFoundation
#if canImport(FoundationXML) && !os(WASI)
import FoundationXML
#endif

/// Records the delegate's events, joining text that arrives in pieces.
private final class Recorder: NSObject, XMLParserDelegate {
    var events: [String] = []
    var abortAt: String?
    private var text = ""

    private func flush() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { events.append("text \(trimmed)") }
        text = ""
    }

    func parserDidStartDocument(_ parser: XMLParser) { events.append("start") }
    func parserDidEndDocument(_ parser: XMLParser) { flush(); events.append("end") }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        flush()
        let attributes = attributeDict.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        events.append("<\(elementName)\(namespaceURI.map { " {\($0)}" } ?? "")\(qName.map { " \($0)" } ?? "")\(attributes.isEmpty ? "" : " " + attributes)>")
        if elementName == abortAt { parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        flush()
        events.append("</\(elementName)>")
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        flush()
        events.append("cdata \(String(decoding: CDATABlock, as: UTF8.self))")
    }
    func parser(_ parser: XMLParser, foundComment comment: String) { flush(); events.append("comment \(comment)") }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        flush()
        events.append("pi \(target) \(data ?? "")")
    }
}

@Suite struct XMLParserTests {
    private func parse(_ xml: String, namespaces: Bool = false, abortAt: String? = nil) -> (ok: Bool, events: [String], code: Int?) {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldProcessNamespaces = namespaces
        let recorder = Recorder()
        recorder.abortAt = abortAt
        parser.delegate = recorder
        let ok = parser.parse()
        return (ok, recorder.events, parser.parserError.flatMap { ($0 as Any as? NSError)?.code })
    }

    @Test func aFeedArrivesInOrder() {
        let feed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- a feed -->
        <rss version="2.0">
          <channel>
            <title>Ships &amp; Boats &#x2014; &#169;</title>
            <item id="1" kind="news"><description><![CDATA[<b>bold</b>]]></description></item>
            <?render fast?>
            <link/>
          </channel>
        </rss>
        """
        let result = parse(feed)
        #expect(result.ok)
        #expect(result.events == [
            "start", "comment  a feed ", "<rss version=2.0>", "<channel>", "<title>", "text Ships & Boats \u{2014} \u{A9}", "</title>",
            "<item id=1,kind=news>", "<description>", "cdata <b>bold</b>", "</description>", "</item>", "pi render fast",
            "<link>", "</link>", "</channel>", "</rss>", "end",
        ])
    }

    @Test func attributesDecodeTheirReferences() {
        let result = parse("<a href=\"x?a=1&amp;b=2\" title='say &quot;hi&quot;'/>")
        #expect(result.ok && result.events.contains("<a href=x?a=1&b=2,title=say \"hi\">"))
    }

    @Test func namespacesSplitNamesWhenProcessed() {
        let feed = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/"><media:thumbnail url="a.png"/></feed>
        """
        let processed = parse(feed, namespaces: true)
        #expect(processed.ok)
        #expect(processed.events.contains("<thumbnail {http://search.yahoo.com/mrss/} media:thumbnail url=a.png>"))
        #expect(processed.events.contains { $0.hasPrefix("<feed {http://www.w3.org/2005/Atom} feed") })
        let plain = parse(feed)
        #expect(plain.events.contains("<media:thumbnail url=a.png>"))
    }

    // Linux's FoundationXML returns true from parse() for these documents and reports another
    // code for an abort, so they hold WebFoundation to Apple's Foundation (macOS) only.
    #if !os(Linux)
    @Test func malformedDocumentsStop() {
        let mismatch = parse("<a><b></a>")
        #expect(!mismatch.ok && mismatch.code == XMLParser.ErrorCode.tagNameMismatchError.rawValue)
        #expect(!parse("").ok)
        #expect(!parse("<a>&nbsp;</a>").ok)
        #expect(!parse("<a>").ok)
        #expect(!parse("<a/><b/>").ok)
    }

    @Test func aDelegateCanAbort() {
        let result = parse("<a><b/><c/></a>", abortAt: "b")
        #expect(!result.ok && result.code == XMLParser.ErrorCode.delegateAbortedParseError.rawValue)
        #expect(!result.events.contains("<c>"))
    }
    #endif

    #if os(WASI)
    @Test func internalEntitiesAreReplaced() {
        let result = parse("<!DOCTYPE r [<!ENTITY who \"World\"> <!ELEMENT r (#PCDATA)>]><r>Hello &who;</r>")
        #expect(result.ok && result.events.contains("text Hello World"))
    }
    #endif
}
