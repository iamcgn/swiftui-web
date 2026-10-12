// `#Preview` (Docs/elements/Preview.md): the macro keeps the preview's body as a `_Preview`
// registration (an enum with a compiler-unique name conforming to `_PreviewRegistration`);
// natively `_PreviewRegistry.all` finds them in the binary's conformance records, the wasm
// gallery lists them from a generated index; `PreviewTrait`s carry layouts and
// `PreviewModifier`s; the older `PreviewProvider` and its modifiers compile.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(MachO)
import MachO
#endif

/// Creates a preview of a SwiftUI view, kept as a `_Preview` registration.
@freestanding(declaration)
public macro Preview(_ name: String? = nil, body: @escaping @MainActor () -> any View) =
    #externalMacro(module: "SwiftUIWebMacros", type: "PreviewMacro")

/// Creates a preview with traits (a fixed layout, orientations, `PreviewModifier`s).
@freestanding(declaration)
public macro Preview(_ name: String? = nil, traits: PreviewTrait, _ moreTraits: PreviewTrait..., body: @escaping @MainActor () -> any View) =
    #externalMacro(module: "SwiftUIWebMacros", type: "PreviewMacro")

/// Options a preview declares.
public struct PreviewTrait: Sendable {
    package enum Kind: Sendable {
        case sizeThatFits
        case fixed(width: Double, height: Double)
        case orientation(String)
        case modifier(any PreviewModifier & Sendable)
        case device(String)
    }
    package let kind: Kind
    package init(_ kind: Kind) { self.kind = kind }

    public init() { kind = .sizeThatFits }
    /// The preview takes the size its content asks for.
    public static let sizeThatFitsLayout = PreviewTrait(.sizeThatFits)
    public static let landscapeLeft = PreviewTrait(.orientation("landscapeLeft"))
    public static let landscapeRight = PreviewTrait(.orientation("landscapeRight"))
    public static let portrait = PreviewTrait(.orientation("portrait"))
    public static let portraitUpsideDown = PreviewTrait(.orientation("portraitUpsideDown"))
    /// The preview is laid out at the given size.
    public static func fixedLayout(width: Double, height: Double) -> PreviewTrait { PreviewTrait(.fixed(width: width, height: height)) }
    /// A modifier applied around the preview's content, with a shared context made once.
    public static func modifier<M: PreviewModifier & Sendable>(_ modifier: M) -> PreviewTrait { PreviewTrait(.modifier(modifier)) }

    /// The fixed layout the traits ask for, if any.
    public var fixedSize: CGSize? {
        if case .fixed(let width, let height) = kind { return CGSize(width: width, height: height) }
        return nil
    }
}

/// A type that applies the same wrapping (a model, a style) to several previews, with a
/// context made once per process (`makeSharedContext`).
@MainActor @preconcurrency
public protocol PreviewModifier {
    associatedtype Context = Void
    associatedtype Body: View
    /// Makes the context the previews share (loaded data, a container); nothing by default.
    static func makeSharedContext() async throws -> Context
    /// Wraps a preview's content with the shared context.
    @ViewBuilder func body(content: PreviewModifierContent, context: Context) -> Body
}

extension PreviewModifier where Context == Void {
    public static func makeSharedContext() async throws -> Void { () }
}

/// The content a `PreviewModifier` wraps.
public struct PreviewModifierContent: View {
    package let content: AnyView
    package init(_ content: AnyView) { self.content = content }
    public var body: some View { content }
}

/// A kept preview: its name, traits, source position and body.
public struct _Preview: Sendable {
    public let name: String?
    public let traits: [PreviewTrait]
    public let file: String
    public let line: Int
    public let body: @MainActor @Sendable () -> any View

    public init(name: String?, traits: [PreviewTrait], file: String, line: Int, body: @escaping @MainActor @Sendable () -> any View) {
        self.name = name
        self.traits = traits
        self.file = file
        self.line = line
        self.body = body
    }

    /// The preview's display name: its own, else the file and line.
    public var displayName: String { name ?? "\(file.split(separator: "/").last.map(String.init) ?? file):\(line)" }

    /// The size the traits fix, if any (`sizeThatFitsLayout` and the orientations fix none).
    public var fixedSize: CGSize? { traits.lazy.compactMap(\.fixedSize).first }

    /// The preview's content with its modifiers applied (`_PreviewHost` makes the contexts).
    @MainActor public func makeView() -> AnyView {
        let modifiers = traits.compactMap { trait -> (any PreviewModifier & Sendable)? in
            if case .modifier(let modifier) = trait.kind { return modifier }
            return nil
        }
        return AnyView(_PreviewHost(preview: self, modifiers: modifiers))
    }
}

/// What the macro expands a `#Preview` into: a type (with a compiler-unique name) holding its
/// `_Preview`. `_PreviewRegistry.all` finds the conformers natively.
public protocol _PreviewRegistration {
    @MainActor static var preview: _Preview { get }
}

/// Renders a preview's body under its modifiers, each with the context it makes (awaited on
/// appearance; the content shows once every context is ready).
struct _PreviewHost: View {
    let preview: _Preview
    let modifiers: [any PreviewModifier & Sendable]
    @State private var contexts: [Any]?

    var body: some View {
        if modifiers.isEmpty {
            AnyView(preview.body())
        } else if let contexts {
            modified(contexts)
        } else {
            Color.clear.task {
                var made: [Any] = []
                for modifier in modifiers { made.append((try? await Self.makeContext(for: modifier)) as Any) }
                contexts = made
            }
        }
    }

