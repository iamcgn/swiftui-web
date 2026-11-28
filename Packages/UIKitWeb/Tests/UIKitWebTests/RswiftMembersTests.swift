// UIKit members R.swift's library calls (Clendar's checked-in Pods): segues made in code and a
// controller's segue hooks, header and footer views registered and dequeued by identifier, and
// nib registrations, which a nib with no objects can only take or remove.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite(.serialized) @MainActor struct RswiftMembersTests {
    final class Source: NSObject, UITableViewDataSource, UITableViewDelegate {
        var headers: [UITableViewHeaderFooterView] = []
        var footers: [UITableViewHeaderFooterView] = []
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        }
        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header")
            header?.textLabel?.text = "Header"
            if let header { headers.append(header) }
            return header
        }
        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 30 }
        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: "footer")
            if let footer { footers.append(footer) }
            return footer
        }
        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 20 }
    }

    final class Header: UITableViewHeaderFooterView {
        var reuses = 0
        var madeWith: String?
        override init(reuseIdentifier: String?) {
            madeWith = reuseIdentifier
            super.init(reuseIdentifier: reuseIdentifier)
        }
        required init?(coder: NSCoder) { return nil }
        override func prepareForReuse() { reuses += 1 }
    }

    private func table() -> (UITableView, Source) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let table = UITableView(frame: window.bounds, style: .plain)
        table.rowHeight = 44
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.register(Header.self, forHeaderFooterViewReuseIdentifier: "header")
        table.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "footer")
        let source = Source()
        table.dataSource = source
        table.delegate = source
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: window.bounds.size)
        return (table, source)
    }

    @Test func aSegueMadeInCodePerformsItsHandler() {
        let source = UIViewController(), destination = UIViewController()
        var performed = 0
        let segue = UIStoryboardSegue(identifier: "show", source: source, destination: destination) { performed += 1 }
        #expect(segue.identifier == "show" && segue.source === source && segue.destination === destination)
        segue.perform()
        #expect(performed == 1)
        // Without a handler the base class performs nothing.
        UIStoryboardSegue(identifier: nil, source: source, destination: destination).perform()
        #expect(performed == 1)
        // A controller lets a segue go ahead unless it says otherwise, and its prepare hook
        // reaches a subclass's override.
        final class Prepared: UIViewController {
            var prepared: [String?] = []
            override func prepare(for segue: UIStoryboardSegue, sender: Any?) { prepared.append(segue.identifier) }
            override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool { identifier != "no" }
        }
        let prepared = Prepared()
        let base: UIViewController = prepared
        base.prepare(for: segue, sender: nil)
        #expect(prepared.prepared == ["show"])
        #expect(base.shouldPerformSegue(withIdentifier: "yes", sender: nil) && !base.shouldPerformSegue(withIdentifier: "no", sender: nil))
        #expect(source.shouldPerformSegue(withIdentifier: "any", sender: nil))
    }

    @Test func headerAndFooterViewsAreDequeuedByIdentifier() throws {
        let (table, source) = table()
        #expect(table.dequeueReusableHeaderFooterView(withIdentifier: "nothing") == nil)
        let header = try #require(source.headers.first)
        let footer = try #require(source.footers.first)
        #expect(header.reuseIdentifier == "header" && footer.reuseIdentifier == "footer")
        #if canImport(ObjectiveC)
        // The registered subclass, made through its own initializer.
        #expect((header as? Header)?.madeWith == "header")
        #endif
        // The header, both rows and the footer stack down the table at their heights.
        #expect(header.superview === table && header.frame == CGRect(x: 0, y: 0, width: 320, height: 30))
        #expect(table.rectForRow(at: IndexPath(row: 1, section: 0)) == CGRect(x: 0, y: 74, width: 320, height: 44))
        #expect(footer.superview === table && footer.frame == CGRect(x: 0, y: 118, width: 320, height: 20))
        #expect(table.contentSize.height == 138)
        #expect(table.headerView(forSection: 0) === header && table.footerView(forSection: 0) === footer)
        // A reload hands the same views back, each prepared for reuse.
        table.reloadData()
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 300))
        #expect(source.headers.count == 2 && source.headers[1] === header)
        #expect(source.footers.count == 2 && source.footers[1] === footer)
        #if canImport(ObjectiveC)
        #expect((header as? Header)?.reuses == 1)
        #endif
        // Unregistering takes the kind away.
        table.register(nil as AnyClass?, forHeaderFooterViewReuseIdentifier: "footer")
        table.register(nil as UINib?, forHeaderFooterViewReuseIdentifier: "header")
        #expect(table.dequeueReusableHeaderFooterView(withIdentifier: "footer") == nil)
    }

    @Test func nibRegistrationsAreTakenAndRemoved() {
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)
        let nib = UINib(nibName: "Cell", bundle: nil)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        #expect(table.dequeueReusableCell(withIdentifier: "cell") != nil)
        table.register(nil as UINib?, forCellReuseIdentifier: "cell")
        #expect(table.dequeueReusableCell(withIdentifier: "cell") == nil)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.register(nil as AnyClass?, forCellReuseIdentifier: "cell")
        #expect(table.dequeueReusableCell(withIdentifier: "cell") == nil)
        // A nib registers (dequeuing it would stop the app: the nib holds no cell).
        table.register(nib, forCellReuseIdentifier: "nib")
        table.register(nib, forHeaderFooterViewReuseIdentifier: "nib")

        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), collectionViewLayout: UICollectionViewFlowLayout())
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        #expect(collection.hasRegisteredCell(withIdentifier: "cell"))
        collection.register(nil as UINib?, forCellWithReuseIdentifier: "cell")
        #expect(!collection.hasRegisteredCell(withIdentifier: "cell"))
        collection.register(nib, forCellWithReuseIdentifier: "nib")
        #expect(collection.hasRegisteredCell(withIdentifier: "nib"))
        collection.register(nib, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "nib")
        collection.register(nil as UINib?, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "nib")
    }
}
