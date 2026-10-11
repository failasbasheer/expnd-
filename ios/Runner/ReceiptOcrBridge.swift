import Flutter
import Foundation
import UIKit
import Vision
import ImageIO

/// Apple's Vision text recognizer runs locally and supports the system's
/// available recognition languages. Only recognized lines cross the channel.
final class ReceiptOcrBridge {
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.expnd.app/receipt_ocr",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { call, result in
            guard call.method == "recognize" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard
                let arguments = call.arguments as? [String: Any],
                let path = arguments["imagePath"] as? String,
                let image = UIImage(contentsOfFile: path),
                let cgImage = image.cgImage
            else {
                result(FlutterError(code: "invalid_image", message: "The receipt photo could not be opened.", details: nil))
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.imageOrientation.cgOrientation, options: [:])
                    try handler.perform([request])
                    let observations = (request.results ?? []).sorted { left, right in
                        if abs(left.boundingBox.midY - right.boundingBox.midY) > 0.02 {
                            return left.boundingBox.midY > right.boundingBox.midY
                        }
                        return left.boundingBox.minX < right.boundingBox.minX
                    }
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    DispatchQueue.main.async { result(["lines": lines]) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "recognition_failed", message: "The receipt could not be read.", details: nil))
                    }
                }
            }
        }
    }
}

private extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
