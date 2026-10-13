import SwiftUI

@main
struct LaunchesApp: App {
    @StateObject private var model = LaunchModel()
    @StateObject private var network = NetworkCheck()
    @State private var data = "data: pending"

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Launches").font(.title)
                Text(model.summary)
                Text(model.status)
                Text("mixed: " + MixedImports.check())
                Text(data).font(.caption)
                Text(network.summary).font(.caption)
                Button("Record again") { model.record() }
            }
            .padding()
            .onAppear { model.record(); network.run(); data = DataCheck.run() }
        }
    }
}
