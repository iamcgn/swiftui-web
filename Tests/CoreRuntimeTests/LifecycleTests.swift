// onAppear, onDisappear and task (Phase 2): actions run after the update that inserts or
// removes the view; tasks start on appear, are cancelled on disappear and restart on an id change.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct LifecycleTests {
    @Observable final class Model: @unchecked Sendable {
        var show = true
        var id = 0
        var log: [String] = []
    }

    struct Content: View {
        let model: Model
        var body: some View {
            VStack {
                Text("Root").onAppear { model.log.append("root appear") }
                if model.show {
                    Text("Child")
                        .onAppear { model.log.append("child appear") }
                        .onDisappear { model.log.append("child disappear") }
                }
            }
        }
    }

    @Test func appearAndDisappearRunAroundUpdates() {
        let model = Model()
        let runtime = Runtime()
        runtime.mount(Content(model: model))
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(model.log == ["root appear", "child appear"])
        model.show = false
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(model.log == ["root appear", "child appear", "child disappear"])
        model.show = true
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(model.log.last == "child appear")
    }

    struct Tasked: View {
        let model: Model
        var body: some View {
            VStack {
                if model.show {
                    Text("A").task(id: model.id) {
                        let id = model.id
                        model.log.append("start \(id)")
                        guard id < 2 else { model.log.append("done \(id)"); return }
                        do {
                            try await Task.sleep(nanoseconds: 10_000_000_000)
                            model.log.append("done \(id)")
                        } catch {
                            model.log.append("cancelled \(id)")
                        }
                    }
                }
            }
        }
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func tasksStartCancelAndRestart() async {
        let model = Model()
        let runtime = Runtime()
        runtime.mount(Tasked(model: model))
        runtime.layout(in: CGSize(width: 100, height: 100))
        await settle()
        #expect(model.log == ["start 0"])
        // A new id cancels and restarts; removing the view cancels; a task left alone completes.
        model.id = 1
        runtime.layout(in: CGSize(width: 100, height: 100))
        await settle()
        #expect(Set(model.log.dropFirst()) == ["cancelled 0", "start 1"])   // the cancellation lands on a later hop
        model.show = false
        runtime.layout(in: CGSize(width: 100, height: 100))
        await settle()
        #expect(model.log.last == "cancelled 1")
        model.id = 2
        model.show = true
        runtime.layout(in: CGSize(width: 100, height: 100))
        await settle()
        #expect(model.log.suffix(2) == ["start 2", "done 2"])
    }
}
#endif
