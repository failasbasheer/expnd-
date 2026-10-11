import 'package:flutter_test/flutter_test.dart';

import 'package:expnd/theme/currencies.dart';

String? _type(String text, {int decimals = 2, String from = ''}) {
  final out = AmountInputFormatter(decimalDigits: decimals).formatEditUpdate(
    TextEditingValue(text: from),
    TextEditingValue(text: text),
  );
  return out.text;
}

void main() {
  group('AmountInputFormatter', () {
    test('a comma from a comma-decimal keypad becomes the decimal point', () {
      expect(_type('12,5'), '12.5');
      expect(parseAmount('12,50'), 12.5);
    });

    test('accepts high-denomination amounts beyond 9,999,999', () {
      expect(_type('150000000', decimals: 0), '150000000');
      expect(_type('9999999999.99'), '9999999999.99');
    });

    test('rejects a 13th integer digit and keeps the previous value', () {
      expect(_type('1234567890123', from: '123456789012'), '123456789012');
    });

    test('follows the currency precision', () {
      expect(_type('1.125', decimals: 3), '1.125');
      expect(_type('1.125', from: '1.12'), '1.12');
      expect(_type('1.5', decimals: 0, from: '1'), '1');
    });
  });

  group('amountInputText', () {
    test('keeps the currency precision without trailing zeros', () {
      expect(amountInputText(100.125, 'KWD'), '100.125');
      expect(amountInputText(250.40, 'USD'), '250.4');
      expect(amountInputText(50000, 'JPY'), '50000');
      expect(amountInputText(1200, 'USD'), '1200');
      expect(amountInputText(0, 'USD'), '');
    });

    test('pre-filled text is always accepted by the field formatter', () {
      for (final (v, code) in [
        (100.125, 'KWD'),
        (50000.0, 'JPY'),
        (9.99, 'EUR'),
      ]) {
        final text = amountInputText(v, code);
        expect(
          _type(text, decimals: currencyDecimalDigits(code)),
          text,
          reason: code,
        );
      }
    });
  });

  test('floorToMinor never rounds up past the available amount', () {
    expect(floorToMinor(100.2999, 'USD'), 100.29);
    expect(floorToMinor(0.29, 'USD'), 0.29);
    expect(floorToMinor(1.0009, 'KWD'), 1.0);
  });

  test('toMinorUnits compares money exactly per currency', () {
    expect(toMinorUnits(10.125, 'KWD'), 10125);
    expect(
      toMinorUnits(6.12 + 4.00, 'KWD'),
      isNot(toMinorUnits(10.125, 'KWD')),
    );
    expect(toMinorUnits(0.1 + 0.2, 'USD'), toMinorUnits(0.3, 'USD'));
  });
}
