// The remaining UIKit controls (Docs/elements/UIKit/Controls.md): a slider, a segmented control,
// a stepper, a progress view, an activity indicator and a page control, each sized to fit and
// placed by frame, measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum MoreControlFixtures {
    public static let all = [controls, rest]

    /// The rest of the controls (uk-controls-rest): a slider with minimum and maximum images,
    /// a segmented control of images, one with a fixed first segment width and one apportioned
    /// by content, measured against UIKit on the simulator.
    public static let rest = UIKitFixture("uikit/controls/rest", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let slider = UISlider()
        slider.value = 0.5
        slider.minimumValueImage = UIImage(systemName: "speaker.fill")
        slider.maximumValueImage = UIImage(systemName: "speaker.wave.3.fill")
        slider.sizeToFit()
        slider.frame = CGRect(x: 16, y: 16, width: 288, height: slider.frame.height)
        root.addSubview(slider.probe("imageSlider"))

        let images = UISegmentedControl(items: [UIImage(systemName: "list.bullet")!, UIImage(systemName: "square.grid.2x2")!, UIImage(systemName: "rectangle.grid.1x2")!])
        images.selectedSegmentIndex = 0
        images.sizeToFit()
        images.frame.origin = CGPoint(x: 16, y: 72)
        root.addSubview(images.probe("imageSegments"))

        let widths = UISegmentedControl(items: ["A", "Second", "C"])
        widths.setWidth(100, forSegmentAt: 0)
        widths.selectedSegmentIndex = 2
        widths.sizeToFit()
        widths.frame.origin = CGPoint(x: 16, y: 128)
        root.addSubview(widths.probe("widthSegments"))

        let apportioned = UISegmentedControl(items: ["A", "Second", "C"])
        apportioned.apportionsSegmentWidthsByContent = true
        apportioned.selectedSegmentIndex = 1
        apportioned.sizeToFit()
        apportioned.frame.origin = CGPoint(x: 16, y: 184)
        root.addSubview(apportioned.probe("apportioned"))
        return root
    }

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
