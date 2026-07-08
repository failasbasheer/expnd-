import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/expnd_theme.dart';

/// Simple id generator (mirrors SwiftData's persistentModelID identity).
int _idSeed = DateTime.now().microsecondsSinceEpoch;
String newId() => (_idSeed++).toString();

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum TransactionType {
  income('Income'),
  expense('Expense'),
  transfer('Transfer');

  final String raw;
  const TransactionType(this.raw);

  static TransactionType fromRaw(String? r) =>
      TransactionType.values.firstWhere((e) => e.raw == r,
          orElse: () => TransactionType.expense);
}

enum RecurrenceRule {
  daily('Daily'),
  weekly('Weekly'),
  biweekly('Biweekly'),
  monthly('Monthly'),
  yearly('Yearly');

  final String raw;
  const RecurrenceRule(this.raw);

  static RecurrenceRule fromRaw(String? r) =>
      RecurrenceRule.values.firstWhere((e) => e.raw == r,
          orElse: () => RecurrenceRule.monthly);

  String get icon {
    switch (this) {
      case RecurrenceRule.daily:
        return 'clock';
      case RecurrenceRule.weekly:
        return 'calendar.badge.clock';
      case RecurrenceRule.biweekly:
        return 'calendar.badge.plus';
      case RecurrenceRule.monthly:
        return 'calendar';
      case RecurrenceRule.yearly:
        return 'calendar.badge.checkmark';
    }
  }

  DateTime nextDate(DateTime date) {
    switch (this) {
      case RecurrenceRule.daily:
        return DateTime(date.year, date.month, date.day + 1, date.hour,
            date.minute, date.second);
      case RecurrenceRule.weekly:
        return date.add(const Duration(days: 7));
      case RecurrenceRule.biweekly:
        return date.add(const Duration(days: 14));
      case RecurrenceRule.monthly:
        return DateTime(date.year, date.month + 1, date.day, date.hour,
            date.minute, date.second);
      case RecurrenceRule.yearly:
        return DateTime(date.year + 1, date.month, date.day, date.hour,
            date.minute, date.second);
    }
  }
}

enum TransactionCategory {
  groceries('Groceries'),
  shopping('Shopping'),
  entertainment('Entertainment'),
  food('Food'),
  transport('Transport'),
  utilities('Utilities'),
  insurance('Insurance'),
  medical('Medical'),
  subscription('Subscription'),
  rent('Rent'),
  education('Education'),
  salary('Salary'),
  freelance('Freelance'),
  investment('Investment'),
  rental('Rental Income'),
  gift('Gift'),
  other('Other');

  final String raw;
  const TransactionCategory(this.raw);

  static TransactionCategory fromRaw(String? r) =>
      TransactionCategory.values.firstWhere((e) => e.raw == r,
          orElse: () => TransactionCategory.other);

  String get icon {
    switch (this) {
      case TransactionCategory.groceries:
        return 'cart.fill';
      case TransactionCategory.shopping:
        return 'bag.fill';
      case TransactionCategory.entertainment:
        return 'gamecontroller.fill';
      case TransactionCategory.food:
        return 'fork.knife';
      case TransactionCategory.transport:
        return 'car.fill';
      case TransactionCategory.utilities:
        return 'bolt.fill';
      case TransactionCategory.insurance:
        return 'shield.fill';
      case TransactionCategory.medical:
        return 'cross.circle.fill';
      case TransactionCategory.subscription:
        return 'apps.iphone';
      case TransactionCategory.rent:
        return 'building.fill';
      case TransactionCategory.education:
        return 'book.closed.fill';
      case TransactionCategory.salary:
        return 'banknote.fill';
      case TransactionCategory.freelance:
        return 'laptopcomputer';
      case TransactionCategory.investment:
        return 'chart.line.uptrend.xyaxis';
      case TransactionCategory.rental:
        return 'house.fill';
      case TransactionCategory.gift:
        return 'gift.fill';
      case TransactionCategory.other:
        return 'ellipsis.circle.fill';
    }
  }

