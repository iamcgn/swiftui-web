// The SwiftUIWeb landing page: a sales page for the repository written in nothing but SwiftUI,
// rendered by SwiftUIWeb itself in the browser (and natively with `swift run Landing`).
//
// This file and SupportData.swift are meant to live in a GitHub gist as well as in
// Examples/Landing (`scripts/landing-gist.sh push` / `pull`): keep them self-contained, with no
// dependency beyond `import SwiftUI`. The feature list comes from Docs/support.json through
// `scripts/gen-landing-support.py`; rerun it after adding an element so the page stays current.
import SwiftUI

@main
struct LandingApp: App {
    var body: some Scene {
        WindowGroup {
            // The reader sits outside the scroll view so scrolling never re-lays the page out.
            GeometryReader { proxy in
                LandingPage().environment(\.isCompact, proxy.size.width < Site.compactWidth)
            }
        }
    }
}

enum Theme: CaseIterable {
    case system, light, dark

    /// The scheme to prefer: `nil` follows the system.
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var symbol: String {
        switch self {
        case .system: return "desktopcomputer"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var title: String {
        switch self {
        case .system: return "System appearance"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// The page's surfaces per appearance; text uses the system label colours, which follow the
/// scheme on their own.
struct Palette {
    let page: Color
    let paper: Color
    let card: Color
    let line: Color
    let code: Color
    let codeText: Color
    let pillSelected: Color
    let pillSelectedText: Color

    static let light = Palette(page: .white, paper: Site.paper, card: .white, line: Site.line, code: Site.ink,
                               codeText: Color(white: 0.92), pillSelected: Site.ink, pillSelectedText: .white)
    static let dark = Palette(page: Color(red: 0.09, green: 0.09, blue: 0.11), paper: Color(red: 0.14, green: 0.14, blue: 0.17),
                              card: Color(red: 0.12, green: 0.12, blue: 0.14), line: Color(red: 0.24, green: 0.24, blue: 0.27),
                              code: Color(red: 0.16, green: 0.16, blue: 0.19), codeText: Color(white: 0.92),
                              pillSelected: Color(white: 0.92), pillSelectedText: Site.ink)
}

extension EnvironmentValues {
    var palette: Palette { colorScheme == .dark ? .dark : .light }
}

/// Phone-width layouts: one column, smaller display type, stacked rows.
struct CompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isCompact: Bool {
        get { self[CompactKey.self] }
        set { self[CompactKey.self] = newValue }
    }
}

/// Two columns side by side, or stacked when compact.
struct Columns<First: View, Second: View>: View {
    @Environment(\.isCompact) private var compact
    let secondWidth: CGFloat
    @ViewBuilder let first: First
    @ViewBuilder let second: Second

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 24) {
                first
                second
            }
        } else {
            HStack(alignment: .top, spacing: 32) {
                first.frame(maxWidth: .infinity, alignment: .leading)
                second.frame(width: secondWidth)
            }
        }
    }
}

// MARK: - Page

enum Site {
    static let repository = URL(string: "https://github.com/iamcgn/swiftui-web")!
    static let matrix = URL(string: "https://github.com/iamcgn/swiftui-web/blob/main/Docs/support-matrix.md")!
    static let roadmap = URL(string: "https://github.com/iamcgn/swiftui-web/blob/main/Docs/ROADMAP.md")!
    static let architecture = URL(string: "https://github.com/iamcgn/swiftui-web/blob/main/Docs/ARCHITECTURE.md")!
    static let workflow = URL(string: "https://github.com/iamcgn/swiftui-web/blob/main/Docs/ELEMENT_WORKFLOW.md")!
    static let license = URL(string: "https://github.com/iamcgn/swiftui-web/blob/main/LICENSE")!
    static let contentWidth: CGFloat = 960
    static let compactWidth: CGFloat = 700
    static let accent = Color(red: 0.98, green: 0.36, blue: 0.22)
    static let accentEnd = Color(red: 0.62, green: 0.20, blue: 0.85)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let line = Color(red: 0.88, green: 0.88, blue: 0.90)
    static var gradient: LinearGradient { LinearGradient(colors: [accent, accentEnd], startPoint: .leading, endPoint: .trailing) }
}

struct LandingPage: View {
    /// The header's theme switch: the system appearance, or a scheme the visitor picked.
    @State private var theme: Theme = .system
    @Environment(\.isCompact) private var compact
    @Environment(\.palette) private var palette
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationBar(theme: $theme)
                Hero()
                Highlights()
                Demos()
                IOSDemo()
                HowItWorks()
                SupportMatrix()
                Footer()
            }
            .frame(maxWidth: Site.contentWidth)
            .padding(.horizontal, compact ? 16 : 24)
            .frame(maxWidth: .infinity)
        }
        .background(palette.page)
        .preferredColorScheme(theme.scheme)
    }
}

