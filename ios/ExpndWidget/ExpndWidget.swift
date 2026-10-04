import WidgetKit
import SwiftUI

// Must match WidgetBridge.appGroupId and the App Group added to both targets.
private let appGroupId = "group.com.expnd.app"

// The `homeWidget` query item is not decoration: home_widget's iOS plugin drops
// any incoming URL that lacks it (isWidgetUrl in SwiftHomeWidgetPlugin), so
// without it the tap launches the app and the deep link is silently swallowed —
// no add sheet. Android reads the intent's data directly and doesn't care.
// The Dart side routes on the host, so the query item is inert there.
private let quickAddURL = URL(string: "expnd://add?homeWidget=1")!

// MARK: - Palette (mirrors ExpndColors in lib/theme/expnd_theme.dart)

private func hex(_ v: UInt32) -> Color {
    Color(
        red: Double((v >> 16) & 0xFF) / 255,
        green: Double((v >> 8) & 0xFF) / 255,
        blue: Double(v & 0xFF) / 255
    )
}

/// Adaptive palette resolved from the widget's color scheme, so the widget
/// tracks light/dark exactly like the app. Keep every value in sync with
/// ExpndColors; brand colours (gold/goldDark/ink) are fixed.
struct Palette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }

    // Adaptive surfaces & text (ExpndColors.surface / card / border / ...).
    var surface: Color { dark ? hex(0x1C222A) : hex(0xFFFFFF) }
    var card: Color    { dark ? hex(0x232B35) : hex(0xF0F2F5) }
    var border: Color  { dark ? hex(0x35404C) : hex(0xDCE1E7) }
    var text: Color    { dark ? .white        : hex(0x0D0D0D) }
    var muted: Color   { dark ? hex(0xACB7C4) : hex(0x576474) }

    // Gold as a FOREGROUND mark: bright on dark, darker amber on light so it
    // stays legible on a white card (ExpndColors.accent).
    var accent: Color   { dark ? hex(0xFFEB34) : hex(0x9A6F00) }
    var positive: Color { dark ? hex(0x06C270) : hex(0x087A4D) }
    var negative: Color { dark ? hex(0xFF806C) : hex(0xBB3526) }

    // Fixed brand tokens (ExpndColors static members).
    let gold     = hex(0xFFEB34)
    let goldDark = hex(0xCDB900)
    let ink      = hex(0x0D0D0D)
}

// MARK: - Type & shape (mirror ExpndSans and ExpndRadius in the app)

/// The app's bundled Noto Sans; only Regular and Bold ship, like the app.
func expndFont(_ size: CGFloat, bold: Bool = false) -> Font {
    .custom(bold ? "NotoSans-Bold" : "NotoSans-Regular", size: size)
}

enum ExpndRadius {
    static let button: CGFloat = 8
    static let tag: CGFloat = 4
}

/// NeoPOP block: a face sitting on a darker depth block offset down-right,
/// the same construction as NeoPopButton in lib/widgets/neopop.dart.
struct NeoPopFace<Content: View>: View {
    let face: Color
    let depth: Color
    var offset: CGFloat = 2
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: ExpndRadius.button).fill(face))
            .background(
                RoundedRectangle(cornerRadius: ExpndRadius.button)
                    .fill(depth)
                    .offset(x: offset, y: offset)
            )
            .padding(.trailing, offset)
            .padding(.bottom, offset)
    }
}

// MARK: - Model

enum Sign { case positive, negative, neutral }

struct Recent: Identifiable {
    let id = UUID()
    let note: String
    let amount: String
    let sign: Sign
}

struct ExpndEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
    /// Formatted remainder of the monthly budget (absolute value), or "" when
    /// no budget is set. Net worth is intentionally not shown on the widget.
    let leftToSpend: String
    let overBudget: Bool
    let monthLabel: String
    let monthSpent: String
    let budgetText: String
    let budgetRatio: Int // 0...100, or -1 when no budget is set
    let recents: [Recent]

    static let sample = ExpndEntry(
        date: Date(),
        hasData: true,
        leftToSpend: "$1,760.00",
        overBudget: false,
        monthLabel: "JULY",
        monthSpent: "$1,240.00",
        budgetText: "of $3,000.00",
        budgetRatio: 41,
        recents: [
            Recent(note: "Groceries", amount: "-$54.20", sign: .negative),
            Recent(note: "Salary", amount: "+$4,000.00", sign: .positive),
            Recent(note: "Transfer to Savings", amount: "$500.00", sign: .neutral),
        ]
    )
}

