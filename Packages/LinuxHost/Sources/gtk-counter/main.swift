// The Counter example in a GTK window (pf-linux): `swift run gtk-counter`.
#if canImport(CGtk)
import SwiftUI
import SwiftUIWebGTK

struct Counter: View {
    @State private var count = 0
    var body: some View {
        VStack(spacing: 16) {
            Text("Count: \(count)").font(.title)
            HStack {
                Button("−") { count -= 1 }
                Button("+") { count += 1 }
            }
            TextField("Name", text: .constant(""))
                .frame(width: 200)
        }
        .padding()
    }
}

exit(GTKHost.launch(size: CGSize(width: 400, height: 300), title: "Counter") { AnyView(Counter()) })
#else
print("gtk-counter needs GTK 4 (libgtk-4-dev)")
#endif
