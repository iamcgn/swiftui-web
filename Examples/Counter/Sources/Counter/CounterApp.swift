// The classic counter. This file must stay valid, unmodified SwiftUI.
import SwiftUI

@main
struct CounterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("Count: \(count)")
                .font(.title)
            HStack {
                Button("−") { count -= 1 }
                Button("+") { count += 1 }
            }
        }
        .padding()
    }
}
