import AppIntents
import SwiftUI
import WidgetKit

// A second widget kind, separate from the glance widget on purpose: capture
// and reading are different jobs, and a medium widget has no room to do both
// without evicting the recent transactions. Users add whichever they want.

// See ExpndWidget.swift for why the `homeWidget` query item has to be here.
private let reviewURL = URL(string: "expnd://captures?homeWidget=1")!

// MARK: - Model

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let presets: [Double]
    let lastAmount: Double
    let lastNote: String
    let pending: Int
    let symbol: String

    var canRepeat: Bool { lastAmount > 0 }

    static let sample = QuickLogEntry(
        date: Date(),
        presets: [100, 500, 1000],
        lastAmount: 120,
        lastNote: "Coffee",
        pending: 2,
        symbol: "$"
    )
}

struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(context.isPreview ? .sample : readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        // Every tap reloads the timeline itself, and the app pushes on each
        // data change, so there's nothing to poll for.
        completion(Timeline(entries: [readEntry()], policy: .never))
    }

    private func readEntry() -> QuickLogEntry {
        QuickLogEntry(
            date: Date(),
            presets: CaptureQueue.presets,
            lastAmount: CaptureQueue.lastExpenseAmount,
            lastNote: CaptureQueue.lastExpenseNote,
            pending: CaptureQueue.pendingCount,
            symbol: CaptureQueue.currencySymbol
        )
    }
}

// MARK: - Buttons

/// A gold NeoPOP block that queues a preset amount, built like the app's
/// primary action buttons.
struct PresetButton: View {
    let amount: Double
    let p: Palette
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        Button(intent: LogAmountIntent(amount: amount)) {
            let label = Text(CaptureQueue.presetLabel(amount))
                .font(expndFont(15, bold: true).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 4)
            if mode == .fullColor {
                NeoPopFace(face: p.gold, depth: p.goldDark) {
                    label.foregroundColor(p.ink)
                }
            } else {
                // Tinted / clear Home Screens flatten colour, so a gold block
                // would turn into a white slab; use a translucent tile instead.
                label
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: ExpndRadius.button)
                            .fill(.white.opacity(0.18))
                    )
                    .widgetAccentable()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(CaptureQueue.presetLabel(amount))")
    }
}

/// Repeat-last is bordered rather than filled: it's the secondary action, and
/// keeping only the presets gold stops the widget reading as four equal blocks.
struct RepeatButton: View {
    let entry: QuickLogEntry
    let p: Palette
    var body: some View {
        Button(intent: RepeatLastExpenseIntent()) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                Text(CaptureQueue.presetLabel(entry.lastAmount))
                    .font(expndFont(13, bold: true).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundColor(p.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ExpndRadius.button).fill(p.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExpndRadius.button)
                    .strokeBorder(p.border, lineWidth: 1)
            )
            // Match the presets' depth inset so all cells line up.
            .padding(.trailing, 2)
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
    }
}

/// How many captures are waiting to be filed. Tapping opens the app's review
/// inbox — the count is only useful if acting on it is one tap away.
struct PendingBadge: View {
    let count: Int
    let p: Palette
    var body: some View {
        Link(destination: reviewURL) {
            Text("\(count) to file")
                .font(expndFont(10, bold: true))
                .foregroundColor(p.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: ExpndRadius.tag)
                        .fill(p.gold.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ExpndRadius.tag)
                        .strokeBorder(p.accent.opacity(0.45), lineWidth: 1)
                )
        }
    }
}

struct QuickLogHeader: View {
    let entry: QuickLogEntry
    let p: Palette
    var body: some View {
        HStack(spacing: 6) {
            WidgetLabel(text: "Quick log", p: p)
            Spacer(minLength: 4)
            if entry.pending > 0 {
                PendingBadge(count: entry.pending, p: p)
            }
        }
    }
}

// MARK: - Views

/// Nothing to show until the app has synced its presets at least once.
struct QuickLogEmpty: View {
    let p: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetLabel(text: "Quick log", p: p)
            Text("Open EXPND to set up quick amounts.")
                .font(expndFont(12))
                .foregroundColor(p.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct QuickLogSmallView: View {
    let entry: QuickLogEntry
    let p: Palette
    // Two-up grid: three presets plus repeat fills it exactly. Without a
    // repeatable expense the third preset takes the fourth cell instead.
    private var cells: [Double] { Array(entry.presets.prefix(entry.canRepeat ? 3 : 4)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickLogHeader(entry: entry, p: p)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(cells, id: \.self) { PresetButton(amount: $0, p: p) }
                if entry.canRepeat {
                    RepeatButton(entry: entry, p: p)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct QuickLogMediumView: View {
    let entry: QuickLogEntry
    let p: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickLogHeader(entry: entry, p: p)
            HStack(spacing: 6) {
                ForEach(entry.presets.prefix(3), id: \.self) { PresetButton(amount: $0, p: p) }
                if entry.canRepeat {
                    RepeatButton(entry: entry, p: p)
                }
            }
            .frame(maxHeight: .infinity)
            if entry.canRepeat && !entry.lastNote.isEmpty {
                Text("Repeat: \(entry.lastNote)")
                    .font(expndFont(10))
                    .foregroundColor(p.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Lock Screen / StandBy: one circular button that repeats the last expense.
/// A circular accessory has room for exactly one action, and repeat-last is the
/// only capture that needs no amount chosen.
struct QuickLogCircularView: View {
    let entry: QuickLogEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.canRepeat {
                Button(intent: RepeatLastExpenseIntent()) {
                    VStack(spacing: 0) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .black))
                        Text(CaptureQueue.presetLabel(entry.lastAmount))
                            .font(.system(size: 9, weight: .heavy))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .black))
            }
        }
    }
}

struct QuickLogEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    let entry: QuickLogEntry

    var body: some View {
        let p = Palette(scheme: colorScheme)
        switch family {
        case .accessoryCircular:
            QuickLogCircularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        default:
            Group {
                if entry.presets.isEmpty {
                    QuickLogEmpty(p: p)
                } else if family == .systemSmall {
                    QuickLogSmallView(entry: entry, p: p)
                } else {
                    QuickLogMediumView(entry: entry, p: p)
                }
            }
            // iOS 17+ already applies the system widget content margins.
            .containerBackground(for: .widget) { p.surface }
        }
    }
}

struct QuickLogWidget: Widget {
    let kind = "ExpndQuickLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickLogProvider()) { entry in
            QuickLogEntryView(entry: entry)
        }
        .configurationDisplayName("EXPND Quick Log")
        .description("Log an amount straight from the Home or Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
