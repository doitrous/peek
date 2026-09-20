import AppKit
import SwiftUI
import Charts
import PeekCore

final class DashboardWindowController: NSWindowController {
    private let stats: StatsStore
    private let pins: PinStore
    private let settings: SettingsStore
    private let model = DashboardModel()

    var onTogglePin: ((String) -> Void)? {
        get { model.onTogglePin } set { model.onTogglePin = newValue }
    }

    init(stats: StatsStore, pins: PinStore, settings: SettingsStore) {
        self.stats = stats
        self.pins = pins
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Peek — " + L("Switching Insights")
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: DashboardView(model: model))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func refresh() {
        model.stickyEnabled = settings.stickyApps
        model.update(with: stats.events, pinned: pins.pinned)
    }
}

// MARK: - Model

struct DayCount: Identifiable { let id = UUID(); let day: Date; let count: Int }
struct AppCount: Identifiable { let id = UUID(); let app: String; let count: Int }
struct HourCount: Identifiable { let id = UUID(); let hour: Int; let count: Int }
struct TransitionCount: Identifiable { let id = UUID(); let label: String; let count: Int }
struct AppAffinity: Identifiable { let id = UUID(); let app: String; let score: Double; let pinned: Bool }

final class DashboardModel: ObservableObject {
    @Published var total = 0
    @Published var activeDays = 0
    @Published var busiestHour: Int?
    @Published var topApp: String?
    @Published var perDay: [DayCount] = []
    @Published var topApps: [AppCount] = []
    @Published var hourly: [HourCount] = []
    @Published var transitions: [TransitionCount] = []
    @Published var affinity: [AppAffinity] = []
    @Published var stickyEnabled = false
    var onTogglePin: ((String) -> Void)?

    func update(with events: [SwitchEvent], pinned: [String]) {
        let agg = StatsAggregator(events: events)
        total = agg.totalSwitches
        perDay = agg.switchesPerDay().map { DayCount(day: $0.day, count: $0.count) }
        activeDays = perDay.count
        topApps = agg.topApps().map { AppCount(app: $0.app, count: $0.count) }
        topApp = topApps.first?.app
        let h = agg.hourlyHistogram()
        hourly = h.enumerated().map { HourCount(hour: $0.offset, count: $0.element) }
        busiestHour = (h.max()).flatMap { m in m > 0 ? h.firstIndex(of: m) : nil }
        transitions = agg.topTransitions().map { TransitionCount(label: "\($0.from) → \($0.to)", count: $0.count) }

        // Pinned apps first, then by affinity — the ranking that drives the switcher.
        let scores = WindowRanker.affinity(events: events)
        let pinSet = Set(pinned)
        let apps = Set(events.map(\.toApp)).union(pinned)
        affinity = apps.map { AppAffinity(app: $0, score: scores[$0] ?? 0, pinned: pinSet.contains($0)) }
            .sorted {
                $0.pinned != $1.pinned ? ($0.pinned && !$1.pinned)
                : ($0.score != $1.score ? $0.score > $1.score : $0.app < $1.app)
            }
    }
}

// MARK: - View

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @State private var selectedDay: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(L("Switching Insights")).font(.largeTitle.bold())
                kpiRow
                if model.total == 0 {
                    emptyState
                } else {
                    affinityCard
                    perDayCard
                    HStack(alignment: .top, spacing: 18) {
                        topAppsCard
                        hourlyCard
                    }
                    transitionsCard
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.layoutDirection, Localize.isRTL ? .rightToLeft : .leftToRight)
    }

    // KPIs

    private var kpiRow: some View {
        HStack(spacing: 14) {
            kpi(L("Total switches"), "\(model.total)", "arrow.left.arrow.right")
            kpi(L("Active days"), "\(model.activeDays)", "calendar")
            kpi(L("Busiest hour"), model.busiestHour.map { "\($0):00" } ?? "—", "clock")
            kpi(L("Most used"), model.topApp ?? "—", "star.fill")
        }
    }

    private func kpi(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // Ranking + pins — the switcher's order, made visible and editable.

    private var affinityCard: some View {
        card(L("Your apps — switcher order")) {
            let maxScore = max(model.affinity.map(\.score).max() ?? 1, 0.0001)
            if !model.stickyEnabled {
                Label(L("Sticky apps (learning) is off — pins still float to the top. Turn it on from the menu-bar icon to auto-favor your most-used apps."),
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).padding(.bottom, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                ForEach(model.affinity.prefix(12)) { a in
                    HStack(spacing: 10) {
                        Button {
                            model.onTogglePin?(a.app)
                        } label: {
                            Image(systemName: a.pinned ? "pin.fill" : "pin")
                                .rotationEffect(.degrees(45))
                                .foregroundStyle(a.pinned ? Color.peekAccent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(a.pinned ? String(format: L("Unpin %@"), a.app)
                                       : String(format: L("Pin %@ to the top"), a.app))

                        Text(a.app).font(.system(size: 13)).frame(width: 150, alignment: .leading).lineLimit(1)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary.opacity(0.5))
                                Capsule().fill(a.pinned ? Color.peekAccent : Color.peekAccent.opacity(0.55))
                                    .frame(width: max(4, geo.size.width * (a.score / maxScore)))
                            }
                        }
                        .frame(height: 8)

                        Text(String(format: "%.1f", a.score))
                            .font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    // Charts

    private var perDayCard: some View {
        card(L("Switches per day")) {
            Chart(model.perDay) { d in
                AreaMark(x: .value("Day", d.day, unit: .day), y: .value("Switches", d.count))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.linearGradient(colors: [.peekAccent.opacity(0.5), .peekAccent.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", d.day, unit: .day), y: .value("Switches", d.count))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.peekAccent)
                if let selectedDay, let sel = model.perDay.first(where: {
                    Calendar.current.isDate($0.day, inSameDayAs: selectedDay)
                }) {
                    RuleMark(x: .value("Day", sel.day, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            calloutView(String(format: L("%d switches"), sel.count), sel.day.formatted(.dateTime.month().day()))
                        }
                }
            }
            .chartXSelection(value: $selectedDay)
            .frame(height: 220)
        }
    }

    private var topAppsCard: some View {
        card(L("Top apps")) {
            Chart(model.topApps) { a in
                BarMark(x: .value("Switches", a.count), y: .value("App", a.app))
                    .foregroundStyle(Color.peekAccent.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(a.count)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: max(160, CGFloat(model.topApps.count) * 30))
        }
    }

    private var hourlyCard: some View {
        card(L("By hour of day")) {
            Chart(model.hourly) { h in
                BarMark(x: .value("Hour", h.hour), y: .value("Switches", h.count))
                    .foregroundStyle(Color.peekAccent.gradient)
            }
            .chartXScale(domain: 0...23)
            .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) }
            .frame(height: max(160, CGFloat(model.topApps.count) * 30))
        }
    }

    private var transitionsCard: some View {
        card(L("Most common transitions")) {
            if model.transitions.isEmpty {
                Text(L("No repeated transitions yet.")).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                Chart(model.transitions) { t in
                    BarMark(x: .value("Count", t.count), y: .value("Transition", t.label))
                        .foregroundStyle(.teal.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(t.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .frame(height: max(140, CGFloat(model.transitions.count) * 30))
            }
        }
    }

    // Helpers

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func calloutView(_ big: String, _ small: String) -> some View {
        VStack(spacing: 2) {
            Text(big).font(.caption.bold())
            Text(small).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(L("No switches recorded yet")).font(.title3.bold())
            Text(L("Press ⌘-Tab to switch windows, then reopen this window."))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}