  Color get color {
    switch (this) {
      case TransactionCategory.groceries:
        return hexColor('22C55E');
      case TransactionCategory.shopping:
        return hexColor('A855F7');
      case TransactionCategory.entertainment:
        return hexColor('3B82F6');
      case TransactionCategory.food:
        return hexColor('F97316');
      case TransactionCategory.transport:
        return hexColor('06B6D4');
      case TransactionCategory.utilities:
        return hexColor('EAB308');
      case TransactionCategory.salary:
        return hexColor('06C270');
      case TransactionCategory.freelance:
        return hexColor('6366F1');
      case TransactionCategory.investment:
        return hexColor('10B981');
      case TransactionCategory.insurance:
        return hexColor('8B5CF6');
      case TransactionCategory.medical:
        return hexColor('EF4444');
      case TransactionCategory.subscription:
        return hexColor('EC4899');
      case TransactionCategory.rent:
        return hexColor('F59E0B');
      case TransactionCategory.education:
        return hexColor('14B8A6');
      case TransactionCategory.rental:
        return hexColor('84CC16');
      case TransactionCategory.gift:
        return hexColor('F472B6');
      case TransactionCategory.other:
        return hexColor('94A3B8');
    }
  }

  static List<TransactionCategory> categoriesFor(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return [salary, freelance, investment, rental, gift, other];
      case TransactionType.expense:
        return [
          groceries, food, shopping, entertainment, transport,
          utilities, rent, subscription, insurance, medical, education,
          gift, other
        ];
      case TransactionType.transfer:
        return [];
    }
  }
}

enum AccountType {
  bank('Bank'),
  cash('Cash'),
  credit('Credit Card'),
  savings('Savings'),
  investment('Investment');

  final String raw;
  const AccountType(this.raw);

  static AccountType fromRaw(String? r) =>
      AccountType.values.firstWhere((e) => e.raw == r,
          orElse: () => AccountType.bank);

  String get icon {
    switch (this) {
      case AccountType.bank:
        return 'building.columns.fill';
      case AccountType.cash:
        return 'banknote.fill';
      case AccountType.credit:
        return 'creditcard.fill';
      case AccountType.savings:
        return 'chart.bar.fill';
      case AccountType.investment:
        return 'chart.line.uptrend.xyaxis';
    }
  }

  String get defaultColorHex {
    switch (this) {
      case AccountType.bank:
        return '1A56DB';
      case AccountType.cash:
        return '057A55';
      case AccountType.credit:
        return '7C3AED';
      case AccountType.savings:
        return 'C27803';
      case AccountType.investment:
        return '0E7490';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class Account {
  final String id;
  String name;
  AccountType type;
  String currencyCode;
  double balance;
  String colorHex;
  DateTime createdAt;

  /// Total sanctioned credit limit (credit cards only). null for other types.
  double? creditLimit;

  /// The user-typed portion of the card number — up to the first 10 digits.
  /// The last 6 digits are never entered and always render masked, so this
  /// only ever holds the leading digits the user chooses to reveal.
  String? cardDigits;

  Account({
    String? id,
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.balance,
    String? colorHex,
    DateTime? createdAt,
    this.creditLimit,
    this.cardDigits,
  })  : id = id ?? newId(),
        colorHex = colorHex ?? type.defaultColorHex,
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.raw,
        'currencyCode': currencyCode,
        'balance': balance,
        'colorHex': colorHex,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'creditLimit': creditLimit,
        'cardDigits': cardDigits,
      };

  factory Account.fromJson(Map j) => Account(
        id: j['id'] as String,
        name: j['name'] as String,
        type: AccountType.fromRaw(j['type'] as String?),
        currencyCode: j['currencyCode'] as String,
        balance: (j['balance'] as num).toDouble(),
        colorHex: j['colorHex'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt()),
        creditLimit: (j['creditLimit'] as num?)?.toDouble(),
        cardDigits: j['cardDigits'] as String?,
      );
}

/// Max digits the user may type of a card number. The remaining
/// [_maskedCardTail] digits are always masked and can never be entered.
const int kCardTypedDigits = 10;
const int _maskedCardTail = 6;

/// Renders a 16-digit card number as four space-separated groups. The user's
/// typed leading digits fill the front; every position past what they typed —
/// and always the final 6 — shows as a bullet. Passing null/empty yields a
/// fully masked number.
String maskedCardNumber(String? digits) {
  final d = (digits ?? '').replaceAll(RegExp(r'\D'), '');
  final typed = d.length > kCardTypedDigits ? d.substring(0, kCardTypedDigits) : d;
  final buf = StringBuffer();
  for (var i = 0; i < 16; i++) {
    final revealed = i < typed.length && i < (16 - _maskedCardTail);
    buf.write(revealed ? typed[i] : '•');
    if (i % 4 == 3 && i != 15) buf.write(' ');
  }
  return buf.toString();
}

class CustomCategory {
  final String id;
  String name;
  String emoji;
  String typeRaw; // "Income" / "Expense" / "Both"
  String colorHex;

  CustomCategory({
    String? id,
    required this.name,
    required this.emoji,
    required this.typeRaw,
    required this.colorHex,
  }) : id = id ?? newId();

  /// null == applies to both.
  TransactionType? get applicableType {
    if (typeRaw == TransactionType.income.raw) return TransactionType.income;
    if (typeRaw == TransactionType.expense.raw) return TransactionType.expense;
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'typeRaw': typeRaw,
        'colorHex': colorHex,
      };

  factory CustomCategory.fromJson(Map j) => CustomCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        emoji: j['emoji'] as String,
        typeRaw: j['typeRaw'] as String,
        colorHex: j['colorHex'] as String,
      );
}

class CategoryBudget {
  final String id;
  String categoryRaw;
  double limit;

