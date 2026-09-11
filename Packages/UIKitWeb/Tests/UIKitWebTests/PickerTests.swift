// UIPickerView (Controls/UIPickerView.swift): rows from the data source and delegate, selection,
// the fitted size, and the semantics node stepping the first component.
import Testing
import UIKit
#if canImport(AppKit)
import WebGraphicsNative
#endif

@MainActor
private final class Source: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    let sizes = ["Small", "Medium", "Large"]
    var selections: [(Int, Int)] = []
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { component == 0 ? sizes.count : 10 }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { component == 0 ? sizes[row] : "\(row + 1)" }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) { selections.append((row, component)) }
}

@Suite @MainActor struct PickerTests {
    @Test func rowsSelectionAndSize() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        #if canImport(AppKit)
        scene.textEngine = CoreTextEngine()   // the drum's scaled fonts are not in the recordings
        #else
        scene.textEngine = try! Goldens.textEngine()
        #endif
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        let source = Source()
        let picker = UIPickerView()
        picker.dataSource = source
        picker.delegate = source
        picker.sizeToFit()
        #expect(picker.frame.size == CGSize(width: 320, height: 216))
        #expect(picker.numberOfComponents == 2)
        #expect(picker.numberOfRows(inComponent: 1) == 10)
        picker.selectRow(1, inComponent: 0, animated: false)
        picker.selectRow(4, inComponent: 1, animated: false)
        #expect(picker.selectedRow(inComponent: 0) == 1)
        #expect(picker.selectedRow(inComponent: 1) == 4)
        root.view.addSubview(picker)
        scene.layout(in: CGSize(width: 320, height: 400))
        let node = scene.semanticsTree().first { $0.role == .slider }
        #expect(node?.label == "Medium 5")
        guard let id = node?.identifier else { Issue.record("no node"); return }
        scene.adjust(semanticsIdentifier: id, increment: true)
        #expect(picker.selectedRow(inComponent: 0) == 2)
        #expect(source.selections.map(\.0) == [2])
        scene.adjust(semanticsIdentifier: id, increment: true)
        #expect(picker.selectedRow(inComponent: 0) == 2)
        let drawn = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(drawn.contains("Large") && drawn.contains("5"))
    }
}