// MARK: - Navigation bar

struct NavigationBar: View {
    @Binding var theme: Theme
    @Environment(\.openURL) private var openURL
    @Environment(\.isCompact) private var compact
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: compact ? 12 : 20) {
            HStack(spacing: 8) {
                Wordmark(size: 22)
                if !compact { Text("SwiftUIWeb").font(.system(size: 18, weight: .semibold)).fixedSize() }
            }
            Spacer()
            if !compact {
                Link("Docs", destination: Site.architecture)
                Link("Support matrix", destination: Site.matrix)
                Link("Roadmap", destination: Site.roadmap)
            }
            ThemeSwitcher(theme: $theme)
            Button { openURL(Site.repository) } label: { Label("GitHub", systemImage: "link") }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
    }
}

/// System / light / dark, as three symbol buttons in a capsule; the choice becomes the page's
/// `preferredColorScheme`.
struct ThemeSwitcher: View {
    @Binding var theme: Theme
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Theme.allCases, id: \.self) { option in
                Button { theme = option } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 24)
                        .background(Capsule().fill(option == theme ? palette.pillSelected : .clear))
                        .foregroundColor(option == theme ? palette.pillSelectedText : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
            }
        }
        .padding(3)
        .background(Capsule().fill(palette.paper))
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
    }
}

/// The wordmark: a rounded square in the site gradient with a bold "S".
struct Wordmark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Site.gradient)
            Text("S").font(.system(size: size * 0.62, weight: .heavy)).foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Hero

struct Hero: View {
    @State private var count = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.isCompact) private var compact
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text(compact ? "This page is SwiftUI on a canvas" : "This whole page is SwiftUI, painted on a canvas")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(palette.paper))
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))

            Text("Your SwiftUI.\nIn the browser.")
                .font(.system(size: compact ? 40 : 60, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Site.gradient)

            Text("SwiftUIWeb runs unmodified SwiftUI source in any browser through WebAssembly, and natively on macOS. No custom compiler, no DOM translation: a layout engine written from the documented semantics and a painter that draws exactly what Apple's SwiftUI draws, verified pixel by pixel against goldens rendered by the real thing.")
                .font(compact ? .body : .title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)

            HStack(spacing: 12) {
                Button { openURL(Site.repository) } label: { Label("Get the source", systemImage: "arrow.right") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button { openURL(Site.matrix) } label: { Label("See what works", systemImage: "checkmark.circle.fill") }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .fixedSize()

            // The Counter from the README, alive, in the page it advertises.
            VStack(spacing: 12) {
                Text("Count: \(count)").font(.title)
                HStack {
                    Button("−") { count -= 1 }
                    Button("+") { count += 1 }
                }
                Text("The README's counter, running unmodified.").font(.footnote).foregroundColor(.secondary)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                Stat(value: "\(SupportData.total)", label: "APIs tracked in the matrix")
                Stat(value: "\(SupportData.counts[.full, default: 0] + SupportData.counts[.partial, default: 0])", label: "verified against Apple's goldens")
                Stat(value: "3", label: "browsers checked: Chromium, WebKit, Firefox")
                Stat(value: "0", label: "lines of your SwiftUI changed")
            }
            .frame(maxWidth: 720)
            .padding(.top, 8)
        }
        .padding(.vertical, compact ? 40 : 64)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 30, weight: .bold)).foregroundStyle(Site.gradient)
            Text(label).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).frame(width: 150)
        }
    }
}