  CategoryBudget({
    String? id,
    required TransactionCategory category,
    required this.limit,
  })  : id = id ?? newId(),
        categoryRaw = category.raw;

  TransactionCategory? get category =>
      TransactionCategory.values.where((e) => e.raw == categoryRaw).firstOrNull;

  Map<String, dynamic> toJson() =>
      {'id': id, 'categoryRaw': categoryRaw, 'limit': limit};

  factory CategoryBudget.fromJson(Map j) {
    final c = CategoryBudget(
      id: j['id'] as String,
      category: TransactionCategory.fromRaw(j['categoryRaw'] as String?),
      limit: (j['limit'] as num).toDouble(),
    );
    c.categoryRaw = j['categoryRaw'] as String;
    return c;
  }
}

class SavingsGoal {
  final String id;
  String name;
  double targetAmount;
  double currentAmount;
  String iconName;
  String colorHex;
  DateTime createdDate;

  SavingsGoal({
    String? id,
    required this.name,
    required this.targetAmount,
    this.currentAmount = 0,
    this.iconName = 'star.fill',
    this.colorHex = 'F7C948',
    DateTime? createdDate,
  })  : id = id ?? newId(),
        createdDate = createdDate ?? DateTime.now();

  double get progress =>
      targetAmount > 0 ? (currentAmount / targetAmount).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetAmount': targetAmount,
        'currentAmount': currentAmount,
        'iconName': iconName,
        'colorHex': colorHex,
        'createdDate': createdDate.millisecondsSinceEpoch,
      };

  factory SavingsGoal.fromJson(Map j) => SavingsGoal(
        id: j['id'] as String,
        name: j['name'] as String,
        targetAmount: (j['targetAmount'] as num).toDouble(),
        currentAmount: (j['currentAmount'] as num).toDouble(),
        iconName: j['iconName'] as String? ?? 'star.fill',
        colorHex: j['colorHex'] as String? ?? 'F7C948',
        createdDate: DateTime.fromMillisecondsSinceEpoch(
            (j['createdDate'] as num).toInt()),
      );
}

class Transaction {
  final String id;
  String note;
  double amount;
  TransactionCategory category;
  TransactionType type;
  DateTime date;
  bool isRecurring;
  String recurrenceRuleRaw;
  DateTime? nextDueDate;
  String? photoPath; // external file path (was photoData)
  String? customCategoryId;
  String? accountId;
  String? toAccountId;

  Transaction({
    String? id,
    this.note = '',
    required this.amount,
    required this.category,
    required this.type,
    DateTime? date,
    this.isRecurring = false,
    RecurrenceRule recurrenceRule = RecurrenceRule.monthly,
    DateTime? nextDueDate,
    this.photoPath,
    this.customCategoryId,
    this.accountId,
    this.toAccountId,
  })  : id = id ?? newId(),
        date = date ?? DateTime.now(),
        recurrenceRuleRaw = recurrenceRule.raw,
        nextDueDate = nextDueDate ??
            (isRecurring ? recurrenceRule.nextDate(date ?? DateTime.now()) : null);

  RecurrenceRule get recurrenceRule => RecurrenceRule.fromRaw(recurrenceRuleRaw);
  set recurrenceRule(RecurrenceRule r) => recurrenceRuleRaw = r.raw;

