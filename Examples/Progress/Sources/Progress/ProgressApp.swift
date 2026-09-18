// The SwiftUIWeb progress page (decision 0016): what works and what is next, written in nothing
// but SwiftUI and rendered by SwiftUIWeb at /progress/ (and natively with `swift run Progress`).
// The data comes from Docs/support.json and Docs/todo.json through `scripts/gen-progress.py`
// (ProgressData.swift); every support row links to the gallery fixtures that prove it and every
// todo item to the docs it refers to.
import SwiftUI

@main
struct ProgressApp: App {
    var body: some Scene {
        WindowGroup {
            GeometryReader { proxy in
                ProgressPage().environment(\.isCompact, proxy.size.width < 700)
            }
            #if canImport(SwiftUIWebCore)
            .environment(\.platformProfile, .macOS)
            #endif
        }
    }
}

// MARK: - Data

enum SupportStatus: String, CaseIterable {
    case full, partial, approximate, stub, missing
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var meaning: String {
        switch self {
        case .full: return "API complete; fixtures pass exact layout and pixel checks"
        case .partial: return "Common usage works; listed gaps"
        case .approximate: return "Works but rendering knowingly differs"
        case .stub: return "Compiles, no behaviour"
        case .missing: return "Not implemented yet"
        }
    }
    var color: Color {
        switch self {
        case .full: return Color(red: 0.16, green: 0.70, blue: 0.30)
        case .partial: return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .approximate: return Color(red: 0.95, green: 0.65, blue: 0.10)
        case .stub: return Color(red: 0.60, green: 0.60, blue: 0.65)
        case .missing: return Color(red: 0.90, green: 0.25, blue: 0.25)
        }
    }
}

struct SupportRow: Identifiable {
    let id: Int
    let framework: String
    let section: String
    let status: SupportStatus
    let api: String
    let notes: String
    let fixtures: [String]
    let noFixture: String
}

enum Priority: String, CaseIterable {
    case next, soon, later
    var title: String {
        switch self {
        case .next: return "Next (Phase 8, in order)"
        case .soon: return "Soon (the gap sweep)"
        case .later: return "Later (needs a decision, a subsystem or a platform)"
        }
    }
}

enum ItemStatus: String {
    case planned, inProgress = "in-progress", done, wontfix
    var mark: String {
        switch self {
        case .planned: return "☐"
        case .inProgress: return "◐"
        case .done: return "☑"
        case .wontfix: return "✕"
        }
    }
}

struct TodoItem: Identifiable {
    let id: String
    let framework: String
    let area: String
    let priority: Priority
    let status: ItemStatus
    let kind: String
    let title: String
    let detail: String
    let done: String
    let refs: [String]
}

enum Site {
    static let frameworks = ["SwiftUI", "UIKit", "Interop", "Site", "Platform"]
    static let repository = "https://github.com/iamcgn/swiftui-web"
    static func doc(_ path: String) -> URL? { URL(string: "\(repository)/blob/main/\(path)") }
    /// The gallery next to this page: one fixture, or every fixture of a prefix.
    static func gallery(fixture: String) -> URL? {
        let encoded = fixture.split(separator: "/", omittingEmptySubsequences: false).joined(separator: "%2F")   // no Foundation on wasm
        return URL(string: fixture.hasSuffix("*") ? "../gallery/?filter=\(String(encoded.dropLast(3)))" : "../gallery/?fixture=\(encoded)")
    }
    static let accent = Color(red: 0.98, green: 0.36, blue: 0.22)
    static let accentEnd = Color(red: 0.62, green: 0.20, blue: 0.85)
    static var gradient: LinearGradient { LinearGradient(colors: [accent, accentEnd], startPoint: .leading, endPoint: .trailing) }
    static let line = Color(red: 0.88, green: 0.88, blue: 0.90)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.98)
}

enum Model {
    static let rows: [SupportRow] = {
        var rows: [SupportRow] = []
        for line in ProgressData.supportBlob.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 7, let status = SupportStatus(rawValue: f[2]) else { continue }
            rows.append(SupportRow(id: rows.count, framework: f[0], section: f[1], status: status, api: f[3], notes: f[4],
                                   fixtures: f[5].isEmpty ? [] : f[5].split(separator: "|").map(String.init), noFixture: f[6]))
        }
        return rows
    }()

    static let items: [TodoItem] = {
        var items: [TodoItem] = []
        for line in ProgressData.todoBlob.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 10, let priority = Priority(rawValue: f[3]), let status = ItemStatus(rawValue: f[4]) else { continue }
            items.append(TodoItem(id: f[0], framework: f[1], area: f[2], priority: priority, status: status, kind: f[5], title: f[6], detail: f[7],
                                  done: f[8], refs: f[9].isEmpty ? [] : f[9].split(separator: "|").map(String.init)))
        }
        return items
    }()

    /// The sections in file order, each with its framework.
    static let sections: [(framework: String, title: String)] = {
        var seen: [(String, String)] = []
        for row in rows where !seen.contains(where: { $0.0 == row.framework && $0.1 == row.section }) { seen.append((row.framework, row.section)) }
        return seen
    }()
}

