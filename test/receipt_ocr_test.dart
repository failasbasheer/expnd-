import 'package:expnd/services/receipt_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supports decimal commas and amounts on the line after total', () {
    final scan = ReceiptScan.fromLines(['Shop', 'Total', '1.234,56']);
    expect(scan.total, 1234.56);
  });

  test('does not confuse dates, subtotals or tender with a total', () {
    final scan = ReceiptScan.fromLines([
      'Shop',
      '15.03.2026',
      'Subtotal 18.00',
      'Cash 50.00',
    ]);
    expect(scan.total, isNull);
    expect(scan.date, DateTime(2026, 3, 15));
  });

  test('leaves ambiguous dates for review', () {
    expect(ReceiptScan.fromLines(['Shop', '03/04/2026']).date, isNull);
  });

  test('extracts merchant, total, and date from recognized lines', () {
    final scan = ReceiptScan.fromLines([
      'Corner Market',
      'Receipt 101',
      '15/03/2026',
      'Bread 4.50',
      'Milk 5.00',
      'Grand Total 9.50',
    ]);
    expect(scan.merchant, 'Corner Market');
    expect(scan.total, 9.5);
    expect(scan.date, DateTime(2026, 3, 15));
  });

  test('does not invent a total when no money is recognized', () {
    final scan = ReceiptScan.fromLines(['Cafe', 'Thank you']);
    expect(scan.merchant, 'Cafe');
    expect(scan.total, isNull);
    expect(scan.date, isNull);
  });
}
