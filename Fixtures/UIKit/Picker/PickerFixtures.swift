// UIPickerView (Docs/elements/UIKit/DatePicker.md): a two-component picker with a data source
// and delegate titles, a row selected in each, sized to fit, measured against UIKit on the
// simulator (the frame; the drum is approximate).
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

final class PickerSource: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    let sizes = ["Small", "Medium", "Large", "Extra Large"]
    let counts = (1...10).map { "\($0)" }
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { component == 0 ? sizes.count : counts.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { component == 0 ? sizes[row] : counts[row] }
}

public enum PickerFixtures {
    public static let all = [basic]

    @MainActor static var sources: [PickerSource] = []

    public static let basic = UIKitFixture("uikit/picker/basic", size: CGSize(width: 320, height: 240)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        root.backgroundColor = .white
        let source = PickerSource()
        sources.append(source)
        let picker = UIPickerView()
        picker.dataSource = source
        picker.delegate = source
        picker.sizeToFit()
        picker.frame.origin = CGPoint(x: 0, y: 12)
        picker.selectRow(1, inComponent: 0, animated: false)
        picker.selectRow(4, inComponent: 1, animated: false)
        root.addSubview(picker.probe("picker"))
        return root
    }
}
#endif
