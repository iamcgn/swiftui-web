// NavigationStack fixtures: links outside and inside a list, the title (window chrome on
// macOS, so nothing in the content), sizing, and a behaviour fixture that pushes and pops
// through a path binding.
import SwiftUI
import FixtureKit

/// Drives `nav/steps`.
@Observable
public final class NavigationModel {
    public var path: [Int] = []
    public init() {}
}

public enum NavigationFixtures {
    /// Links outside a list: text, custom label and value forms, and a destination registration.
    public static let basic = Fixture("nav/basic", size: CGSize(width: 320, height: 260)) {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Root").probe("root")
                NavigationLink("Detail") { Text("Detail") }.probe("link")
                NavigationLink(destination: Text("Detail")) { Label("Go", image: "icon") }.probe("labelLink")
                NavigationLink("Value", value: 1).probe("valueLink")
                NavigationLink("Wide") { Text("Detail") }.frame(maxWidth: .infinity).probe("wideLink")
            }
            .navigationDestination(for: Int.self) { number in Text("Number \(number)").probe("numberDetail") }
            .probe("stack")
        }
        .probe("nav")
    }

    /// Links as list rows.
    public static let list = Fixture("nav/list", size: CGSize(width: 320, height: 200)) {
        NavigationStack {
            List {
                NavigationLink("Apple") { Text("Apple detail") }.probe("row1")
                NavigationLink("Banana", value: 2).probe("row2")
                NavigationLink(value: 3) { Label("Go", image: "icon") }.probe("row3")
                Text("Cherry").probe("row4")
            }
            .navigationDestination(for: Int.self) { number in Text("Number \(number)") }
            .probe("list")
        }
        .probe("nav")
    }

    /// The title and subtitle go to the window's title bar on macOS: the content is unchanged.
    public static let title = Fixture("nav/title", size: CGSize(width: 320, height: 120)) {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Content").probe("content")
            }
            .navigationTitle("Title")
            .navigationSubtitle("Subtitle")
            .probe("stack")
        }
        .probe("nav")
    }

    /// Sizing: a stack fills its proposal whatever its content.
    public static let sizing = Fixture("nav/sizing", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 8) {
            NavigationStack { Color.red.probe("fill") }.probe("navFill")
            NavigationStack { Text("Small").probe("small") }.probe("navText")
            HStack(spacing: 8) {
                NavigationStack { Text("Left").probe("left") }.frame(width: 100).probe("navLeft")
                Text("Right").probe("right")
            }
            .probe("row")
        }
        .probe("stack")
    }

    /// Behaviour: the path binding pushes and pops destinations.
    public static let steps = Fixture(
        "nav/steps", size: CGSize(width: 320, height: 200),
        model: { NavigationModel() },
        steps: [
            FixtureStep("push1") { $0.path = [1] },
            FixtureStep("push2") { $0.path = [1, 2] },
            FixtureStep("pop") { $0.path = [1] },
            FixtureStep("popAll") { $0.path = [] },
        ]
    ) { model in
        NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
            VStack(spacing: 12) {
                Text("Root").probe("root")
                NavigationLink("Push", value: 1).probe("link")
            }
            .navigationDestination(for: Int.self) { number in
                VStack(spacing: 12) {
                    Text("Number \(number)").probe("number\(number)")
                    NavigationLink("Deeper", value: number + 1).probe("deeper\(number)")
                }
            }
            .probe("stack")
        }
        .probe("nav")
    }

    public static let all: [Fixture] = [basic, list, title, sizing, steps]
}
