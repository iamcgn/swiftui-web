import SwiftUI
import FixtureKit

/// Every fixture the harness and the tests know about. Keep sorted by name.
public enum AllFixtures {
    public static let all: [Fixture] = LayoutFixtures.all + PaintFixtures.all + TextFixtures.all + ButtonFixtures.all
        + ForEachFixtures.all + SectionFixtures.all + ScrollViewFixtures.all + ImageFixtures.all + ColorFixtures.all + ShapeFixtures.all + ToggleFixtures.all + LabelFixtures.all + TextFieldFixtures.all + ListFixtures.all + NavigationFixtures.all + PickerFixtures.all + SliderFixtures.all + StepperFixtures.all + FormFixtures.all + LifecycleFixtures.all + AnimationFixtures.all + PresentationFixtures.all + CustomLayoutFixtures.all + GridFixtures.all + CanvasFixtures.all + ObservableObjectFixtures.all + TimelineFixtures.all + FocusFixtures.all + AccessibilityFixtures.all
}