// MARK: - Timeline provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ExpndEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ExpndEntry) -> Void) {
        completion(context.isPreview ? .sample : readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpndEntry>) -> Void) {
        // The app refreshes the widget on every data change, so we don't need a
        // reload cadence — hold the current snapshot until the next push.
        completion(Timeline(entries: [readEntry()], policy: .never))
    }

    private func readEntry() -> ExpndEntry {
        let d = UserDefaults(suiteName: appGroupId)
        func str(_ key: String, _ fallback: String = "") -> String {
            d?.string(forKey: key) ?? fallback
        }
        let count = min(d?.integer(forKey: "tx_count") ?? 0, 3)
        var recents: [Recent] = []
        for i in 0..<count {
            let amount = str("tx\(i)_amount")
            let sign: Sign
            if amount.hasPrefix("+") {
                sign = .positive
            } else if amount.hasPrefix("-") || amount.hasPrefix("\u{2212}") {
                sign = .negative
            } else {
                sign = .neutral
            }
            recents.append(Recent(note: str("tx\(i)_note"), amount: amount, sign: sign))
        }

        return ExpndEntry(
            date: Date(),
            hasData: d?.bool(forKey: "has_data") ?? false,
            leftToSpend: str("left_to_spend"),
            overBudget: d?.bool(forKey: "over_budget") ?? false,
            monthLabel: str("month_label"),
            monthSpent: str("month_spent", "—"),
            budgetText: str("budget_text"),
            budgetRatio: d?.object(forKey: "budget_ratio") == nil ? -1 : (d?.integer(forKey: "budget_ratio") ?? -1),
            recents: recents
        )
    }
}

// MARK: - Views

/// Section label in the app's sentence-case style ("Monthly net", "Spent").
struct WidgetLabel: View {
    let text: String
    let p: Palette
    var body: some View {
        Text(text)
            .font(expndFont(11, bold: true))
            .foregroundColor(p.muted)
            .lineLimit(1)
    }
}

/// A figure with tabular digits so amounts don't jitter between refreshes.
struct Figure: View {
    let text: String
    let size: CGFloat
    let color: Color
    var body: some View {
        Text(text)
            .font(expndFont(size, bold: true).monospacedDigit())
            .tracking(size >= 20 ? -0.6 : -0.2)
            .foregroundColor(color)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

private func monthTitle(_ entry: ExpndEntry) -> String {
    entry.monthLabel.isEmpty ? "This month" : entry.monthLabel.capitalized
}

/// Budget burn bar shared by both sizes; mirrors the Home "Monthly budget" card.
struct BudgetBar: View {
    let ratio: Int
    let p: Palette
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.border)
                Capsule()
                    .fill(ratio >= 100 ? p.negative : p.positive)
                    .frame(width: max(6, geo.size.width * CGFloat(min(ratio, 100)) / 100))
                    .widgetAccentable()
            }
        }
        .frame(height: 6)
    }
}

/// "9% used" — the same pill wording the app's Home budget card uses.
struct UsedPill: View {
    let ratio: Int
    let p: Palette
    var body: some View {
        let color = ratio >= 100 ? p.negative : p.positive
        Text("\(ratio)% used")
            .font(expndFont(9, bold: true).monospacedDigit())
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.14)))
            .lineLimit(1)
            .fixedSize()
    }
}

/// Gold NeoPOP "+" action, the same face/depth construction as the app's
/// primary buttons.
struct QuickAddButton: View {
    let p: Palette
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        Group {
            if mode == .fullColor {
                NeoPopFace(face: p.gold, depth: p.goldDark) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(p.ink)
                }
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Circle().fill(.white.opacity(0.18)))
                    .widgetAccentable()
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("Add transaction")
    }
}

/// Direction glyph in a tinted tile, echoing the app's transaction icons.
struct DirectionTile: View {
    let sign: Sign
    let p: Palette
    var body: some View {
        let tint: Color = sign == .positive ? p.positive : sign == .negative ? p.negative : p.muted
        let symbol = sign == .positive ? "arrow.down.left" : sign == .negative ? "arrow.up.right" : "arrow.left.arrow.right"
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(tint)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.14)))
    }
}

private func amountColor(_ sign: Sign, _ p: Palette) -> Color {
    switch sign {
    case .positive: return p.positive
    case .negative: return p.negative
    case .neutral: return p.text
    }
}

extension ExpndEntry {
    var hasBudget: Bool { !leftToSpend.isEmpty }
}

/// The widget's lead figure: what's left of this month's budget, or the
/// month's spending when no budget is set.
struct Headline: View {
    let entry: ExpndEntry
    let p: Palette
    let size: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.hasBudget {
                WidgetLabel(text: entry.overBudget ? "Over budget" : "Left to spend", p: p)
                Figure(
                    text: entry.leftToSpend,
                    size: size,
                    color: entry.overBudget ? p.negative : p.text
                )
            } else {
                WidgetLabel(text: "Spent in \(monthTitle(entry))", p: p)
                Figure(text: entry.monthSpent, size: size, color: p.text)
            }
        }
    }
}