// MARK: - Highlights

struct Highlight: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let text: String
}

struct Highlights: View {
    static let items = [
        Highlight(id: 1, icon: "doc.text", title: "Unmodified source", text: "Write `import SwiftUI` and ship the same file to the App Store and to the web. SwiftUIWeb provides a module literally named SwiftUI with Apple's API surface."),
        Highlight(id: 2, icon: "ruler", title: "Measured, not guessed", text: "Every element is a fixture rendered by Apple's SwiftUI on macOS. Frames must match exactly; pixels within tolerance in three browsers and natively."),
        Highlight(id: 3, icon: "paintbrush.fill", title: "Canvas painter", text: "Layout runs in Swift and emits a display list. Canvas2D paints it in the browser; CoreGraphics paints the very same list in an AppKit window."),
        Highlight(id: 4, icon: "accessibility", title: "Accessible by default", text: "A semantics tree mirrors the view tree into an ARIA overlay: screen readers, keyboard focus, Tab order and real text inputs for IME and autofill."),
        Highlight(id: 5, icon: "bolt.fill", title: "State that just works", text: "@State, @Binding, @Observable, ObservableObject, @FocusState, environment, preferences, animations, transitions and tasks behave like the originals."),
        Highlight(id: 6, icon: "square.grid.2x2", title: "The real controls", text: "Buttons, toggles, pickers, sliders, steppers, date and colour pickers, tables, lists, forms, gauges, menus and navigation, drawn the way macOS draws them."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(kicker: "Why", title: "Fidelity is the feature")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(Self.items) { item in
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: item.icon).font(.title2).foregroundStyle(Site.gradient)
                            Text(item.title).font(.headline)
                            Text(item.text).font(.callout).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 40)
    }
}

struct SectionHeader: View {
    let kicker: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker.uppercased()).font(.caption).fontWeight(.semibold).foregroundColor(Site.accent)
            Text(title).font(.system(size: 34, weight: .bold))
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
    }
}

// MARK: - Live demos

@Observable
final class DemoModel {
    var enabled = true
    var volume = 0.65
    var quantity = 3
    var flavour = "Vanilla"
    var accent: Color = Site.accent
    var name = "Ada"
    var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var notes = "Type here. Real text input: IME, autofill and selection are the browser's."
    var selection: Int? = nil
    var order = [KeyPathComparator(\Element.symbol)]
    var todos = ["Measure the golden", "Write the fixture", "Ship it"]
    var newTodo = ""
    var revealed = false
}

struct Element: Identifiable {
    let id: Int
    let symbol: String
    let name: String
    let number: Int
}

let elements = [
    Element(id: 1, symbol: "Sw", name: "Swift", number: 2014),
    Element(id: 2, symbol: "Ui", name: "SwiftUI", number: 2019),
    Element(id: 3, symbol: "Wa", name: "WebAssembly", number: 2017),
    Element(id: 4, symbol: "Cv", name: "Canvas2D", number: 2009),
]

struct Demos: View {
    @State private var model = DemoModel()
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(kicker: "Try it", title: "Every control below is live")
            Text("Nothing here is a screenshot. These are SwiftUI views laid out by SwiftUIWeb and painted on a canvas; the state behind them is a plain @Observable model.")
                .foregroundColor(.secondary)
            Picker("Demo", selection: $tab) {
                Text("Controls").tag(0)
                Text("Data").tag(1)
                Text("Drawing").tag(2)
                Text("State").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            Card {
                switch tab {
                case 0: ControlsDemo(model: model)
                case 1: DataDemo(model: model)
                case 2: DrawingDemo(model: model)
                default: StateDemo(model: model)
                }
            }
        }
        .padding(.vertical, 40)
    }
}

