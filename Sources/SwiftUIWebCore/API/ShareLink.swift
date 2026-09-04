// ShareLink (Docs/elements/ShareLink.md): a bordered button with the share symbol that hands
// its items to the host's share sheet.
#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif

/// An action that shares items (the host's share sheet; the browser's Web Share).
public struct ShareAction: Sendable {
    /// The host's sharer: nil until a host installs one.
    @MainActor public static var systemHandler: (@MainActor ([String], String?) -> Void)?

    @MainActor package static func share(_ items: [String], subject: String?) {
        systemHandler?(items, subject)
    }
}

/// A view that controls a sharing presentation.
public struct ShareLink<Label: View>: View {
    package let items: [String]
    package let subject: Text?
    package let message: Text?
    package let label: Label

    /// Creates an instance that presents the share interface for the items with a custom label.
    public init(items: [URL], subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.items = items.map(\.absoluteString)
        self.subject = subject
        self.message = message
        self.label = label()
    }

    @_disfavoredOverload
    public init(items: [String], subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.items = items
        self.subject = subject
        self.message = message
        self.label = label()
    }

    public init(item: URL, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(items: [item], subject: subject, message: message, label: label)
    }

    @_disfavoredOverload
    public init(item: String, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(items: [item], subject: subject, message: message, label: label)
    }

    public var body: some View {
        let items = items
        let subject = subject?.resolvedString
        return Button(action: { ShareAction.share(items, subject: subject) }) { label }
    }
}

extension ShareLink where Label == SwiftUIWebCore.Label<Text, Image> {
    /// The default label: "Share…" with the share symbol.
    public init(item: URL, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    @_disfavoredOverload
    public init(item: String, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    public init(items: [URL], subject: Text? = nil, message: Text? = nil) {
        self.init(items: items, subject: subject, message: message) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    /// A titled share link with the share symbol.
    public init(_ titleKey: LocalizedStringKey, item: URL, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label(titleKey, systemImage: "square.and.arrow.up") }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, item: URL, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label(title, systemImage: "square.and.arrow.up") }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, item: String, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label(title, systemImage: "square.and.arrow.up") }
    }
}