struct CompactKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isCompact: Bool { get { self[CompactKey.self] } set { self[CompactKey.self] = newValue } }
}

// MARK: - Page

struct ProgressPage: View {
    @Environment(\.isCompact) private var compact
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Header()
                Counts()
                Matrix()
                Todo()
                Landed()
                Footer()
            }
            .padding(.horizontal, compact ? 16 : 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("SwiftUIWeb").font(.system(size: 22, weight: .bold)).foregroundStyle(Site.gradient)
                Text("progress").font(.system(size: 22, weight: .semibold))
                Spacer()
                Link("Landing page", destination: URL(string: "../")!)
                Link("Gallery", destination: URL(string: "../gallery/")!)
                Link("Repository", destination: URL(string: Site.repository)!)
            }
            Text("What works, what is planned and what landed, from the repository's two tracking files (`Docs/support.json` and `Docs/todo.json`, last edited \(ProgressData.edited)). Every row that does something links to the fixtures that prove it in the gallery; every item links to the docs it refers to.")
                .foregroundColor(.secondary)
        }
    }
}

struct Counts: View {
    @Environment(\.isCompact) private var compact
    private func count(_ framework: String, _ status: SupportStatus?) -> Int {
        Model.rows.filter { $0.framework == framework && (status == nil || $0.status == status) }.count
    }
    private func open(_ framework: String, _ priority: Priority?) -> Int {
        Model.items.filter { $0.framework == framework && ($0.status == .planned || $0.status == .inProgress) && (priority == nil || $0.priority == priority) }.count
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By the numbers").font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 140 : 200), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(["SwiftUI", "UIKit", "Interop"], id: \.self) { framework in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(framework).font(.headline)
                            Text("\(count(framework, nil)) rows").font(.system(size: 26, weight: .bold)).foregroundStyle(Site.gradient)
                            HStack(spacing: 8) {
                                ForEach(SupportStatus.allCases, id: \.self) { status in
                                    let n = count(framework, status)
                                    if n > 0 {
                                        HStack(spacing: 3) { Circle().fill(status.color).frame(width: 7, height: 7); Text("\(n)").font(.caption) }
                                    }
                                }
                            }
                            let items = Model.items.filter { $0.framework == framework }
                            Text("\(open(framework, nil)) open items (\(open(framework, .next)) next, \(open(framework, .soon)) soon, \(open(framework, .later)) later); \(items.filter { $0.status == .done }.count) landed")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Site.paper))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.line, lineWidth: 1))
    }
}

// MARK: - Matrix

struct Matrix: View {
    @State private var filter: SupportStatus? = nil
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @Environment(\.isCompact) private var compact