struct ControlsDemo: View {
    @Bindable var model: DemoModel

    var body: some View {
        Columns(secondWidth: 360) {
            Form {
                TextField("Name", text: $model.name)
                Toggle("Notifications", isOn: $model.enabled)
                Slider(value: $model.volume, in: 0...1) { Text("Volume") }
                Stepper("Quantity: \(model.quantity)", value: $model.quantity, in: 0...12)
                Picker("Flavour", selection: $model.flavour) {
                    Text("Vanilla").tag("Vanilla")
                    Text("Chocolate").tag("Chocolate")
                    Text("Pistachio").tag("Pistachio")
                }
                DatePicker("Delivery", selection: $model.date, displayedComponents: .date)
                ColorPicker("Accent", selection: $model.accent)
            }
            .frame(maxWidth: 420)
            .disabled(!model.enabled)
        } second: {
            VStack(alignment: .leading, spacing: 14) {
                Text("Reads back").font(.headline)
                LabeledContent("Name", value: model.name.isEmpty ? "—" : model.name)
                LabeledContent("Volume", value: "\(Int(model.volume * 100)) %")
                LabeledContent("Order", value: "\(model.quantity) × \(model.flavour)")
                Gauge(value: model.volume) { Text("Volume") } currentValueLabel: { Text("\(Int(model.volume * 100))") }
                    .gaugeStyle(.accessoryLinear)
                    .tint(model.accent)
                ProgressView(value: Double(model.quantity), total: 12) { Text("Quantity") }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(model.accent)
                    .frame(height: 40)
                    .overlay(Text("Accent").foregroundColor(.white).font(.headline))
                Menu("Actions") {
                    Button("Reset volume") { model.volume = 0.5 }
                    Button("Max volume") { model.volume = 1 }
                    Divider()
                    Button("Clear name") { model.name = "" }
                }
                .frame(width: 140)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DataDemo: View {
    @Bindable var model: DemoModel

    var body: some View {
        Columns(secondWidth: 360) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Table: click a header to sort, a row to select").font(.headline)
                Table(elements.sorted(using: model.order), selection: $model.selection, sortOrder: $model.order) {
                    TableColumn("Symbol", value: \.symbol).width(min: 50, ideal: 60)
                    TableColumn("Name", value: \.name)
                    TableColumn("Since", value: \.number) { Text("\($0.number)") }.width(min: 50, ideal: 60)
                }
                .frame(height: 160)
                Text(model.selection.flatMap { id in elements.first { $0.id == id } }.map { "Selected: \($0.name)" } ?? "Nothing selected")
                    .font(.callout).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } second: {
            VStack(alignment: .leading, spacing: 14) {
                Text("List, disclosure and grid").font(.headline)
                List(elements) { element in
                    Label(element.name, systemImage: "circle.fill")
                }
                .frame(height: 120)
                DisclosureGroup("How the table is laid out", isExpanded: $model.revealed) {
                    Text("Column widths follow NSTableView's rules, measured from 46 goldens: a 117 pt automatic pitch, 8 and 7 pt margins, and grow, shrink and overflow regimes in half points.")
                        .font(.callout).foregroundColor(.secondary)
                }
                Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow { Text("Tier").bold(); Text("Checks").bold(); Text("Where").bold() }
                    GridRow { Text("A"); Text("exact frames"); Text("native tests") }
                    GridRow { Text("B"); Text("frames + pixels"); Text("three browsers") }
                    GridRow { Text("C"); Text("pixels"); Text("AppKit window") }
                }
                .font(.callout)
            }
        }
    }
}

struct DrawingDemo: View {
    @Bindable var model: DemoModel
    @Environment(\.palette) private var palette
    private let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "sun.max.fill", "moon.fill", "globe", "camera", "bell", "flag", "tag", "bookmark"]

    var body: some View {
        Columns(secondWidth: 320) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Canvas, gradients and shapes").font(.headline)
                Canvas { context, size in
                    let bars = 12
                    let gap: CGFloat = 6
                    let width = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                    for index in 0..<bars {
                        // A triangle wave (no libm on wasm) the slider shifts.
                        let t = Double(index) / Double(bars - 1) * 1.5 + model.volume
                        let fraction = t - Double(Int(t))
                        let wave = abs(1 - 2 * fraction)
                        let height = size.height * (0.25 + 0.75 * wave)
                        let rect = CGRect(x: CGFloat(index) * (width + gap), y: size.height - height, width: width, height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .linearGradient(
                            Gradient(colors: [Site.accent, Site.accentEnd]), startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: 0, y: 0)))
                    }
                    context.stroke(Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height - 0.5))
                        path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                    }, with: .color(palette.line), lineWidth: 1)
                }
                .frame(height: 140)
                Slider(value: $model.volume, in: 0...1) { Text("Phase") }
                HStack(spacing: 12) {
                    Circle().fill(RadialGradient(colors: [.white, Site.accent], center: .center, startRadius: 2, endRadius: 28)).frame(width: 56, height: 56)
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AngularGradient(colors: [Site.accent, Site.accentEnd, Site.accent], center: .center)).frame(width: 56, height: 56)
                    Capsule().strokeBorder(Site.gradient, lineWidth: 6).frame(width: 90, height: 56)
                    Circle().trim(from: 0, to: model.volume).stroke(Site.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 56, height: 56)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } second: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Symbols, text and time").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36))], spacing: 10) {
                    ForEach(symbols, id: \.self) { name in
                        Image(systemName: name).font(.title2).foregroundStyle(Site.gradient)
                    }
                }
                Text("Large Title").font(.largeTitle) + Text(" title ").font(.title) + Text("body ").font(.body) + Text("caption").font(.caption)
                Text("Wrapped paragraphs break where CoreText breaks them, truncate with the same ellipsis and align on the same baselines.")
                    .font(.callout).foregroundColor(.secondary).lineLimit(3)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSinceReferenceDate) % 60
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text("TimelineView ticking: \(seconds) s")
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct StateDemo: View {
    @Bindable var model: DemoModel
    @State private var pulse = false
    @Environment(\.palette) private var palette

    var body: some View {
        Columns(secondWidth: 320) {
            VStack(alignment: .leading, spacing: 12) {
                Text("An @Observable to-do list").font(.headline)
                HStack {
                    TextField("New item", text: $model.newTodo)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(model.newTodo.isEmpty)
                }
                if model.todos.isEmpty {
                    ContentUnavailableView("All done", systemImage: "checkmark.circle.fill", description: Text("Add an item above."))
                        .frame(height: 140)
                } else {
                    ForEach(Array(model.todos.enumerated()), id: \.offset) { index, todo in
                        HStack {
                            Image(systemName: "circle").foregroundColor(.secondary)
                            Text(todo)
                            Spacer()
                            Button { model.todos.remove(at: index) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } second: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Animation and text editing").font(.headline)
                HStack(spacing: 16) {
                    Button("Pulse") { withAnimation(.spring(duration: 0.5)) { pulse.toggle() } }
                    Circle()
                        .fill(Site.gradient)
                        .frame(width: 32, height: 32)
                        .scaleEffect(pulse ? 1.6 : 1)
                        .opacity(pulse ? 0.7 : 1)
                }
                TextEditor(text: $model.notes)
                    .font(.callout)
                    .frame(height: 80)
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.line, lineWidth: 1))
                Text("\(model.notes.count) characters").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func add() {
        let text = String(model.newTodo.drop(while: { $0 == " " }).reversed().drop(while: { $0 == " " }).reversed())
        guard !text.isEmpty else { return }
        model.todos.append(text)
        model.newTodo = ""
    }
}

// MARK: - iOS look

/// The same settings screen twice: under the macOS platform profile and, in a phone frame,
/// under the iOS one (`platformProfile` is SwiftUIWeb's environment value; its iOS metrics are
/// measured on Mac Catalyst goldens, decision 0013).
struct IOSDemo: View {
    @State private var model = SettingsModel()
    @Environment(\.isCompact) private var compact

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(kicker: "iOS too", title: "One source, each platform's look")
            Text("A SwiftUI app looks like the platform it runs on. SwiftUIWeb carries a platform profile: text styles, control geometry and colours measured from Apple's own rendering. The settings screen below is one view, shown with the macOS profile and with the iOS profile. Both are live.")
                .foregroundColor(.secondary)
            Columns(secondWidth: 340) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("macOS profile").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                        SettingsScreen(model: model)
                    }
                }
            } second: {
                PhoneFrame {
                    SettingsScreen(model: model)
                        .padding(.top, 44)   // below the island
                        #if canImport(SwiftUIWebCore)
                        .environment(\.platformProfile, .iOS)
                        #endif
                }
            }
        }
        .padding(.vertical, 40)
    }
}

