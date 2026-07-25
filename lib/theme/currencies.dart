import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Caps a decimal money input so oversized values can't overflow the gauges
/// and amount labels they feed (net worth, budget ring, account cards, EMI).
/// Allows up to 7 integer digits and 2 decimal places — i.e. max 9,999,999.99.
class AmountInputFormatter extends TextInputFormatter {
  static final RegExp _pattern = RegExp(r'^\d{0,7}(\.\d{0,2})?$');

  const AmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty || _pattern.hasMatch(text)) return newValue;
    // Reject the edit by keeping the previous valid value.
    return oldValue;
  }
}

/// Shared formatter list for all monetary amount fields.
const List<TextInputFormatter> amountInputFormatters = [AmountInputFormatter()];

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
  static const mask = '••••';
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

/// A bare grouped number with two decimals and no currency symbol
/// (e.g. `1,250.00`). Callers that render their own symbol use this.
String formatAmount(double amount) => AmountPrivacy.hidden
    ? AmountPrivacy.mask
    : NumberFormat('#,##0.00').format(amount);

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