/// Secondary block under the headline: spend against budget with the same
/// pill and bar as the app's Home budget card.
struct MonthSummary: View {
    let entry: ExpndEntry
    let p: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.hasBudget {
                WidgetLabel(text: "Spent in \(monthTitle(entry))", p: p)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Figure(text: entry.monthSpent, size: 15, color: p.text)
                    Spacer(minLength: 0)
                    UsedPill(ratio: max(entry.budgetRatio, 0), p: p)
                }
                .padding(.top, 2)
                BudgetBar(ratio: max(entry.budgetRatio, 0), p: p)
                    .padding(.top, 6)
            } else {
                Text("Set a monthly budget in Plan to see what's left.")
                    .font(expndFont(10))
                    .foregroundColor(p.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SmallWidgetView: View {
    let entry: ExpndEntry
    let p: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Headline(entry: entry, p: p, size: 24)
            Spacer(minLength: 8)
            MonthSummary(entry: entry, p: p)
        }
        .privacySensitive()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(quickAddURL)
    }
}

struct MediumWidgetView: View {
    let entry: ExpndEntry
    let p: Palette
    private var rows: [Recent] { Array(entry.recents.prefix(3)) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: budget headroom at a glance.
            VStack(alignment: .leading, spacing: 0) {
                Headline(entry: entry, p: p, size: 22)
                Spacer(minLength: 8)
                MonthSummary(entry: entry, p: p)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle().fill(p.border).frame(width: 1)

            // Right: recent activity and the add action.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    WidgetLabel(text: "Recent", p: p)
                    Spacer(minLength: 4)
                    Link(destination: quickAddURL) { QuickAddButton(p: p) }
                }
                Spacer(minLength: 4)
                if rows.isEmpty {
                    Text("No transactions yet")
                        .font(expndFont(11))
                        .foregroundColor(p.muted)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(rows) { tx in
                            HStack(spacing: 7) {
                                DirectionTile(sign: tx.sign, p: p)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(tx.note)
                                        .font(expndFont(11, bold: true))
                                        .foregroundColor(p.text)
                                        .lineLimit(1)
                                    Figure(text: tx.amount, size: 11, color: amountColor(tx.sign, p))
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .privacySensitive()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Lock Screen / StandBy accessories
//
// Accessories are rendered by the system in a single tint, so they carry no
// palette — shape and text have to do all the work. Each one answers a
// different glance: how much budget is left, what the month looks like, and a
// one-line summary for the inline slot above the Lock Screen clock.

/// Budget burn as a ring. Falls back to the month's spend when no budget is
/// set, because an empty ring reads as "zero spent", which would be a lie.
struct AccessoryCircularView: View {
    let entry: ExpndEntry
    var body: some View {
        if entry.budgetRatio >= 0 {
            Gauge(value: Double(min(entry.budgetRatio, 100)), in: 0...100) {
                // The app's currency is picked at setup and could be any of
                // them, so the label is the user's own symbol, not a fixed
                // SF Symbol for one currency.
                Text(CaptureQueue.currencySymbol)
            } currentValueLabel: {
                Text("\(entry.budgetRatio)%")
                    .font(.system(size: 13, weight: .heavy))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("SPENT")
                        .font(.system(size: 8, weight: .black))
                    Text(entry.monthSpent)
                        .font(.system(size: 11, weight: .heavy))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct AccessoryRectangularView: View {
    let entry: ExpndEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.hasBudget
                 ? "\(entry.leftToSpend) \(entry.overBudget ? "over" : "left")"
                 : "\(entry.monthSpent) spent")
                .font(.system(size: 13, weight: .heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("\(entry.monthLabel) \(entry.monthSpent)")
                .font(.system(size: 12, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if entry.budgetRatio >= 0 {
                Gauge(value: Double(min(entry.budgetRatio, 100)), in: 0...100) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExpndWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    let entry: ExpndEntry

    var body: some View {
        let p = Palette(scheme: colorScheme)
        switch family {
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            // The inline slot is one tinted line with no layout control.
            Text("\(entry.monthLabel) \(entry.monthSpent)")
                .containerBackground(for: .widget) { Color.clear }
        default:
            Group {
                if family == .systemSmall {
                    SmallWidgetView(entry: entry, p: p)
                } else {
                    MediumWidgetView(entry: entry, p: p)
                }
            }
            // iOS 17+ already applies the system widget content margins.
            .containerBackground(for: .widget) { p.surface }
        }
    }
}

// MARK: - Widget

struct ExpndWidget: Widget {
    let kind = "ExpndWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ExpndWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("EXPND")
        .description("What's left to spend this month, and recent transactions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