@Observable
final class SettingsModel {
    var wifi = true
    var bluetooth = false
    var volume = 0.6
    var quantity = 3
    var size = 2
    var name = ""
}

/// A settings screen written once; the platform profile decides how its controls look.
struct SettingsScreen: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.largeTitle).bold()
            Toggle("Wi-Fi", isOn: $model.wifi)
            Toggle("Bluetooth", isOn: $model.bluetooth)
            VStack(alignment: .leading, spacing: 4) {
                Text("Volume").font(.subheadline)
                Slider(value: $model.volume)
            }
            Stepper("Quantity: \(model.quantity)", value: $model.quantity, in: 0...12)
            Picker("Size", selection: $model.size) {
                Text("Small").tag(1); Text("Medium").tag(2); Text("Large").tag(3)
            }
            .pickerStyle(.segmented)
            TextField("Name", text: $model.name).textFieldStyle(.roundedBorder)
            Button("Save") {}.buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// A phone-shaped bezel around a white screen.
struct PhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        content
            .frame(width: 320, height: 520, alignment: .top)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 46, style: .continuous).fill(Site.ink))
            .overlay(alignment: .top) {
                Capsule().fill(Color.black).frame(width: 100, height: 26).padding(.top, 20)
            }
    }
}

// MARK: - How it works

