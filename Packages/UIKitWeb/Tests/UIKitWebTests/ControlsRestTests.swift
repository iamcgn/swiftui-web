// The rest of the controls (uk-controls-rest): the slider's end images inset its track, segment
// widths (fixed, apportioned, image segments), the stepper's autorepeat while held, the page
// control's taps and scrubbing.
import Testing
@testable import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite @MainActor struct ControlsRestTests {
    @Test func sliderImagesInsetTheTrack() {
        let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 288, height: 34))
        slider.value = 0.5
        #expect(slider.trackRect(forBounds: slider.bounds) == CGRect(x: 0, y: 14, width: 288, height: 6))
        // Symbols of the built-in table (the full one is the host's; the fixture uses the speakers).
        slider.minimumValueImage = UIImage(systemName: "speaker.wave.1")
        slider.maximumValueImage = UIImage(systemName: "speaker.wave.2")
        let minimum = slider.minimumValueImageRect(forBounds: slider.bounds), maximum = slider.maximumValueImageRect(forBounds: slider.bounds)
        // The images at the edges, centred on the track's middle; the track 11 in from each.
        #expect(minimum.minX == 0 && abs(minimum.midY - 17) < 0.01 && abs(maximum.maxX - 288) < 0.01, "\(minimum) \(maximum)")
        let track = slider.trackRect(forBounds: slider.bounds)
        #expect(abs(track.minX - (minimum.width + 11)) < 0.01 && abs(track.maxX - (288 - maximum.width - 11)) < 0.01)
        // The knob travels within the track; a press at the track's start is the minimum.
        let knob = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: 0.5)
        #expect(abs(knob.midX - track.midX) <= 1)
        slider.touchesBegan([UITouch(at: CGPoint(x: track.minX + 10, y: 17), in: nil, view: slider, type: .direct, timestamp: 0)], with: nil)
        #expect(slider.value == 0)
    }

    @Test func segmentWidths() throws {
        UIKitScene.shared.textEngine = try Goldens.textEngine()
        let control = UISegmentedControl(items: ["A", "Second", "C"])
        let shared = control.frame.width
        #expect(shared == 3 * control.segmentWidth)
        control.setWidth(100, forSegmentAt: 0)
        #expect(control.widthForSegment(at: 0) == 100 && control.sizeThatFits(.zero).width == 100 + 2 * control.segmentWidth)
        control.setWidth(0, forSegmentAt: 0)
        control.apportionsSegmentWidthsByContent = true
        let widths = control.segmentWidths(for: 0)
        #expect(widths[0] == 32 && widths[2] == 32 && widths[1] > 32 && widths[1] == control.segmentWidth, "\(widths)")
        // Image segments are 40 wide; a disabled segment ignores taps.
        let images = UISegmentedControl(items: [UIImage(systemName: "list.bullet")!, UIImage(systemName: "square.grid.2x2")!])
        #expect(images.frame.width == 80 && images.imageForSegment(at: 1) != nil)
        images.setEnabled(false, forSegmentAt: 1)
        images.selectedSegmentIndex = 0
        images.frame = CGRect(x: 0, y: 0, width: 80, height: 32)
        images.touchesBegan([UITouch(at: CGPoint(x: 60, y: 16), in: nil, view: images, type: .direct, timestamp: 0)], with: nil)
        images.touchesEnded([UITouch(at: CGPoint(x: 60, y: 16), in: nil, view: images, type: .direct, timestamp: 0.1)], with: nil)
        #expect(images.selectedSegmentIndex == 0)
    }

    @Test func stepperRepeatsWhileHeld() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let stepper = UIStepper()
        stepper.frame.origin = CGPoint(x: 16, y: 16)
        var changes = 0
        stepper.addAction(UIAction { _ in changes += 1 }, for: .valueChanged)
        window.addSubview(stepper)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 200))
        // The press steps at once; held, it repeats after half a second and every tenth after.
        scene.pointerDown(at: CGPoint(x: 16 + 70, y: 32), type: .touch, time: 0)
        #expect(stepper.value == 1 && changes == 1)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(stepper.value == 1)
        _ = scene.advanceFrame(elapsed: 0.25)
        #expect(stepper.value == 2)
        for _ in 0..<5 { _ = scene.advanceFrame(elapsed: 0.1) }
        #expect(stepper.value == 7, "\(stepper.value)")
        scene.pointerUp(at: CGPoint(x: 16 + 70, y: 32), time: 1)
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(stepper.value == 7, "released: no more steps")
        // Without autorepeat a hold steps once.
        stepper.autorepeat = false
        scene.pointerDown(at: CGPoint(x: 16 + 20, y: 32), type: .touch, time: 2)
        _ = scene.advanceFrame(elapsed: 1)
        scene.pointerUp(at: CGPoint(x: 16 + 20, y: 32), time: 3)
        #expect(stepper.value == 6)
        scene.removeAllWindows()
    }

    @Test func pageControlTapsAndScrubs() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let pages = UIPageControl()
        pages.numberOfPages = 4
        pages.currentPage = 1
        pages.sizeToFit()
        pages.frame.origin = CGPoint(x: 16, y: 16)
        var changes: [Int] = []
        pages.addAction(UIAction { _ in changes.append(pages.currentPage) }, for: .valueChanged)
        window.addSubview(pages)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 200))
        let frame = pages.frame
        // A tap on the trailing half goes forward, on the leading half back.
        scene.pointerDown(at: CGPoint(x: frame.maxX - 5, y: frame.midY), type: .touch, time: 0); scene.pointerUp(at: CGPoint(x: frame.maxX - 5, y: frame.midY), time: 0.1)
        #expect(pages.currentPage == 2)
        scene.pointerDown(at: CGPoint(x: frame.minX + 5, y: frame.midY), type: .touch, time: 1); scene.pointerUp(at: CGPoint(x: frame.minX + 5, y: frame.midY), time: 1.1)
        #expect(pages.currentPage == 1)
        // A drag across scrubs to the page under the finger.
        scene.pointerDown(at: CGPoint(x: frame.minX + 5, y: frame.midY), type: .touch, time: 2)
        scene.pointerMoved(to: CGPoint(x: frame.maxX - 2, y: frame.midY), time: 2.1)
        #expect(pages.currentPage == 3)
        scene.pointerMoved(to: CGPoint(x: frame.minX + 2, y: frame.midY), time: 2.2)
        scene.pointerUp(at: CGPoint(x: frame.minX + 2, y: frame.midY), time: 2.3)
        #expect(pages.currentPage == 0 && changes == [2, 1, 3, 0])
        pages.allowsContinuousInteraction = false
        scene.pointerDown(at: CGPoint(x: frame.minX + 5, y: frame.midY), type: .touch, time: 3)
        scene.pointerMoved(to: CGPoint(x: frame.maxX - 2, y: frame.midY), time: 3.1)
        scene.pointerUp(at: CGPoint(x: frame.maxX - 2, y: frame.midY), time: 3.2)
        #expect(pages.currentPage == 1, "no scrubbing: the release is a tap on the trailing half")
        scene.removeAllWindows()
    }
}
