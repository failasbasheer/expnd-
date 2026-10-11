import 'package:flutter/services.dart';

/// Text recognition runs entirely on the device through Vision (iOS) or ML
/// Kit's bundled recognizer (Android). The user reviews extracted fields before
/// anything is saved to the ledger.
class ReceiptOcr {
  static const channel = MethodChannel('com.expnd.app/receipt_ocr');

  static Future<ReceiptScan> scan(String imagePath) async {
    final raw = await channel.invokeMapMethod<String, dynamic>('recognize', {
      'imagePath': imagePath,
    });
    final lines = (raw?['lines'] as List?)?.whereType<String>().toList() ?? [];
    return ReceiptScan.fromLines(lines);
  }
}

class ReceiptScan {
  final String? merchant;
  final double? total;
  final DateTime? date;
  final List<String> lines;

  const ReceiptScan({
    required this.merchant,
    required this.total,
    required this.date,
    required this.lines,
  });

  factory ReceiptScan.fromLines(List<String> lines) {
    final clean = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final merchant = clean
        .where(
          (line) => !RegExp(
            r'^\d|^(receipt|invoice|tax|tel|phone|www|http)',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .firstOrNull;

    double? parseAmount(String text) {
      // Receipt dates and identifiers must never become suggested amounts.
      if (RegExp(r'\b\d{1,4}[/.-]\d{1,2}[/.-]\d{2,4}\b').hasMatch(text)) {
        return null;
      }
      final matches = RegExp(
        r'(?<![\d.,])(\d{1,3}(?:[., ]\d{3})+|\d+)([.,])(\d{2})(?!\d)',
      ).allMatches(text);
      if (matches.isEmpty) return null;
      final match = matches.last;
      final whole = match.group(1)!.replaceAll(RegExp(r'[., ]'), '');
      return double.tryParse('$whole.${match.group(3)}');
    }

    double? total;
    for (var index = clean.length - 1; index >= 0; index--) {
      final line = clean[index];
      if (RegExp(
            r'\b(grand total|total due|amount paid|balance due|total)\b',
            caseSensitive: false,
          ).hasMatch(line) &&
          !RegExp(
            r'\b(subtotal|sub total|tax total|total tax|total savings)\b',
            caseSensitive: false,
          ).hasMatch(line)) {
        total = parseAmount(line);
        if (total == null && index + 1 < clean.length) {
          total = parseAmount(clean[index + 1]);
        }
        if (total != null) break;
      }
    }

    DateTime? date;
    final datePattern = RegExp(r'\b(\d{1,4})[/.-](\d{1,2})[/.-](\d{2,4})\b');
    for (final line in clean) {
      final match = datePattern.firstMatch(line);
      if (match == null) continue;
      final a = int.parse(match.group(1)!);
      final b = int.parse(match.group(2)!);
      final c = int.parse(match.group(3)!);
      final yearFirst = a > 31;
      final year = yearFirst ? a : (c < 100 ? 2000 + c : c);
      // Ambiguous day/month dates are left for the user to enter.
      if (!yearFirst && a <= 12 && b <= 12 && a != b) continue;
      final month = yearFirst ? b : (a > 12 ? b : a);
      final day = yearFirst ? c : (a > 12 ? a : b);
      final candidate = DateTime(year, month, day);
      if (candidate.year == year &&
          candidate.month == month &&
          candidate.day == day) {
        date = candidate;
        break;
      }
    }
    return ReceiptScan(
      merchant: merchant,
      total: total,
      date: date,
      lines: clean,
    );
  }
}
