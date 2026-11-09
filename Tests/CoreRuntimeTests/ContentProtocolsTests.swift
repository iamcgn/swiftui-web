// Content protocols in the shape packages extend: rotor content with a `body`, and table column
// and row content typed by their row value. swift-perception wraps each in its tracking view
// (`WithPerceptionTracking: AccessibilityRotorContent where Content: AccessibilityRotorContent`,
// and the same for TableColumnContent and TableRowContent); `TrackedContent` below declares those
// conformances the way it does.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
/// A wrapper whose `body` is its content, declared outside any actor like perception's.
fileprivate struct TrackedContent<Content> {
    let content: Content
    var body: Content { content }
}

extension TrackedContent: AccessibilityRotorContent where Content: AccessibilityRotorContent {
    init(@AccessibilityRotorContentBuilder content: @escaping () -> Content) { self.content = content() }
}

extension TrackedContent: TableColumnContent where Content: TableColumnContent {
    typealias TableRowValue = Content.TableRowValue
    typealias TableColumnSortComparator = Content.TableColumnSortComparator
    typealias TableColumnBody = Never

    init<R, C>(@TableColumnBuilder<R, C> content: @escaping () -> Content)
    where R == Content.TableRowValue, C == Content.TableColumnSortComparator {
        self.content = content()
    }

    nonisolated var tableColumnBody: Never { return fatalError() }

    nonisolated static func _makeContent(content: _GraphValue<TrackedContent<Content>>, inputs: _TableColumnInputs) -> _TableColumnOutputs {
        Content._makeContent(content: content[\.body], inputs: inputs)
    }
}

extension TrackedContent: TableRowContent where Content: TableRowContent {
    typealias TableRowValue = Content.TableRowValue
    typealias TableRowBody = Never

    init<R>(@TableRowBuilder<R> content: @escaping () -> Content) where R == Content.TableRowValue {
        self.content = content()
    }

    nonisolated var tableRowBody: Never { return fatalError() }
}

/// Rotor content of its own: a type whose `body` lists entries.
fileprivate struct EndsRotorContent: AccessibilityRotorContent {
    let namespace: Namespace.ID
    var body: some AccessibilityRotorContent {
        AccessibilityRotorEntry("Top", id: "header", in: namespace)
        AccessibilityRotorEntry("Bottom", id: "footer", in: namespace)
    }
}

fileprivate struct EndsRotor: View {
    @Namespace private var namespace
    var body: some View {
        VStack {
            Text("Header").accessibilityRotorEntry(id: "header", in: namespace)
            Text("Footer").accessibilityRotorEntry(id: "footer", in: namespace)
        }
        .accessibilityRotor("Ends") { EndsRotorContent(namespace: namespace) }
        .accessibilityRotor("TrackedContent") {
            TrackedContent { AccessibilityRotorEntry("Only the footer", id: "footer", in: namespace) }
        }
    }
}

fileprivate struct NumberName { let number: Int; let name: String }

private func rowValue<C: TableColumnContent>(of content: C.Type) -> Any.Type { C.TableRowValue.self }
private func comparator<C: TableColumnContent>(of content: C.Type) -> Any.Type { C.TableColumnSortComparator.self }

@Suite @MainActor struct ContentProtocolsTests {
    @Test func rotorContentReadsItsBody() {
        let runtime = Runtime()
        runtime.mount(EndsRotor())
        runtime.layout(in: CGSize(width: 320, height: 300))
        let tree = runtime.semanticsTree()
        let header = tree.first { $0.label == "Header" }!, footer = tree.first { $0.label == "Footer" }!
        let holder = tree.first { !$0.rotors.isEmpty }!
        #expect(holder.rotors == [
            SemanticsRotor(label: "Ends", entries: [.init(label: "Top", target: header.identifier), .init(label: "Bottom", target: footer.identifier)]),
            SemanticsRotor(label: "TrackedContent", entries: [.init(label: "Only the footer", target: footer.identifier)]),
        ])
    }

    @Test func graphValuesReachTheirParts() {
        let value = _GraphValue { NumberName(number: 7, name: "seven") }
        #expect(value[\.name].value() == "seven")
        #expect(value[\.number].value() == 7)
    }

    @Test func emptyColumnContentMakesNoColumns() {
        // A wrapper around no columns forwards to Never's, which makes none.
        let outputs = TrackedContent<Never>._makeContent(content: _GraphValue { fatalError("never read") }, inputs: _TableColumnInputs())
        #expect(outputs.columns.isEmpty)
        // The content types name the row value and the comparator their columns sort with.
        #expect(rowValue(of: TrackedContent<Never>.self) == Never.self)
        #expect(comparator(of: TrackedContent<Never>.self) == Never.self)
    }
}
#endif
