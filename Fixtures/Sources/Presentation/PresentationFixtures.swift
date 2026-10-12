// Presentation fixture: buttons that present a sheet, a popover and an alert, and a pop-up
// picker. The golden holds the base state only (macOS presents these in separate windows the
// hosted golden window cannot capture); Playwright/presentation-probe.mjs drives them in the browser.
import SwiftUI
import FixtureKit

@Observable
public final class PresentationModel {
    public var sheet = false
    public var popover = false
    public var alert = false
    public var fruit = 1
    public init() {}
}

struct PresentationSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            Text("Sheet content")
            Button("Done") { dismiss() }
        }
    }
}

public enum PresentationFixtures {
    public static let basic = Fixture(
        "presentation/basic", size: CGSize(width: 360, height: 240),
        model: { PresentationModel() },
        steps: []
    ) { model in
        VStack(spacing: 12) {
            Button("Sheet") { model.sheet = true }.probe("sheet")
            Button("Popover") { model.popover = true }
                .popover(isPresented: Binding(get: { model.popover }, set: { model.popover = $0 })) { Text("Popover content") }
                .probe("popover")
            Button("Alert") { model.alert = true }
                .alert("Alert title", isPresented: Binding(get: { model.alert }, set: { model.alert = $0 })) { Button("OK") {} } message: { Text("Message") }
                .probe("alert")
            Picker("Fruit", selection: Binding(get: { model.fruit }, set: { model.fruit = $0 })) { Text("Apple").tag(1); Text("Banana").tag(2) }
                .probe("picker")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { PresentationSheet() }
        .probe("stack")
    }

    /// The macOS looks (sw-mac-presentation-looks, 2026-10-11): each presentation after a step
    /// presents it, the harness recording the presented window's frame as `window.<kind>` and
    /// compositing its content (`Fixture.capturesWindow` on macOS; the panels' own chrome is
    /// the window server's and stays out).
    public static let macSheet = Fixture(
        "presentation/mac-sheet", size: CGSize(width: 400, height: 300),
        model: { PresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white
            Button("Sheet") { model.sheet = true }.probe("button")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            VStack(spacing: 12) {
                Text("Sheet title").font(.headline).probe("sheetTitle")
                Text("Some content under the title.").probe("sheetBody")
                Button("Done") { model.sheet = false }.probe("sheetDone")
            }
            .padding()
        }
        .probe("stack")
    }.capturesWindow()

    public static let macAlert = Fixture(
        "presentation/mac-alert", size: CGSize(width: 400, height: 300),
        model: { PresentationModel() },
        steps: [FixtureStep("present") { $0.alert = true }]
    ) { model in
        ZStack {
            Color.white
            Button("Delete…") { model.alert = true }.probe("button")
        }
        .alert("Delete the item?", isPresented: Binding(get: { model.alert }, set: { model.alert = $0 })) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .probe("stack")
    }.capturesWindow()

    public static let macPopover = Fixture(
        "presentation/mac-popover", size: CGSize(width: 400, height: 300),
        model: { PresentationModel() },
        steps: [FixtureStep("present") { $0.popover = true }]
    ) { model in
        ZStack {
            Color.white
            Button("Popover") { model.popover = true }
                .popover(isPresented: Binding(get: { model.popover }, set: { model.popover = $0 })) {
                    VStack(spacing: 8) {
                        Text("Popover title").font(.headline).probe("popTitle")
                        Text("A line of content.").probe("popBody")
                    }
                    .padding()
                }
                .probe("button")
        }
        .probe("stack")
    }.capturesWindow()

    public static let all: [Fixture] = [basic, macSheet, macAlert, macPopover]
}
