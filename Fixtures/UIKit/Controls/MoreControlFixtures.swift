// The remaining UIKit controls (Docs/elements/UIKit/Controls.md): a slider, a segmented control,
// a stepper, a progress view, an activity indicator and a page control, each sized to fit and
// placed by frame, measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum MoreControlFixtures {
    public static let all = [controls]

    public static let controls = UIKitFixture("uikit/controls/more", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let slider = UISlider()
        slider.value = 0.3
        slider.sizeToFit()
        slider.frame = CGRect(x: 16, y: 16, width: 288, height: slider.frame.height)
        root.addSubview(slider.probe("slider"))

        let segmented = UISegmentedControl(items: ["One", "Two", "Three"])
        segmented.selectedSegmentIndex = 1
        segmented.sizeToFit()
        segmented.frame.origin = CGPoint(x: 16, y: 72)
        root.addSubview(segmented.probe("segmented"))

        let stepper = UIStepper()
        stepper.value = 2
        stepper.sizeToFit()
        stepper.frame.origin = CGPoint(x: 16, y: 128)
        root.addSubview(stepper.probe("stepper"))

        let progress = UIProgressView(progressViewStyle: .default)
        progress.progress = 0.6
        progress.sizeToFit()
        progress.frame = CGRect(x: 16, y: 184, width: 288, height: progress.frame.height)
        root.addSubview(progress.probe("progress"))

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.sizeToFit()
        spinner.frame.origin = CGPoint(x: 16, y: 216)
        spinner.hidesWhenStopped = false
        root.addSubview(spinner.probe("spinner"))

        let large = UIActivityIndicatorView(style: .large)
        large.sizeToFit()
        large.frame.origin = CGPoint(x: 72, y: 216)
        large.hidesWhenStopped = false
        root.addSubview(large.probe("spinnerLarge"))

        let pages = UIPageControl()
        pages.numberOfPages = 4
        pages.currentPage = 1
        pages.sizeToFit()
        pages.frame.origin = CGPoint(x: 16, y: 288)
        root.addSubview(pages.probe("pages"))

        let disabledSlider = UISlider()
        disabledSlider.value = 0.7
        disabledSlider.isEnabled = false
        disabledSlider.sizeToFit()
        disabledSlider.frame = CGRect(x: 16, y: 336, width: 200, height: disabledSlider.frame.height)
        root.addSubview(disabledSlider.probe("disabledSlider"))
        return root
    }
}
#endif
