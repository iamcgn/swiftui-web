// What the sweep found once apps' `#if os(iOS)` branches compile (PR 93): Umbrella's item alert
// hands its own non-escaping builders on (Hipstapaper), FoodTruck turns an `Angle` the other way
// and scales its box lid in from the bottom, and Resolver's iOS branch locks a mutex with only
// UIKit and SwiftUI imported (MakeItSo).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

extension View {
    /// Umbrella's `alert(item:title:actions:message:)`: Apple's alert builders don't escape, so
    /// a modifier of the app's own can pass its non-escaping parameters straight through.
    fileprivate func itemAlert<A: View, M: View, T>(item: Binding<T?>, title: String,
                                                    @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        alert(title, isPresented: _itemBinding(item), presenting: item.wrappedValue, actions: actions, message: message)
    }

    fileprivate func plainDialog<A: View>(_ title: String, @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(title, isPresented: .constant(true), titleVisibility: .visible, actions: actions)
    }
}

@Suite @MainActor struct IOSBranchGapsTests {
    private func shownTexts(_ runtime: Runtime) -> [String] {
        runtime.presentations.flatMap { $0.content.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString } }
    }

    @Test func alertBuildersNeedNotEscape() {
        let alert = Runtime()
        alert.mount(Text("root").itemAlert(item: .constant(7 as Int?), title: "Delete?",
                                           actions: { Button("Delete \($0)") {} }, message: { Text("Item \($0) goes") }))
        alert.layout(in: CGSize(width: 300, height: 300))
        let shown = shownTexts(alert)
        #expect(shown.contains("Delete?") && shown.contains("Delete 7") && shown.contains("Item 7 goes"))

        let dialog = Runtime()
        dialog.mount(Text("root").plainDialog("Share") { Button("Copy link") {} })
        dialog.layout(in: CGSize(width: 300, height: 300))
        #expect(shownTexts(dialog).contains("Copy link"))
    }

    @Test func anglesNegateAndTransitionsScaleFromAnAnchor() {
        #expect(-Angle.degrees(30) == .degrees(-30))
        #expect((-Angle.radians(1)).radians == -1)
        let lid = AnyTransition.scale(scale: 0.75, anchor: .bottom)
        if case let .scale(factor, anchor) = lid.kind {
            #expect(factor == 0.75 && anchor == .bottom)
        } else {
            Issue.record("expected a scale transition")
        }
    }

    #if os(WASI)
    @Test func mutexesNeedOnlySwiftUI() {
        var mutex = pthread_mutex_t()
        var attributes = pthread_mutexattr_t()
        #expect(pthread_mutexattr_init(&attributes) == 0)
        #expect(pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE) == 0)
        #expect(pthread_mutex_init(&mutex, &attributes) == 0)
        #expect(pthread_mutex_lock(&mutex) == 0 && pthread_mutex_unlock(&mutex) == 0)
    }
    #endif
}
