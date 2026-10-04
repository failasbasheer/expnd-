import Foundation
import WidgetKit

/// The handoff between "logged from outside the app" and "in the ledger".
///
/// App Intents run in the widget extension's process, which has no access to
/// the app's Hive store — so a capture can't become a transaction here. Instead
/// it lands in a queue inside the shared App Group, and the Flutter app drains
/// it into its pending-capture inbox on next launch or resume.
///
/// Entries stay queued until the app explicitly acknowledges them by rewriting
/// the array without their ids. Draining is therefore idempotent: an app that
/// dies mid-drain replays the same entries rather than losing them, and the
/// Dart side skips ids it already holds.
enum CaptureQueue {
    /// Must match WidgetBridge.appGroupId and the App Group on both targets.
    static let appGroupId = "group.com.expnd.app"

    /// The key `home_widget` reads and writes from Dart. Keep in sync with
    /// CaptureInbox.queueKey.
    static let queueKey = "pending_captures"
    static let consumedKey = "consumed_capture_ids"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Writing

    /// Appends a capture and returns the new queue depth, so a caller can tell
    /// the user how many are waiting. A malformed or missing queue is treated
    /// as empty rather than as an error — losing the tap would be worse than
    /// losing whatever unreadable thing was there.
    @discardableResult
    static func append(amount: Double, note: String, source: String) -> Int {
        guard amount > 0, let d = defaults else { return 0 }

        var entries = read()
        entries.append([
            "id": newId(),
            "amount": amount,
            "note": note,
            // Milliseconds, matching how every date crosses into Dart here.
            "at": Int(Date().timeIntervalSince1970 * 1000),
            "source": source,
        ])
        write(entries, to: d)
        return entries.count
    }

    // MARK: - Reading

    static var pendingCount: Int { read().count }

    private static func read() -> [[String: Any]] {
        guard let raw = defaults?.string(forKey: queueKey),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let entries = parsed as? [[String: Any]]
        else { return [] }
        let consumed: Set<String> = {
            guard let raw = defaults?.string(forKey: consumedKey),
                  let data = raw.data(using: .utf8),
                  let ids = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return Set(ids)
        }()
        return entries.filter { entry in
            guard let id = entry["id"] as? String else { return true }
            return !consumed.contains(id)
        }
    }

    private static func write(_ entries: [[String: Any]], to d: UserDefaults) {
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
              let json = String(data: data, encoding: .utf8)
        else { return }
        d.set(json, forKey: queueKey)
    }

    /// Ids must be unique across processes and stable enough for the Dart side
    /// to dedupe on, which a UUID gives us without any shared counter.
    private static func newId() -> String { "cap-\(UUID().uuidString)" }

    // MARK: - Snapshot reads

    /// Quick-capture preset amounts published by WidgetBridge. Empty until the
    /// app has synced at least once, which is also when the widget has nothing
    /// worth showing anyway.
    static var presets: [Double] {
        guard let raw = defaults?.string(forKey: "presets"), !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { Double($0) }
    }

    static func string(_ key: String, _ fallback: String = "") -> String {
        defaults?.string(forKey: key) ?? fallback
    }

    /// The most recent expense's amount, for repeat-last. Zero when there is
    /// no expense to repeat, which the UI uses to hide the button entirely.
    static var lastExpenseAmount: Double {
        defaults?.double(forKey: "last_expense_amount") ?? 0
    }

    static var lastExpenseNote: String { string("last_expense_note") }

    static var currencySymbol: String { string("symbol", "$") }

    /// Formats an amount the way the widget's buttons label themselves —
    /// symbol-prefixed and without decimals, since presets are round numbers.
    static func presetLabel(_ amount: Double) -> String {
        let whole = amount.rounded()
        if abs(amount - whole) < 0.005 {
            return "\(currencySymbol)\(Int(whole))"
        }
        return String(format: "%@%.2f", currencySymbol, amount)
    }
}
