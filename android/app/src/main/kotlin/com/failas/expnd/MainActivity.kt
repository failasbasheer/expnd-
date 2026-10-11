package com.failas.expnd

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Must extend FlutterFragmentActivity (not FlutterActivity) so the local_auth
// biometric prompt has an AndroidX FragmentActivity host. Otherwise
// authenticate() throws `no_fragment_activity` at runtime.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.expnd.app/receipt_ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("imagePath")
                if (path.isNullOrBlank() || !File(path).isFile) {
                    result.error("invalid_image", "The receipt photo could not be opened.", null)
                    return@setMethodCallHandler
                }
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                try {
                    val image = InputImage.fromFilePath(this, Uri.fromFile(File(path)))
                    recognizer.process(image)
                        .addOnSuccessListener { text ->
                            result.success(mapOf("lines" to text.textBlocks.flatMap { block ->
                                block.lines.map { line -> line.text }
                            }))
                            recognizer.close()
                        }
                        .addOnFailureListener {
                            result.error("recognition_failed", "The receipt could not be read.", null)
                            recognizer.close()
                        }
                } catch (_: Exception) {
                    recognizer.close()
                    result.error("invalid_image", "The receipt photo could not be opened.", null)
                }
            }
    }
}
