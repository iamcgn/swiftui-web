// ProgressView fixtures: determinate linear bars (bare, labelled, with value labels, tinted,
// sized), determinate circular rings, and the indeterminate spinner and bar (animated: their
// pixels are approximate, their frames exact).
import SwiftUI
import FixtureKit

public enum ProgressFixtures {
    public static let basic = Fixture("progress/basic", size: CGSize(width: 320, height: 400)) {
        VStack(spacing: 14) {
            ProgressView(value: 0.4).probe("bare")
            ProgressView("Loading", value: 0.6).probe("labelled")
            ProgressView(value: 0.3) { Text("Copying") } currentValueLabel: { Text("30%") }.probe("valueLabel")
            ProgressView(value: 0.7).tint(.red).probe("tinted")
            ProgressView(value: 0.5).frame(width: 120).probe("narrow")
            HStack(spacing: 20) {
                ProgressView(value: 0.4).progressViewStyle(.circular).probe("ring")
                ProgressView("Ring", value: 0.75).progressViewStyle(.circular).probe("ringLabelled")
                ProgressView(value: 1).progressViewStyle(.circular).probe("ringFull")
            }
            .probe("rings")
            ProgressView(value: 25, total: 50).progressViewStyle(.linear).probe("total")
        }
        .padding(20)
        .probe("stack")
    }

    public static let indeterminate = Fixture("progress/indeterminate", size: CGSize(width: 240, height: 220)) {
        VStack(spacing: 20) {
            ProgressView().probe("spinner")
            ProgressView("Working").probe("spinnerLabelled")
            ProgressView().progressViewStyle(.linear).probe("bar")
            ProgressView().controlSize(.small).probe("small")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, indeterminate]
}
