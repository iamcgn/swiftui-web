import SwiftUI

@main
struct LaunchesApp: App {
    @StateObject private var model = LaunchModel()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Launches").font(.title)
                Text(model.summary)
                Text(model.status)
                Button("Record again") { model.record() }
            }
            .padding()
            .onAppear { model.record() }
        }
    }
}
