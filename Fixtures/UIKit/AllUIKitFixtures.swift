#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// Every UIKit fixture the harness and the tests know about. Keep sorted by name.
public enum AllUIKitFixtures {
    public static let all: [UIKitFixture] = [
        LabelFixtures.all, ButtonFixtures.all, StackFixtures.all, ViewFixtures.all, ControlFixtures.all,
        AutoLayoutFixtures.all, DrawFixtures.all, NavigationFixtures.all, TableFixtures.all, MoreControlFixtures.all, CollectionFixtures.all, PresentationFixtures.all, TextViewFixtures.all, BarFixtures.all, DatePickerFixtures.all, PickerFixtures.all, DarkFixtures.all,
    ].flatMap { $0 }
}
#endif
