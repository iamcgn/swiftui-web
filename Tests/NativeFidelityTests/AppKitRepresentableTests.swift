// AppKit representables on the native host (ix-appkit): the real NSView lives in the
// runtime's view at its node's frame, sized by its fitting size, moved when the layout
// changes and removed when the node unmounts.
#if canImport(AppKit)
import AppKit
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebNative

@Suite @MainActor struct AppKitRepresentableTests {
    struct Field: NSViewRepresentable {
        let text: String
        func makeNSView(context: Context) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.identifier = NSUserInterfaceItemIdentifier("hosted-field")
            return field
        }
        func updateNSView(_ nsView: NSTextField, context: Context) { nsView.stringValue = text }
    }

    @Observable final class Model { var text = "Hello"; var shown = true; var leading = false }

    struct Screen: View {
        let model: Model
        var body: some View {
            VStack {
                if model.shown { Field(text: model.text)._probe("field") }
                Text("Below")
            }
            .frame(maxWidth: .infinity, alignment: model.leading ? .leading : .center)
        }
    }

    @Test func realViewsLiveInTheWindowAtTheirFrames() {
        let model = Model()
        let host = NativeHost(size: CGSize(width: 320, height: 200)) { AnyView(Screen(model: model)) }
        host.makeView()
        host.runtime.layout(in: CGSize(width: 320, height: 200))
        let field = host.view.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "hosted-field" }
        let frame = host.runtime.probeFrames["field"]
        #expect(field != nil && frame != nil && field?.frame == frame, "\(String(describing: field?.frame)) \(String(describing: frame))")
        #expect((frame?.width ?? 0) > 20 && (frame?.height ?? 0) > 10, "sized by the field's fitting size: \(String(describing: frame))")
        // A layout change moves it; a model change updates it.
        model.leading = true
        model.text = "Hello there"
        host.runtime.layout(in: CGSize(width: 320, height: 200))
        #expect(field?.frame == host.runtime.probeFrames["field"] && field?.stringValue == "Hello there")
        #expect((field?.frame.minX ?? 100) < 10)
        // Unmounting takes it out of the window.
        model.shown = false
        host.runtime.layout(in: CGSize(width: 320, height: 200))
        #expect(field?.superview == nil)
    }
}
#endif
