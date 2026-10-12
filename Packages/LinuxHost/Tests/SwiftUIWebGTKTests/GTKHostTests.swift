// The GTK host without a window (pf-linux): the scene paints into a cairo image through the
// host, presses reach buttons, keys type into the focused field.
#if canImport(CGtk)
import Testing
import Foundation
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebGTK
import WebGraphicsGTK
import WebGraphicsCairo
import CGtk

@Suite @MainActor struct GTKHostTests {
    @Observable final class Model { var count = 0; var name = "" }

    struct Screen: View {
        let model: Model
        var body: some View {
            VStack(spacing: 12) {
                Text("Count \(model.count)")
                Button("Add") { model.count += 1 }._probe("add")
                TextField("Name", text: Bindable(model).name)._probe("name")
                Color.red.frame(width: 40, height: 40)._probe("red")
            }
            .padding()
        }
    }

    @Test func paintsPressesAndTypes() {
        let model = Model()
        let host = GTKHost.make(size: CGSize(width: 300, height: 240), title: "Test") { AnyView(Screen(model: model)) }
        let runtime = host.scene as! Runtime
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 300, 240)!
        let cr = cairo_create(surface)!
        host.paint(into: cr, size: CGSize(width: 300, height: 240))
        cairo_surface_flush(surface)
        let red = runtime.probeFrames["red"]!
        let pixel = CairoPainter.pixel(of: surface, x: Int(red.midX), y: Int(red.midY))
        // SwiftUI's system red is (255, 56, 60).
        #expect(pixel.red > 0.9 && pixel.green < 0.3 && pixel.blue < 0.3, "the red square painted: \(pixel)")
        // A press on the button.
        let add = runtime.probeFrames["add"]!
        host.pressed(at: CGPoint(x: add.midX, y: add.midY), time: 0)
        host.released(at: CGPoint(x: add.midX, y: add.midY), time: 0.1)
        #expect(model.count == 1)
        // Focus the field with a press, then type through GTK key values.
        let name = runtime.probeFrames["name"]!
        host.pressed(at: CGPoint(x: name.midX, y: name.midY), time: 1)
        host.released(at: CGPoint(x: name.midX, y: name.midY), time: 1.1)
        #expect(runtime.focusedTextFieldIdentifier != nil)
        host.key(UInt32(GDK_KEY_h), modifiers: 0)
        host.key(UInt32(GDK_KEY_i), modifiers: 0)
        host.key(UInt32(GDK_KEY_BackSpace), modifiers: 0)
        host.key(UInt32(GDK_KEY_o), modifiers: 0)
        host.paint(into: cr, size: CGSize(width: 300, height: 240))
        #expect(model.name == "ho", "\(model.name)")
        cairo_destroy(cr)
        cairo_surface_destroy(surface)
    }
}
#endif