  Map<String, dynamic> toJson() => {
        'id': id,
        'note': note,
        'amount': amount,
        'category': category.raw,
        'type': type.raw,
        'date': date.millisecondsSinceEpoch,
        'isRecurring': isRecurring,
        'recurrenceRuleRaw': recurrenceRuleRaw,
        'nextDueDate': nextDueDate?.millisecondsSinceEpoch,
        'photoPath': photoPath,
        'customCategoryId': customCategoryId,
        'accountId': accountId,
        'toAccountId': toAccountId,
      };

  factory Transaction.fromJson(Map j) {
    final t = Transaction(
      id: j['id'] as String,
      note: j['note'] as String? ?? '',
      amount: (j['amount'] as num).toDouble(),
      category: TransactionCategory.fromRaw(j['category'] as String?),
      type: TransactionType.fromRaw(j['type'] as String?),
      date: DateTime.fromMillisecondsSinceEpoch((j['date'] as num).toInt()),
      isRecurring: j['isRecurring'] as bool? ?? false,
      photoPath: j['photoPath'] as String?,
      customCategoryId: j['customCategoryId'] as String?,
      accountId: j['accountId'] as String?,
      toAccountId: j['toAccountId'] as String?,
    );
    t.recurrenceRuleRaw =
        j['recurrenceRuleRaw'] as String? ?? RecurrenceRule.monthly.raw;
    final nd = j['nextDueDate'];
    t.nextDueDate =
        nd == null ? null : DateTime.fromMillisecondsSinceEpoch((nd as num).toInt());
    return t;
  }
}

/// An ongoing loan / EMI (Equated Monthly Installment) attached to an account
/// (typically a credit card). The monthly payment and amortization are derived
/// from principal, annual interest rate, and tenure — nothing about progress is
/// stored, so "months paid / remaining" stay live off [startDate].
class Emi {
  final String id;
  String accountId;
  String name;
  double principal;
  double annualRate; // nominal % per annum
  int tenureMonths;
  DateTime startDate;

  Emi({
    String? id,
    required this.accountId,
    required this.name,
    required this.principal,
    required this.annualRate,
    required this.tenureMonths,
    DateTime? startDate,
  })  : id = id ?? newId(),
        startDate = startDate ?? DateTime.now();

  double get _monthlyRate => annualRate / 12 / 100;

  /// The flat monthly installment: P·r·(1+r)^n / ((1+r)^n − 1).
  double get monthlyAmount {
    if (tenureMonths <= 0) return 0;
    final r = _monthlyRate;
    if (r == 0) return principal / tenureMonths;
    final f = math.pow(1 + r, tenureMonths).toDouble();
    return principal * r * f / (f - 1);
  }

  double get totalPayable => monthlyAmount * tenureMonths;
  double get totalInterest => totalPayable - principal;

  /// Whole months elapsed since [startDate], clamped to the tenure.
  int get monthsPaid {
    final now = DateTime.now();
    var m = (now.year - startDate.year) * 12 + (now.month - startDate.month);
    if (now.day < startDate.day) m -= 1;
    return m.clamp(0, tenureMonths);
  }

  int get monthsRemaining => (tenureMonths - monthsPaid).clamp(0, tenureMonths);
  bool get isActive => monthsRemaining > 0;
  double get amountPaid => monthlyAmount * monthsPaid;
  double get remainingAmount => monthlyAmount * monthsRemaining;
  double get progress =>
      tenureMonths <= 0 ? 0 : (monthsPaid / tenureMonths).clamp(0.0, 1.0);

  /// Outstanding principal still owed — this is what counts against a card's
  /// available credit. Uses the standard amortization balance formula.
  double get outstandingPrincipal {
    if (tenureMonths <= 0) return 0;
    final r = _monthlyRate;
    if (r == 0) {
      return principal * (monthsRemaining / tenureMonths);
    }
    final full = math.pow(1 + r, tenureMonths).toDouble();
    final paid = math.pow(1 + r, monthsPaid).toDouble();
    return principal * (full - paid) / (full - 1);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'name': name,
        'principal': principal,
        'annualRate': annualRate,
        'tenureMonths': tenureMonths,
        'startDate': startDate.millisecondsSinceEpoch,
      };

  factory Emi.fromJson(Map j) => Emi(
        id: j['id'] as String,
        accountId: j['accountId'] as String,
        name: j['name'] as String? ?? '',
        principal: (j['principal'] as num).toDouble(),
        annualRate: (j['annualRate'] as num).toDouble(),
        tenureMonths: (j['tenureMonths'] as num).toInt(),
        startDate:
            DateTime.fromMillisecondsSinceEpoch((j['startDate'] as num).toInt()),
      );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
