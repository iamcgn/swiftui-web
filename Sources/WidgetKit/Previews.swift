// WidgetKit's preview context (Docs/support.json, "WidgetKit"): a `PreviewProvider` for a
// widget's view names the size it previews, `.previewContext(WidgetPreviewContext(family:))`.
// The gallery shows the view as it lays out, so the family is kept, not applied.
import SwiftUI

/// The widget size a preview shows a widget's view at.
public struct WidgetPreviewContext: PreviewContext, Sendable {
    public let family: WidgetFamily

    public init(family: WidgetFamily) { self.family = family }
}
