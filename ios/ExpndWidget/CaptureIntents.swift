import AppIntents
import WidgetKit

/// Intents the widget's own buttons fire. They run in the extension process,
/// so all they can do is queue the capture (see CaptureQueue) and ask WidgetKit
/// to redraw — the amount reaches the ledger when the app next runs.
///
/// Siri's free-text entry point lives in the app target instead
/// (Runner/ExpndAppIntents.swift), because App Shortcut phrases are only
/// discoverable when they're declared by the app itself.

/// Logs one of the preset amounts. The amount is a parameter rather than three
/// separate intents so the presets stay data-driven — the app can change them
/// without the widget code knowing what they are.
struct LogAmountIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Amount"
    static var description = IntentDescription(
        "Records an amount in EXPND for you to categorise later."
    )

    /// Buttons inside a widget must not launch the app — the whole point is
    /// logging without leaving the Home Screen.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    init() {}

    init(amount: Double) {
        self.amount = amount
    }

    func perform() async throws -> some IntentResult {
        CaptureQueue.append(amount: amount, note: "", source: "widget")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Re-logs the most recent expense — the daily coffee, the same commute fare.
/// Reads the amount at tap time rather than capturing it in the button, so a
/// stale timeline can't re-log a number the user has since moved past.
struct RepeatLastExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Repeat Last Expense"
    static var description = IntentDescription(
        "Records the same amount as your most recent expense."
    )

    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        let amount = CaptureQueue.lastExpenseAmount
        guard amount > 0 else { return .result() }
        CaptureQueue.append(
            amount: amount,
            note: CaptureQueue.lastExpenseNote,
            source: "widget"
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
