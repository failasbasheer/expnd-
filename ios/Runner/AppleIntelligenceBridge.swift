import Flutter
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Keeps Apple's model behind one small channel so the Flutter application can
/// continue supporting older iOS versions and non-Apple platforms unchanged.
final class AppleIntelligenceBridge {
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.expnd.app/apple_intelligence",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(isModelAvailable())
        case "summarizeInsights":
            guard
                let arguments = call.arguments as? [String: Any],
                let facts = arguments["facts"] as? [[String: Any]],
                let mode = arguments["mode"] as? String
            else {
                result(FlutterError(
                    code: "invalid_arguments",
                    message: "Verified insight facts are required.",
                    details: nil
                ))
                return
            }
            summarize(facts: facts, mode: mode, result: result)
        case "suggestCategory":
            guard
                let arguments = call.arguments as? [String: Any],
                let description = arguments["description"] as? String,
                let categories = arguments["categories"] as? [String],
                !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !categories.isEmpty
            else {
                result(FlutterError(
                    code: "invalid_arguments",
                    message: "A description and allowed categories are required.",
                    details: nil
                ))
                return
            }
            suggestCategory(
                description: String(description.prefix(240)),
                categories: Array(categories.prefix(24)),
                result: result
            )
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// True only when the system model can answer right now: the device is
    /// eligible (A17 Pro / M1 or newer), Apple Intelligence is switched on,
    /// the model has finished downloading, and the current language is
    /// supported. Everything else uses the app's rule-based coach.
    private func isModelAvailable() -> Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return false }
            return model.supportsLocale(Locale.current)
        }
#endif
        return false
    }

    private func suggestCategory(
        description: String,
        categories: [String],
        result: @escaping FlutterResult
    ) {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                result(FlutterError(
                    code: "model_unavailable",
                    message: "Apple Intelligence is not available on this device.",
                    details: nil
                ))
                return
            }

            let session = LanguageModelSession(
                model: model,
                instructions: """
                Classify a transaction using only its short merchant or note.
                Reply with exactly one category from the supplied list. Do not
                add punctuation, explanation, or a category that is not listed.
                """
            )
            let prompt = """
                Note: \(description)
                Allowed categories: \(categories.joined(separator: ", "))
                """

            Task {
                do {
                    let response = try await session.respond(
                        to: prompt,
                        options: GenerationOptions(
                            temperature: 0.0,
                            maximumResponseTokens: 12
                        )
                    )
                    let answer = response.content.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let canonical = categories.first {
                        $0.caseInsensitiveCompare(answer) == .orderedSame
                    }
                    await MainActor.run { result(canonical) }
                } catch {
                    await MainActor.run {
                        result(FlutterError(
                            code: "generation_failed",
                            message: "A category could not be suggested.",
                            details: String(describing: error)
                        ))
                    }
                }
            }
            return
        }
#endif

        result(FlutterError(
            code: "unsupported_os",
            message: "Apple Intelligence requires iOS 26 or later.",
            details: nil
        ))
    }

    private func summarize(
        facts: [[String: Any]],
        mode: String,
        result: @escaping FlutterResult
    ) {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                result(FlutterError(
                    code: "model_unavailable",
                    message: "Apple Intelligence is not available on this device.",
                    details: nil
                ))
                return
            }

            let lines = facts.prefix(3).compactMap { fact -> String? in
                guard
                    let title = fact["title"] as? String,
                    let detail = fact["detail"] as? String,
                    !title.isEmpty,
                    !detail.isEmpty
                else { return nil }
                return "- \(title.prefix(140)) — \(detail.prefix(220))"
            }
            guard !lines.isEmpty else {
                result(FlutterError(
                    code: "invalid_arguments",
                    message: "At least one complete insight is required.",
                    details: nil
                ))
                return
            }

            let request: String
            switch mode {
            case "focus":
                request = """
                    Name the single fact that deserves attention now and briefly
                    explain why. Be direct but never alarming or judgmental.
                    """
            case "win":
                request = """
                    Point out the clearest positive fact. If there is no positive
                    fact, say exactly: No clear win yet — keep logging.
                    """
            case "next_step":
                request = """
                    Give one tiny, concrete budgeting or bookkeeping step directly
                    supported by one fact. It should be doable today.
                    """
            case "summary":
                request = """
                    Connect the most useful one or two facts into a concise summary.
                    You may suggest one small action only when a fact supports it.
                    """
            default:
                result(FlutterError(
                    code: "invalid_arguments",
                    message: "Unknown coaching mode.",
                    details: nil
                ))
                return
            }

            let session = LanguageModelSession(
                model: model,
                instructions: """
                You explain personal-finance facts in calm, plain language.
                Every fact was calculated and verified by the app. Never do new
                arithmetic or introduce numbers, dates, merchants, claims, or
                predictions that are not in those facts. Do not give investment,
                tax, credit, or legal advice. Never shame the user. Write at most
                two short sentences, using simple words.
                """
            )
            let prompt = """
                \(request)
                Preserve any number you use exactly.

                \(lines.joined(separator: "\n"))
                """

            Task {
                do {
                    let response = try await session.respond(
                        to: prompt,
                        options: GenerationOptions(
                            temperature: 0.2,
                            maximumResponseTokens: 90
                        )
                    )
                    let content = response.content
                    await MainActor.run { result(content) }
                } catch {
                    let details = String(describing: error)
                    await MainActor.run {
                        result(FlutterError(
                            code: "generation_failed",
                            message: "The on-device summary could not be created.",
                            details: details
                        ))
                    }
                }
            }
            return
        }
#endif

        result(FlutterError(
            code: "unsupported_os",
            message: "Apple Intelligence requires iOS 26 or later.",
            details: nil
        ))
    }
}