    private func matches(_ row: SupportRow) -> Bool {
        (filter == nil || row.status == filter) && (query.isEmpty || row.api.lowercased().contains(query.lowercased()) || row.notes.lowercased().contains(query.lowercased()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The support matrix").font(.title2.weight(.semibold))
            TextField("Search the rows", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
                Pill(title: "All", color: nil, count: Model.rows.count, selected: filter == nil) { filter = nil }
                ForEach(SupportStatus.allCases, id: \.self) { status in
                    Pill(title: status.title, color: status.color, count: Model.rows.filter { $0.status == status }.count, selected: filter == status) { filter = status }
                }
            }
            ForEach(["SwiftUI", "UIKit", "Interop"], id: \.self) { framework in
                let sections = Model.sections.filter { $0.framework == framework }
                Text(framework).font(.headline).padding(.top, 8)
                ForEach(sections, id: \.title) { section in
                    let rows = Model.rows.filter { $0.section == section.title && $0.framework == framework && matches($0) }
                    if !rows.isEmpty {
                        let open = expanded.contains(section.title) || !query.isEmpty
                        DisclosureGroup(isExpanded: Binding(get: { open }, set: { on in if on { expanded.insert(section.title) } else { expanded.remove(section.title) } })) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(rows) { row in
                                    RowView(row: row)
                                    Divider()
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack { Text(section.title).font(.system(size: 14, weight: .semibold)); Text("\(rows.count)").font(.caption).foregroundColor(.secondary) }
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 8) {
                ForEach(SupportStatus.allCases, id: \.self) { status in
                    HStack(spacing: 6) { Circle().fill(status.color).frame(width: 9, height: 9); Text(status.meaning).font(.caption).foregroundColor(.secondary) }
                }
            }
        }
    }
}

struct Pill: View {
    let title: String
    let color: Color?
    let count: Int
    let selected: Bool
    let action: @MainActor @Sendable () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 9, height: 9) }
                Text(title).fixedSize()
                Text("\(count)").foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(selected ? Color.primary.opacity(0.85) : Site.paper))
            .foregroundColor(selected ? Color.white : .primary)
            .overlay(Capsule().stroke(Site.line, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct RowView: View {
    let row: SupportRow
    @Environment(\.isCompact) private var compact
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(row.status.color).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.api).font(.system(size: 13, weight: .semibold))
                if !row.notes.isEmpty { Text(row.notes).font(.callout).foregroundColor(.secondary) }
                if !row.fixtures.isEmpty {
                    HStack(spacing: 8) {
                        Text("Fixtures:").font(.caption).foregroundColor(.secondary)
                        ForEach(row.fixtures.prefix(6), id: \.self) { fixture in
                            if let url = Site.gallery(fixture: fixture) { Link(fixture, destination: url).font(.caption) }
                        }
                        if row.fixtures.count > 6 { Text("+\(row.fixtures.count - 6)").font(.caption).foregroundColor(.secondary) }
                    }
                } else if !row.noFixture.isEmpty {
                    Text("No fixture: \(row.noFixture)").font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact { Text(row.status.title).font(.caption).foregroundColor(.secondary).frame(width: 84, alignment: .trailing) }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Todo

struct Todo: View {
    @State private var framework: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What is next").font(.title2.weight(.semibold))
            Text("Priorities: next is Phase 8 of the roadmap in order, soon the gap sweep after it (what ordinary apps hit), later what needs a decision, a subsystem or a platform that does not exist yet. Kinds: missing (no API), accepted (compiles, no behaviour), approximate (behaves, pixels or motion differ), verify (never measured against Apple), infra (tooling, docs, site).")
                .font(.callout).foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], alignment: .leading, spacing: 10) {
                Pill(title: "All", color: nil, count: openItems(nil).count, selected: framework == nil) { framework = nil }
                ForEach(Site.frameworks, id: \.self) { fw in
                    let n = openItems(fw).count
                    if n > 0 { Pill(title: fw, color: nil, count: n, selected: framework == fw) { framework = fw } }
                }
            }
            ForEach(Priority.allCases, id: \.self) { priority in
                let items = openItems(framework).filter { $0.priority == priority }
                if !items.isEmpty {
                    Text(priority.title).font(.headline).padding(.top, 8)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            ItemView(item: item)
                            Divider()
                        }
                    }
                }
            }
        }
    }
    private func openItems(_ framework: String?) -> [TodoItem] {
        Model.items.filter { ($0.status == .planned || $0.status == .inProgress) && (framework == nil || $0.framework == framework) }
    }
}

struct ItemView: View {
    let item: TodoItem
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.status.mark).frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title).font(.system(size: 13, weight: .semibold))
                    Text("\(item.framework) · \(item.area) · \(item.kind)").font(.caption).foregroundColor(.secondary)
                }
                Text(item.detail).font(.callout).foregroundColor(.secondary)
                if !item.refs.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(item.refs, id: \.self) { ref in
                            if let url = Site.doc(ref) { Link(ref.split(separator: "/").last.map(String.init) ?? ref, destination: url).font(.caption) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

struct Landed: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently landed").font(.title2.weight(.semibold))
            let done = Model.items.filter { $0.status == .done }.sorted { $0.done > $1.done }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(done.prefix(25)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.done).font(.caption.monospacedDigit()).foregroundColor(.secondary).frame(width: 84, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text("\(item.framework) · \(item.area)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
            let wontfix = Model.items.filter { $0.status == .wontfix }
            if !wontfix.isEmpty {
                Text("Non-goals").font(.headline).padding(.top, 8)
                ForEach(wontfix) { item in
                    Text("✕ \(item.title) (\(item.framework)): \(item.detail)").font(.callout).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct Footer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("This page is a SwiftUI app rendered by SwiftUIWeb, like the landing page and the gallery. Its data is generated by scripts/gen-progress.py; CI refuses stale outputs.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}
