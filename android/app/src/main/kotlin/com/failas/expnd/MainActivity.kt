package com.failas.expnd

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
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
                            result.success(mapOf("lines" to receiptRows(text)))
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

    // ML Kit groups text into column blocks, so a receipt's "TOTAL" label and
    // its amount arrive in different blocks, far apart. Rebuild visual rows
    // (top-to-bottom, then left-to-right) so the Dart parser sees
    // "TOTAL 23.45" on one line, matching what Vision returns on iOS.
    private fun receiptRows(text: Text): List<String> {
        val lines = text.textBlocks.flatMap { it.lines }
        val boxed = lines.filter { it.boundingBox != null }
            .sortedBy { it.boundingBox!!.exactCenterY() }
        val rows = mutableListOf<MutableList<Text.Line>>()
        for (line in boxed) {
            val box = line.boundingBox!!
            val row = rows.lastOrNull()
            val anchor = row?.first()?.boundingBox
            if (anchor != null &&
                Math.abs(box.exactCenterY() - anchor.exactCenterY()) <
                minOf(box.height(), anchor.height()) / 2f
            ) {
                row!!.add(line)
            } else {
                rows.add(mutableListOf(line))
            }
        }
        return rows.map { row ->
            row.sortedBy { it.boundingBox!!.left }.joinToString("  ") { it.text }
        } + lines.filter { it.boundingBox == null }.map { it.text }
    }
}
