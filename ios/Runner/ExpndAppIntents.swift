import AppIntents
import Foundation
import WidgetKit

/// Siri and Shortcuts entry point for logging an amount by voice.
///
/// This lives in the app target rather than the widget extension because App
/// Shortcut phrases are only discoverable when the app itself declares them —
/// an extension's intents show up in the Shortcuts app but never answer "Hey
/// Siri". The widget's own buttons use the extension's copies instead
/// (ExpndWidget/CaptureIntents.swift).
///
/// It deliberately does not touch Hive. The intent may run while the app isn't
/// launched, and opening the store from a background intent process would race
/// the running app. Writing to the same App Group queue the widget uses keeps
/// exactly one path into the ledger: the Flutter side drains it on resume.

/// The shared-container queue, mirrored from ExpndWidget/CaptureQueue.swift.
/// The two targets are separate binaries with no shared framework, so this
/// small duplication is the cost of not adding one — keep both in sync, along
/// with CaptureInbox.queueKey on the Dart side.
enum AppCaptureQueue {
    static let appGroupId = "group.com.expnd.app"
    static let queueKey = "pending_captures"
    static let consumedKey = "consumed_capture_ids"

    @discardableResult
    static func append(amount: Double, note: String, source: String) -> Int {
        guard amount > 0, let d = UserDefaults(suiteName: appGroupId) else { return 0 }

        var entries: [[String: Any]] = []
        if let raw = d.string(forKey: queueKey),
           !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data),
           let existing = parsed as? [[String: Any]] {
            let consumed: Set<String> = {
                guard let raw = d.string(forKey: consumedKey),
                      let data = raw.data(using: .utf8),
                      let ids = try? JSONSerialization.jsonObject(with: data) as? [String]
                else { return [] }
                return Set(ids)
            }()
            entries = existing.filter { entry in
                guard let id = entry["id"] as? String else { return true }
                return !consumed.contains(id)
            }
        }

        entries.append([
            "id": "cap-\(UUID().uuidString)",
            "amount": amount,
            "note": note,
            "at": Int(Date().timeIntervalSince1970 * 1000),
            "source": source,
        ])

        if let data = try? JSONSerialization.data(withJSONObject: entries),
           let json = String(data: data, encoding: .utf8) {
            d.set(json, forKey: queueKey)
        }
        return entries.count
    }

    static var currencySymbol: String {
        UserDefaults(suiteName: appGroupId)?.string(forKey: "symbol") ?? ""
    }
}

/// The app still deploys to iOS 13, so everything AppIntents touches is gated
/// rather than the deployment target being raised — voice logging is a bonus,
/// not a reason to drop devices that run the rest of the app fine.
@available(iOS 16.0, *)
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense"
    static var description = IntentDescription(
        "Records an amount in EXPND. You choose the account and category later, in the app."
    )

    /// Answering by voice is the entire point — launching the app would defeat
    /// it. The capture is confirmed in the spoken reply instead.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", requestValueDialog: "How much?")
    var amount: Double

    @Parameter(title: "Note", requestValueDialog: "What was it for?")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) in EXPND for \(\.$note)")
    }

    init() {}

    init(amount: Double, note: String?) {
        self.amount = amount
        self.note = note
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        AppCaptureQueue.append(amount: amount, note: trimmed, source: "siri")

        // The Quick Log widget shows a "to file" count, so it needs redrawing
        // even though the capture came from Siri.
        WidgetCenter.shared.reloadAllTimelines()

        let symbol = AppCaptureQueue.currencySymbol
        let spoken = symbol.isEmpty
            ? String(format: "%g", amount)
            : "\(symbol)\(String(format: "%g", amount))"
        let what = trimmed.isEmpty ? "" : " for \(trimmed)"
        return .result(dialog: "Logged \(spoken)\(what). File it in EXPND when you're ready.")
    }
}

/// What a Back Tap runs.
///
/// iOS gives apps no way to observe Back Tap directly — the gesture can only run
/// a Shortcut, and a Shortcut can run this. So "Back Tap support" is really
/// this: a parameterless intent worth binding a gesture to, plus the setup steps
/// in Settings → Quick Add.
///
/// Unlike the intents above it takes nothing and records nothing. It exists to
/// open the app on the Quick Add screen so the user types the amount and picks a
/// category themselves. A gesture that can fire from inside a pocket must not
/// silently commit a number to the ledger, and it has no way to know the amount
/// anyway.
@available(iOS 16.0, *)
struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add"
    static var description = IntentDescription(
        "Opens EXPND on the Quick Add screen, ready for an amount."
    )

    /// The opposite of every other intent here: opening the app *is* the effect.
    static var openAppWhenRun: Bool = true

    /// Keep in sync with CaptureTrigger.requestKey on the Dart side.
    static let requestKey = "capture_request"

    init() {}

    /// Leaves a timestamp for the Flutter side to find. A flag rather than a
    /// direct call because there's no guaranteed ordering between this running
    /// and Flutter finishing its launch — see CaptureTrigger for the other half.
    /// Milliseconds, matching how every other date crosses into Dart here.
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: AppCaptureQueue.appGroupId)?.set(
            String(Int(Date().timeIntervalSince1970 * 1000)),
            forKey: Self.requestKey
        )
        return .result()
    }
}

/// Zero-setup Siri phrases. `applicationName` is required in every phrase, and
/// covering both "EXPND" and the natural verb forms means the user doesn't have
/// to learn an exact incantation.
///
/// Declaring Quick Add here is also what makes it selectable as a Back Tap
/// action without the user having to build anything first.
@available(iOS 16.0, *)
struct ExpndShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Log spending in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "Record a payment in \(.applicationName)",
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "Quick add in \(.applicationName)",
                "Open quick add in \(.applicationName)",
                "New expense in \(.applicationName)",
            ],
            shortTitle: "Quick Add",
            systemImageName: "bolt.fill"
        )
    }
}
