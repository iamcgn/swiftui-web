// UIHostingConfiguration (Docs/elements/Representable.md): SwiftUI content as a table or
// collection cell's `contentConfiguration`, hosted by the same runtime `UIHostingController`
// uses, with margins (the cell's layout margins by default), a background and a minimum size.
import SwiftUIWebCore
import UIKitWebCore

/// A content configuration suitable for hosting a hierarchy of SwiftUI views.
public struct UIHostingConfiguration<Content: View, Background: View>: UIContentConfiguration {
    let content: Content
    let background: Background
    /// The margins; nil takes the cell's default (16 sideways, ios/representable/hostingcells;
    /// 11 above and below, under the row's 56 pt floor).
    var marginInsets: EdgeInsets?
    var minimumSize = CGSize(width: 0, height: 0)

    public init(@ViewBuilder content: () -> Content) where Background == EmptyView {
        self.content = content()
        background = EmptyView()
    }

    init(content: Content, background: Background, margins: EdgeInsets?, minimumSize: CGSize) {
        self.content = content
        self.background = background
        marginInsets = margins
        self.minimumSize = minimumSize
    }

    public func background<B: View>(@ViewBuilder content: () -> B) -> UIHostingConfiguration<Content, B> {
        UIHostingConfiguration<Content, B>(content: self.content, background: content(), margins: marginInsets, minimumSize: minimumSize)
    }

    public func background<S: ShapeStyle>(_ style: S) -> UIHostingConfiguration<Content, FillShapeView<Rectangle, S, EmptyView>> {
        UIHostingConfiguration<Content, FillShapeView<Rectangle, S, EmptyView>>(content: content, background: Rectangle().fill(style), margins: marginInsets, minimumSize: minimumSize)
    }

    public func margins(_ insets: EdgeInsets) -> Self {
        var copy = self
        copy.marginInsets = insets
        return copy
    }

    public func margins(_ edges: Edge.Set = .all, _ length: CGFloat) -> Self {
        var copy = self
        var insets = copy.marginInsets ?? Self.defaultMargins
        if edges.contains(.top) { insets.top = length }
        if edges.contains(.bottom) { insets.bottom = length }
        if edges.contains(.leading) { insets.leading = length }
        if edges.contains(.trailing) { insets.trailing = length }
        copy.marginInsets = insets
        return copy
    }

    public func minSize(width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
        var copy = self
        if let width { copy.minimumSize.width = width }
        if let height { copy.minimumSize.height = height }
        return copy
    }

    public func minSize(_ size: CGSize) -> Self { minSize(width: size.width, height: size.height) }

    static var defaultMargins: EdgeInsets { EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16) }

    public func makeContentView() -> UIView & UIContentView { _UIHostingContentView(configuration: self) }
}

/// The hosted content: the background behind the content inset by the margins, in one runtime.
@MainActor
final class _UIHostingContentView<Content: View, Background: View>: UIView, UIContentView {
    private var hosted: UIHostingConfiguration<Content, Background>
    private let hostingView: _UIHostingView<AnyView>

    var configuration: any UIContentConfiguration {
        get { hosted }
        set {
            guard let configuration = newValue as? UIHostingConfiguration<Content, Background> else { return }
            hosted = configuration
            hostingView.rootView = Self.composed(configuration)
            setNeedsLayout()
        }
    }

    init(configuration: UIHostingConfiguration<Content, Background>) {
        hosted = configuration
        hostingView = _UIHostingView(rootView: Self.composed(configuration))
        super.init(frame: .zero)
        hostingView.backgroundColor = .clear
        addSubview(hostingView)
    }

    static func composed(_ configuration: UIHostingConfiguration<Content, Background>) -> AnyView {
        let margins = configuration.marginInsets ?? UIHostingConfiguration<Content, Background>.defaultMargins
        return AnyView(ZStack {
            configuration.background
            configuration.content.padding(margins).frame(maxWidth: .infinity, alignment: .leading)
        })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostingView.frame = bounds
    }

    /// The content's height for the width, at least the minimum size.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = hostingView.sizeThatFits(CGSize(width: size.width, height: UIView.layoutFittingExpandedSize.height))
        return CGSize(width: max(size.width, hosted.minimumSize.width), height: max(fitted.height, hosted.minimumSize.height))
    }
}
