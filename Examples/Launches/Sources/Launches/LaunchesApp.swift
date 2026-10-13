import SwiftUI

@main
struct LaunchesApp: App {
    @StateObject private var model = LaunchModel()
    @StateObject private var network = NetworkCheck()
    @State private var data = "data: pending"
    @StateObject private var keyboard = KeyboardCheck()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Launches").font(.title)
                Text(model.summary)
                Text(model.status)
                Text("mixed: " + MixedImports.check())
                Text(keyboard.summary).font(.caption)
                TextField("A field for the keyboard", text: .constant(""))
                Text(data).font(.caption)
                Text(network.summary).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Record again") { model.record() }
            }
            .padding()
            .onAppear { model.record(); network.run(); data = DataCheck.run() }
        }
    }
}