    private static func makeContext(for modifier: any PreviewModifier & Sendable) async throws -> Any {
        func make<M: PreviewModifier>(_: M) async throws -> Any { try await M.makeSharedContext() }
        return try await make(modifier)
    }

    private func modified(_ contexts: [Any]) -> AnyView {
        var content = AnyView(preview.body())
        for (modifier, context) in zip(modifiers, contexts) {
            func apply<M: PreviewModifier>(_ modifier: M) -> AnyView {
                guard let typed = context as? M.Context else { return content }
                return AnyView(modifier.body(content: PreviewModifierContent(content), context: typed))
            }
            content = apply(modifier)
        }
        return content
    }
}

/// A type that produces previews (the older API); `PreviewProvider.previews` can be listed by
/// the generated index like a `#Preview`.
public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder @MainActor static var previews: Previews { get }
}

/// A device a preview targets (ignored: the gallery renders the macOS or iOS profile).
public struct PreviewDevice: RawRepresentable, ExpressibleByStringLiteral, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
}

/// How a `PreviewProvider` preview is laid out.
public enum PreviewLayout: Sendable {
    case device
    case sizeThatFits
    case fixed(width: CGFloat, height: CGFloat)
}

extension View {
    /// Overrides the device for a `PreviewProvider` preview (accepted; the gallery shows the
    /// profile it runs).
    nonisolated public func previewDevice(_ value: PreviewDevice?) -> some View { self }
    /// Overrides the layout of a `PreviewProvider` preview (accepted).
    nonisolated public func previewLayout(_ value: PreviewLayout) -> some View { self }
    /// Names a `PreviewProvider` preview (accepted).
    nonisolated public func previewDisplayName(_ value: String?) -> some View { self }
}

// MARK: - Discovery

/// The previews an app declared with `#Preview`.
public enum _PreviewRegistry {
    /// Registrations added by hand or by a generated index (`scripts/gen-fixture-sources.py`
    /// emits one for the gallery, where no conformance records can be read).
    @MainActor public static var registered: [_Preview] = []

    /// Every `#Preview` in the process: the registered ones plus, on Apple platforms, the
    /// `_PreviewRegistration` conformers found in the loaded images' Swift protocol conformance
    /// records (`__TEXT,__swift5_proto`; the mechanism Xcode's previews use). Sorted by file
    /// and line.
    @MainActor public static var all: [_Preview] {
        var previews = registered
        var seen = Set(previews.map { "\($0.file):\($0.line)" })
        for type in conformers() {
            let preview = type.preview
            let key = "\(preview.file):\(preview.line)"
            if seen.insert(key).inserted { previews.append(preview) }
        }
        return previews.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
    }

    #if canImport(MachO)
    /// The `_PreviewRegistration` conformers in every loaded Mach-O image.
    private static func conformers() -> [any _PreviewRegistration.Type] {
        var result: [any _PreviewRegistration.Type] = []
        for index in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(index) else { continue }
            var size: UInt = 0
            let mh = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            guard let section = getsectiondata(mh, "__TEXT", "__swift5_proto", &size) else { continue }
            let base = UnsafeRawPointer(section)
            for offset in stride(from: 0, to: Int(size), by: 4) {
                let entry = base.advanced(by: offset)
                let descriptor = entry.advanced(by: Int(entry.load(as: Int32.self)))
                guard let proto = relativeIndirectable(descriptor), contextName(proto) == "_PreviewRegistration" else { continue }
                // The conformance's flags: bits 3–5 say how the type is referenced.
                let flags = descriptor.load(fromByteOffset: 12, as: UInt32.self)
                let kind = (flags >> 3) & 0x7
                guard kind == 0 || kind == 1 else { continue }
                let typeField = descriptor.advanced(by: 4)
                var typeDescriptor = typeField.advanced(by: Int(typeField.load(as: Int32.self)))
                if kind == 1 { typeDescriptor = typeDescriptor.load(as: UnsafeRawPointer.self) }
                // The type descriptor's metadata accessor (its fourth word) hands back the
                // metadata; the second return word (the state) is dropped.
                let accessField = typeDescriptor.advanced(by: 12)
                let accessor = unsafeBitCast(accessField.advanced(by: Int(accessField.load(as: Int32.self))), to: (@convention(c) (UInt) -> UnsafeRawPointer).self)
                let metadata = unsafeBitCast(accessor(0), to: Any.Type.self)
                if let registration = metadata as? any _PreviewRegistration.Type { result.append(registration) }
            }
        }
        return result
    }

    /// A relative pointer whose low bit means "to a pointer to the target".
    private static func relativeIndirectable(_ field: UnsafeRawPointer) -> UnsafeRawPointer? {
        let offset = field.load(as: Int32.self)
        if offset == 0 { return nil }
        let target = field.advanced(by: Int(offset & ~1))
        return offset & 1 == 1 ? target.load(as: UnsafeRawPointer.self) : target
    }

    /// A context descriptor's name (its third word, a relative pointer to a C string).
    private static func contextName(_ descriptor: UnsafeRawPointer) -> String {
        let field = descriptor.advanced(by: 8)
        return String(cString: field.advanced(by: Int(field.load(as: Int32.self))).assumingMemoryBound(to: CChar.self))
    }
    #else
    private static func conformers() -> [any _PreviewRegistration.Type] { [] }
    #endif
}
