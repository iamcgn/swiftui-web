// UITableView (Docs/elements/UIKit/TableView.md): the plain and inset grouped styles with the
// default, subtitle and value1 cell styles, accessories, section headers and footers, and a
// selected row, measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// A table whose rows come from a fixed list of (title, detail) pairs per section.
final class TableSource: NSObject, UITableViewDataSource, UITableViewDelegate {
    struct Section {
        var header: String?
        var footer: String?
        var rows: [(title: String, detail: String?, accessory: UITableViewCell.AccessoryType)]
    }
    var sections: [Section] = []
    var cellStyle: UITableViewCell.CellStyle = .default
    var probes: [IndexPath: String] = [:]

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].header }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: cellStyle, reuseIdentifier: "cell")
        let row = sections[indexPath.section].rows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.detail
        cell.accessoryType = row.accessory
        if let probe = probes[indexPath] { cell.probe(probe) }
        return cell
    }
}

@MainActor public final class TableModel {
    var table: UITableView?
    var source: TableSource?
    public init() {}
}

public enum TableFixtures {
    public static let all = [plain, subtitle, grouped, selection]

    @MainActor static func make(style: UITableView.Style, cellStyle: UITableViewCell.CellStyle, sections: [TableSource.Section], probes: [IndexPath: String],
                                model: TableModel? = nil) -> UIView {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let source = TableSource()
        source.sections = sections
        source.cellStyle = cellStyle
        source.probes = probes
        let table = UITableView(frame: root.bounds, style: style)
        table.dataSource = source
        table.delegate = source
        root.addSubview(table.probe("table"))
        model?.table = table
        model?.source = source
        // The source must outlive the closure: the table keeps it weakly, as UIKit does.
        root.layer.name = "\(ObjectIdentifier(source).hashValue)"
        TableFixtures.sources.append(source)
        return root
    }

    @MainActor static var sources: [TableSource] = []

    /// A plain table: one section without a header, default cells with and without accessories.
    public static let plain = UIKitFixture("uikit/table/plain", size: CGSize(width: 320, height: 400)) {
        make(style: .plain, cellStyle: .default, sections: [
            .init(header: nil, footer: nil, rows: [("First row", nil, .none), ("Second row", nil, .disclosureIndicator), ("Third row", nil, .checkmark), ("Fourth row", nil, .none)]),
        ], probes: [IndexPath(row: 0, section: 0): "row0", IndexPath(row: 1, section: 0): "row1", IndexPath(row: 3, section: 0): "row3"])
    }

    /// Subtitle cells with a header, under the plain style.
    public static let subtitle = UIKitFixture("uikit/table/subtitle", size: CGSize(width: 320, height: 400)) {
        make(style: .plain, cellStyle: .subtitle, sections: [
            .init(header: "Header", footer: nil, rows: [("Title", "Detail text", .none), ("Another title", "More detail", .disclosureIndicator)]),
        ], probes: [IndexPath(row: 0, section: 0): "row0", IndexPath(row: 1, section: 0): "row1"])
    }

    /// The inset grouped style: two sections with headers and a footer, value1 cells.
    public static let grouped = UIKitFixture("uikit/table/grouped", size: CGSize(width: 320, height: 400)) {
        make(style: .insetGrouped, cellStyle: .value1, sections: [
            .init(header: "General", footer: "A footer note.", rows: [("Name", "iPhone", .disclosureIndicator), ("Software", "26.0", .none)]),
            .init(header: "Display", footer: nil, rows: [("Brightness", nil, .none)]),
        ], probes: [IndexPath(row: 0, section: 0): "row0", IndexPath(row: 1, section: 0): "row1", IndexPath(row: 0, section: 1): "row2"])
    }

    /// Selecting a row highlights it; deselecting clears it.
    public static let selection = UIKitFixture("uikit/table/selection", size: CGSize(width: 320, height: 400),
                                               model: { TableModel() },
                                               steps: [UIKitFixtureStep("select") { $0.table?.selectRow(at: IndexPath(row: 1, section: 0), animated: false, scrollPosition: .none) },
                                                       UIKitFixtureStep("deselect") { $0.table?.deselectRow(at: IndexPath(row: 1, section: 0), animated: false) }]) { model in
        make(style: .plain, cellStyle: .default, sections: [
            .init(header: nil, footer: nil, rows: [("First row", nil, .none), ("Second row", nil, .none), ("Third row", nil, .none)]),
        ], probes: [IndexPath(row: 1, section: 0): "row1"], model: model)
    }
}
#endif