struct HowItWorks: View {
    static let steps = [
        ("1", "cursorarrow.click", "Write SwiftUI", "The same source you ship on macOS: @main, WindowGroup, views, modifiers, state."),
        ("2", "cpu", "Build for wasm", "`scripts/build-wasm.sh` compiles your package with the Swift wasm SDK and bundles it with the canvas host."),
        ("3", "safari", "Open index.html", "The runtime lays out in Swift, emits a display list, and Canvas2D paints it. Same list, CoreGraphics on macOS."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(kicker: "How", title: "Three steps, no compiler tricks")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                ForEach(Self.steps, id: \.0) { step in
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(step.0).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                    .frame(width: 26, height: 26).background(Circle().fill(Site.gradient))
                                Image(systemName: step.1).foregroundColor(.secondary)
                            }
                            Text(step.2).font(.headline)
                            Text(step.3).font(.callout).foregroundColor(.secondary)
                        }
                    }
                }
            }
            CodeSample()
        }
        .padding(.vertical, 40)
    }
}

struct CodeSample: View {
    static let code = """
    import SwiftUI

    @main struct CounterApp: App {
        var body: some Scene { WindowGroup { ContentView() } }
    }

    struct ContentView: View {
        @State private var count = 0
        var body: some View {
            VStack(spacing: 12) {
                Text("Count: \\(count)")
                Button("Increment") { count += 1 }
            }
            .padding()
        }
    }
    """

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
                Spacer()
                Text("CounterApp.swift").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(12)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Self.code)
                    .font(.system(size: 13).monospaced())
                    .foregroundColor(palette.codeText)
                    .fixedSize()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.code))
    }
}

