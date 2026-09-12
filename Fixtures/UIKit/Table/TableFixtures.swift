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


/// A cell whose height comes from a wrapping label constrained 16 in and 12 above and below.
final class NoteCell: UITableViewCell {
    let note = UILabel()   // constrained on first configure: no initializer to mirror on both UIKits
    private var constrained = false
    func configure(_ text: String, size: CGFloat) {
        note.text = text
        note.font = .systemFont(ofSize: size)
        note.numberOfLines = 0
        guard !constrained else { return }
        constrained = true
        note.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(note)
        NSLayoutConstraint.activate([
            note.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            note.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            note.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            note.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }
}

/// Rows sized by their content: default cells with wrapping text labels and note cells.
final class SelfSizingSource: NSObject, UITableViewDataSource {
    let rows: [(text: String, custom: Bool, size: CGFloat)] = [
        ("Short", false, 17),
        ("A default cell whose text label wraps onto several lines when the text runs past the cell's width", false, 17),
        ("A note cell sized by its constrained label, twelve points above and below the text", true, 15),
        ("A longer note that needs a third line at this size once it has said everything it has to say about itself", true, 15),
        ("A footnote-sized note wrapping onto a second line inside the very same cell", true, 13),
    ]
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        if row.custom {
            let cell = tableView.dequeueReusableCell(withIdentifier: "note") as? NoteCell ?? NoteCell(style: .default, reuseIdentifier: "note")
            cell.configure(row.text, size: row.size)
            cell.note.probe("label\(indexPath.row)")
            return cell.probe("row\(indexPath.row)")
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
        cell.textLabel?.text = row.text
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.probe("label\(indexPath.row)")
        return cell.probe("row\(indexPath.row)")
    }
}


/// Rows that can be edited: the first two delete and reorder, the third inserts, the fourth
/// cannot be edited.
final class EditingSource: NSObject, UITableViewDataSource, UITableViewDelegate {
    var rows = ["Milk", "Eggs", "Add an item", "Fixed"]
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
        cell.textLabel?.text = rows[indexPath.row]
        cell.accessoryType = indexPath.row == 0 ? .disclosureIndicator : .none
        cell.showsReorderControl = indexPath.row < 2
        cell.textLabel?.probe("label\(indexPath.row)")
        return cell.probe("row\(indexPath.row)")
    }
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { indexPath.row != 3 }
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { indexPath.row < 2 }
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        rows.insert(rows.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)
    }
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        indexPath.row == 2 ? .insert : .delete
    }
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            rows.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
}


/// Sections lettered A to F with an index strip on the right.
final class IndexedSource: NSObject, UITableViewDataSource {
    let sections: [(title: String, rows: [String])] = [
        ("A", ["Ada", "Alan"]), ("B", ["Barbara", "Bjarne"]), ("C", ["Claude"]), ("D", ["Dennis", "Donald"]), ("E", ["Edsger"]), ("F", ["Frances"]),
    ]
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
        cell.textLabel?.text = sections[indexPath.section].rows[indexPath.row]
        if indexPath.row == 0 { cell.textLabel?.probe("label\(indexPath.section)") }
        return indexPath.row == 0 ? cell.probe("row\(indexPath.section)") : cell
    }
    func sectionIndexTitles(for tableView: UITableView) -> [String]? { sections.map(\.title) }
    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int { index }
}

@MainActor public final class TableModel {
    var table: UITableView?
    var source: TableSource?
    public init() {}
}

public enum TableFixtures {
    public static let all = [plain, subtitle, grouped, selection, pinned, selfSizing, editing, indexed]

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

    /// Plain-style section headers pin to the top while their section scrolls under them and
    /// are pushed away by the next header.
    public static let pinned = UIKitFixture("uikit/table/pinned", size: CGSize(width: 320, height: 300),
                                            model: { TableModel() },
                                            steps: [UIKitFixtureStep("scroll") { model in
                                                        model.table?.contentOffset = CGPoint(x: 0, y: 100)
                                                        model.table?.layoutIfNeeded()
                                                        model.table?.headerView(forSection: 0)?.probe("header0")
                                                        model.table?.headerView(forSection: 1)?.probe("header1")
                                                    },
                                                    UIKitFixtureStep("push") { model in
                                                        model.table?.contentOffset = CGPoint(x: 0, y: 260)
                                                        model.table?.layoutIfNeeded()
                                                        model.table?.headerView(forSection: 0)?.probe("header0")
                                                        model.table?.headerView(forSection: 1)?.probe("header1")
                                                    }]) { model in
        make(style: .plain, cellStyle: .default, sections: [
            .init(header: "Alpha", footer: nil, rows: [("One", nil, .none), ("Two", nil, .none), ("Three", nil, .none), ("Four", nil, .none)]),
            .init(header: "Beta", footer: nil, rows: [("Five", nil, .none), ("Six", nil, .none), ("Seven", nil, .none), ("Eight", nil, .none)]),
        ], probes: [IndexPath(row: 0, section: 0): "row0", IndexPath(row: 0, section: 1): "row4"], model: model)
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

    /// Automatic row heights from an estimate: wrapping text labels in default cells and a
    /// custom cell with a constrained label.
    public static let selfSizing = UIKitFixture("uikit/table/selfsizing", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let source = SelfSizingSource()
        selfSizingSources.append(source)
        let table = UITableView(frame: root.bounds, style: .plain)
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 44
        table.dataSource = source
        root.addSubview(table.probe("table"))
        return root
    }

    @MainActor static var selfSizingSources: [SelfSizingSource] = []

    /// Editing mode: the rows shift right behind delete and insert controls, movable rows show
    /// a reorder handle, a row that cannot be edited stays put.
    public static let editing = UIKitFixture("uikit/table/editing", size: CGSize(width: 320, height: 300),
                                             model: { TableModel() },
                                             steps: [UIKitFixtureStep("edit") { model in
                                                         model.table?.setEditing(true, animated: false)
                                                         model.table?.layoutIfNeeded()
                                                     },
                                                     UIKitFixtureStep("done") { model in
                                                         model.table?.setEditing(false, animated: false)
                                                         model.table?.layoutIfNeeded()
                                                     }]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let source = EditingSource()
        editingSources.append(source)
        let table = UITableView(frame: root.bounds, style: .plain)
        table.rowHeight = 44
        table.dataSource = source
        table.delegate = source
        root.addSubview(table.probe("table"))
        model.table = table
        return root
    }

    @MainActor static var editingSources: [EditingSource] = []

    /// A plain table with lettered section headers and the section index strip.
    public static let indexed = UIKitFixture("uikit/table/indexed", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let source = IndexedSource()
        indexedSources.append(source)
        let table = UITableView(frame: root.bounds, style: .plain)
        table.rowHeight = 44
        table.dataSource = source
        root.addSubview(table.probe("table"))
        return root
    }

    @MainActor static var indexedSources: [IndexedSource] = []
}
#endif
