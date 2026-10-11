import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Largest number of integer digits a money field accepts. Twelve covers
/// everyday amounts in high-denomination currencies (IDR rent, KRW loans,
/// INR home loans) while staying well inside double precision.
const int kMaxAmountIntegerDigits = 12;

/// Validates a decimal money input as it's typed.
///
/// A comma is accepted as the decimal separator and normalised to '.', because
/// the decimal-pad keyboard shows ',' in comma-decimal regions (most of
/// Europe, Brazil, Turkey, ...). Decimal precision follows the field currency.
class AmountInputFormatter extends TextInputFormatter {
  final int decimalDigits;

  const AmountInputFormatter({this.decimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    const whole = '\\d{0,$kMaxAmountIntegerDigits}';
    final pattern = decimalDigits == 0
        ? RegExp('^$whole\$')
        : RegExp('^$whole(\\.\\d{0,$decimalDigits})?\$');
    if (text.isEmpty || pattern.hasMatch(text)) {
      return text == newValue.text ? newValue : newValue.copyWith(text: text);
    }
    // Reject the edit by keeping the previous valid value.
    return oldValue;
  }
}

/// The money-field formatter for [code]'s precision.
List<TextInputFormatter> amountFormattersFor(String code) => [
  AmountInputFormatter(decimalDigits: currencyDecimalDigits(code)),
];

/// Text to pre-fill a money field with [amount]: the currency's precision,
/// with trailing zeros after the decimal point dropped (100.125 KWD stays
/// "100.125", 250.40 becomes "250.4", 50000 JPY is "50000"). Returns '' for 0.
String amountInputText(double amount, String code) {
  if (amount == 0) return '';
  var s = amount.toStringAsFixed(currencyDecimalDigits(code));
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// Parses user-typed money or a rate, accepting ',' as the decimal separator.
double? parseAmount(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// [amount] rounded down to whole minor units of [code], for "Max" buttons:
/// rounding 100.2999 up to 100.30 would exceed what's actually available.
double floorToMinor(double amount, String code) {
  var factor = 1;
  for (var i = 0; i < currencyDecimalDigits(code); i++) {
    factor *= 10;
  }
  // Nudge by a hair first so 0.29 (stored as 0.28999...) doesn't floor to 0.28.
  return (amount * factor + 1e-6).floorToDouble() / factor;
}

/// [amount] rounded to whole minor units of [code] (cents, fils, ...), so
/// money can be compared exactly instead of with a float tolerance.
int toMinorUnits(double amount, String code) {
  var factor = 1;
  for (var i = 0; i < currencyDecimalDigits(code); i++) {
    factor *= 10;
  }
  return (amount * factor).round();
}

class CurrencyOption {
  final String code;
  final String name;
  final String symbol;
  const CurrencyOption(this.code, this.name, this.symbol);
}

const List<CurrencyOption> supportedCurrencies = [
  // Global majors
  CurrencyOption('USD', 'US Dollar', '\$'),
  CurrencyOption('EUR', 'Euro', '€'),
  CurrencyOption('GBP', 'British Pound', '£'),
  // South Asia
  CurrencyOption('INR', 'Indian Rupee', '₹'),
  CurrencyOption('PKR', 'Pakistani Rupee', '₨'),
  CurrencyOption('BDT', 'Bangladeshi Taka', '৳'),
  CurrencyOption('LKR', 'Sri Lankan Rupee', 'Rs'),
  // Middle East
  CurrencyOption('AED', 'UAE Dirham', 'AED'),
  CurrencyOption('SAR', 'Saudi Riyal', 'SAR'),
  CurrencyOption('QAR', 'Qatari Riyal', 'QAR'),
  CurrencyOption('KWD', 'Kuwaiti Dinar', 'KWD'),
  CurrencyOption('BHD', 'Bahraini Dinar', 'BHD'),
  CurrencyOption('OMR', 'Omani Rial', 'OMR'),
  CurrencyOption('JOD', 'Jordanian Dinar', 'JOD'),
  CurrencyOption('EGP', 'Egyptian Pound', 'E£'),
  // East & SE Asia
  CurrencyOption('JPY', 'Japanese Yen', '¥'),
  CurrencyOption('CNY', 'Chinese Yuan', '¥'),
  CurrencyOption('KRW', 'South Korean Won', '₩'),
  CurrencyOption('SGD', 'Singapore Dollar', 'S\$'),
  CurrencyOption('HKD', 'Hong Kong Dollar', 'HK\$'),
  CurrencyOption('MYR', 'Malaysian Ringgit', 'RM'),
  CurrencyOption('THB', 'Thai Baht', '฿'),
  CurrencyOption('IDR', 'Indonesian Rupiah', 'Rp'),
  CurrencyOption('PHP', 'Philippine Peso', '₱'),
  // Americas & Commonwealth
  CurrencyOption('CAD', 'Canadian Dollar', 'CA\$'),
  CurrencyOption('AUD', 'Australian Dollar', 'A\$'),
  CurrencyOption('NZD', 'New Zealand Dollar', 'NZ\$'),
  CurrencyOption('BRL', 'Brazilian Real', 'R\$'),
  CurrencyOption('MXN', 'Mexican Peso', 'MX\$'),
  // Europe
  CurrencyOption('CHF', 'Swiss Franc', 'Fr'),
  CurrencyOption('SEK', 'Swedish Krona', 'kr'),
  CurrencyOption('NOK', 'Norwegian Krone', 'kr'),
  CurrencyOption('DKK', 'Danish Krone', 'kr'),
  CurrencyOption('PLN', 'Polish Złoty', 'zł'),
  CurrencyOption('TRY', 'Turkish Lira', '₺'),
  CurrencyOption('RUB', 'Russian Ruble', '₽'),
  // Africa
  CurrencyOption('ZAR', 'South African Rand', 'R'),
  CurrencyOption('NGN', 'Nigerian Naira', '₦'),
  CurrencyOption('KES', 'Kenyan Shilling', 'KSh'),
  CurrencyOption('GHS', 'Ghanaian Cedi', '₵'),
];

String currencySymbol(String code) =>
    supportedCurrencies
        .where((c) => c.code == code)
        .map((c) => c.symbol)
        .firstOrNull ??
    '\$';

/// Minor-unit digits per ISO 4217. Most currencies use 2; a handful differ.
/// Getting this right matters for a worldwide release (e.g. ¥1,000 not ¥1,000.00,
/// and KWD 1.500 with three places).
int currencyDecimalDigits(String code) {
  switch (code) {
    case 'JPY':
    case 'KRW':
      return 0;
    case 'KWD':
    case 'BHD':
    case 'OMR':
      return 3;
    default:
      return 2;
  }
}

/// Global privacy gate behind the eye button in the dashboard and wallet
/// headers. When on, every user-facing money string renders as a mask instead
/// of the figure. Mirrored from `SettingsStore.amountsHidden` so the pure
/// formatters below can honour it without a [BuildContext] — screens rebuild on
/// toggle because they already watch the store for `currencyCode`.
class AmountPrivacy {
  AmountPrivacy._();

  static bool hidden = false;

  /// Fixed glyph count regardless of the real value, so a masked figure gives
  /// away nothing about its magnitude.
  static const mask = '●●●●';
}

/// Formats [amount] like SwiftUI's `.currency(code:)` — symbol + grouped value,
/// using the currency's correct number of decimal places.
///
/// Pass `maskable: false` for surfaces outside the app's own UI (the
/// home-screen widget bridge) — those have no eye button of their own, so they
/// always render the real figure.
String formatCurrency(double amount, String code, {bool maskable = true}) {
  final symbol = currencySymbol(code);
  // Keep the symbol: it costs nothing privacy-wise and holds the layout.
  if (maskable && AmountPrivacy.hidden) return '$symbol${AmountPrivacy.mask}';
  final f = NumberFormat.currency(
    symbol: symbol,
    decimalDigits: currencyDecimalDigits(code),
  );
  return f.format(amount);
}

/// A whole-number percentage ("63%"), masked with the amounts: a share of a
/// budget or a month-on-month change says a lot about the hidden figures.
String formatPercent(num value) =>
    AmountPrivacy.hidden ? '●●%' : '${value.round()}%';

/// A bare grouped number with two decimals and no currency symbol
/// (e.g. `1,250.00`). Callers that render their own symbol use this.
String formatAmount(double amount) => AmountPrivacy.hidden
    ? AmountPrivacy.mask
    : NumberFormat('#,##0.00').format(amount);

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
