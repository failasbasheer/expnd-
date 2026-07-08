import WidgetKit
import SwiftUI

// Must match WidgetBridge.appGroupId and the App Group added to both targets.
private let appGroupId = "group.com.expnd.app"
private let quickAddURL = URL(string: "expnd://add")!

// MARK: - Palette (mirrors ExpndColors in lib/theme/expnd_theme.dart)

private func hex(_ v: UInt32) -> Color {
    Color(
        red: Double((v >> 16) & 0xFF) / 255,
        green: Double((v >> 8) & 0xFF) / 255,
        blue: Double(v & 0xFF) / 255
    )
}

/// Adaptive palette resolved from the widget's color scheme, so the widget
/// tracks light/dark exactly like the app. Brand colours (gold/green/red/ink)
/// are fixed; surfaces and text flip with the scheme.
struct Palette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }

    // Adaptive surfaces & text (ExpndColors.surface / text / muted / border).
    var surface: Color { dark ? hex(0x121212) : hex(0xFFFFFF) }
    var text: Color    { dark ? .white        : hex(0x0D0D0D) }
    var muted: Color   { dark ? hex(0x8A8A8A)  : hex(0x666660) }
    var border: Color  { dark ? hex(0x3D3D3D)  : hex(0xD4D4CC) }

    // Gold as a FOREGROUND mark: bright on dark, darker amber on light so it
    // stays legible on a white card (ExpndColors.accent).
    var accent: Color  { dark ? hex(0xFFEB34)  : hex(0x9A6F00) }

    // Fixed brand tokens (ExpndColors static members).
    let gold  = hex(0xFFEB34)
    let ink   = hex(0x0D0D0D)
    let green = hex(0x06C270)
    let red   = hex(0xEE4D37)
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
    let netWorth: String
    let netNegative: Bool
    let monthLabel: String
    let monthSpent: String
    let budgetText: String
    let budgetRatio: Int // 0...100, or -1 when no budget is set
    let recents: [Recent]

    static let sample = ExpndEntry(
        date: Date(),
        hasData: true,
        netWorth: "$12,480.00",
        netNegative: false,
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

        let net = str("net_worth", "—")
        return ExpndEntry(
            date: Date(),
            hasData: d?.bool(forKey: "has_data") ?? false,
            netWorth: net,
            netNegative: net.hasPrefix("-") || net.hasPrefix("\u{2212}"),
            monthLabel: str("month_label"),
            monthSpent: str("month_spent", "—"),
            budgetText: str("budget_text"),
            budgetRatio: d?.object(forKey: "budget_ratio") == nil ? -1 : (d?.integer(forKey: "budget_ratio") ?? -1),
            recents: recents
        )
    }
}

// MARK: - Views

struct NetBalanceHeader: View {
    let entry: ExpndEntry
    let p: Palette
    var showTag: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("NET BALANCE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .foregroundColor(p.muted)
                if showTag && entry.hasData {
                    StatusTag(negative: entry.netNegative, p: p)
                }
            }
            Text(entry.netWorth)
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.5)
                .foregroundColor(p.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

/// The app's POSITIVE / NEGATIVE pill: ink block with gold text (neoPOP, square).
struct StatusTag: View {
    let negative: Bool
    let p: Palette
    var body: some View {
        Text(negative ? "NEGATIVE" : "POSITIVE")
            .font(.system(size: 8, weight: .black))
            .tracking(0.8)
            .foregroundColor(negative ? .white : p.gold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(negative ? p.red : p.ink)
    }
}

struct MonthLine: View {
    let entry: ExpndEntry
    let p: Palette
    var showBudgetText: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(entry.monthLabel) SPENT")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.0)
                    .foregroundColor(p.muted)
                Spacer(minLength: 4)
                Text(entry.monthSpent)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(p.text)
                if showBudgetText && !entry.budgetText.isEmpty {
                    Text(entry.budgetText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(p.muted)
                }
            }
            if entry.budgetRatio >= 0 {
                // neoPOP budget bar — green fill like the app, red when over.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(p.border)
                        Rectangle()
                            .fill(entry.budgetRatio >= 100 ? p.red : p.green)
                            .frame(width: geo.size.width * CGFloat(entry.budgetRatio) / 100)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .frame(height: 5)
            }
        }
    }
}

/// Gold neoPOP action block (near-square), ink content — mirrors the app's
/// gold quick-add button.
struct QuickAddPill: View {
    let p: Palette
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .black))
            Text("ADD")
                .font(.system(size: 11, weight: .black))
                .tracking(0.6)
        }
        .foregroundColor(p.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 3).fill(p.gold))
    }
}

private func amountColor(_ sign: Sign, _ p: Palette) -> Color {
    switch sign {
    case .positive: return p.green
    case .negative: return p.red
    case .neutral: return p.text
    }
}

struct SmallWidgetView: View {
    let entry: ExpndEntry
    let p: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NetBalanceHeader(entry: entry, p: p)
            Spacer(minLength: 0)
            MonthLine(entry: entry, p: p)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(quickAddURL)
    }
}

struct MediumWidgetView: View {
    let entry: ExpndEntry
    let p: Palette
    // Two rows keeps the medium widget airy; the app is one tap away for more.
    private var rows: [Recent] { Array(entry.recents.prefix(2)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                NetBalanceHeader(entry: entry, p: p, showTag: false)
                Spacer()
                Link(destination: quickAddURL) { QuickAddPill(p: p) }
            }
            MonthLine(entry: entry, p: p, showBudgetText: false)
            Rectangle().fill(p.border).frame(height: 1)
            if rows.isEmpty {
                Text("No transactions yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(p.muted)
            } else {
                VStack(spacing: 9) {
                    ForEach(rows) { tx in
                        HStack {
                            Text(tx.note)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(p.text)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(tx.amount)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(amountColor(tx.sign, p))
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ExpndWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    let entry: ExpndEntry

    var body: some View {
        let p = Palette(scheme: colorScheme)
        Group {
            switch family {
            case .systemSmall: SmallWidgetView(entry: entry, p: p)
            default: MediumWidgetView(entry: entry, p: p)
            }
        }
        .padding(16)
        .containerBackground(for: .widget) { p.surface }
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
        .description("Net balance, this month's spending, and recent transactions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