// MARK: - Support matrix

struct SupportMatrix: View {
    @State private var filter: SupportStatus? = nil
    @State private var expanded: Set<String> = ["Views"]
    @Environment(\.isCompact) private var compact

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(kicker: "Status", title: "What works today")
            Text("Generated from the repository's support matrix on \(SupportData.generated). Anything not listed is not implemented; the missing rows are the next phase's plan.")
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
                StatusPill(status: nil, count: SupportData.total, selected: filter == nil) { filter = nil }
                ForEach(SupportStatus.allCases, id: \.self) { status in
                    StatusPill(status: status, count: SupportData.counts[status, default: 0], selected: filter == status) { filter = status }
                }
            }
            ForEach(SupportData.sections) { section in
                let rows = section.entries.filter { filter == nil || $0.status == filter }
                if !rows.isEmpty {
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(section.id) }, set: { open in
                        if open { expanded.insert(section.id) } else { expanded.remove(section.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { entry in
                                SupportRow(entry: entry)
                                Divider()
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Text(section.title).font(.headline)
                            Text("\(rows.count)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], alignment: .leading, spacing: 8) {
                ForEach(SupportStatus.allCases, id: \.self) { status in
                    HStack(spacing: 6) {
                        StatusDot(status: status)
                        Text(status.meaning).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 40)
    }
}

struct StatusPill: View {
    let status: SupportStatus?
    let count: Int
    let selected: Bool
    let action: @MainActor @Sendable () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let status { StatusDot(status: status) }
                Text(status?.title ?? "All").fixedSize()
                Text("\(count)").foregroundColor(selected ? palette.pillSelectedText.opacity(0.6) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? palette.pillSelected : palette.paper))
            .foregroundColor(selected ? palette.pillSelectedText : .primary)
            .overlay(Capsule().stroke(palette.line, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct StatusDot: View {
    let status: SupportStatus
    var color: Color {
        switch status {
        case .full: return Color(red: 0.16, green: 0.70, blue: 0.30)
        case .partial: return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .approximate: return Color(red: 0.95, green: 0.65, blue: 0.10)
        case .stub: return Color(red: 0.60, green: 0.60, blue: 0.65)
        case .missing: return Color(red: 0.90, green: 0.25, blue: 0.25)
        }
    }
    var body: some View { Circle().fill(color).frame(width: 9, height: 9) }
}

struct SupportRow: View {
    let entry: SupportEntry
    @Environment(\.isCompact) private var compact
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusDot(status: entry.status).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.api).font(.system(size: 13, weight: .semibold))
                if !entry.notes.isEmpty {
                    Text(entry.notes).font(.callout).foregroundColor(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                Text(entry.status.title).font(.caption).foregroundColor(.secondary).frame(width: 84, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Footer

struct Footer: View {
    var body: some View {
        VStack(spacing: 16) {
            Divider()
            HStack(spacing: 8) {
                Wordmark(size: 18)
                Text("SwiftUIWeb").font(.headline)
                Spacer()
                ShareLink(item: Site.repository) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], alignment: .leading, spacing: 8) {
                Link("GitHub", destination: Site.repository)
                Link("Architecture", destination: Site.architecture)
                Link("Element workflow", destination: Site.workflow)
                Link("Apache-2.0", destination: Site.license)
            }
            Text("Open source, Apache-2.0. Borrows ideas with attribution from Tokamak, ElementaryUI and OpenSwiftUI. This page is Examples/Landing in the repository: a SwiftUI view, nothing else.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 32)
    }
}
