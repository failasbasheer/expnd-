// The amortization math decides real money figures — the monthly installment,
// the interest you'll pay, and how much principal still eats into a card's
// available credit. It had no direct coverage, only incidental exercise
// through the Upcoming projections, so it is pinned here.
//
// Expected values are computed from the closed-form formulas independently of
// the implementation, so a rewrite of the getters still has to agree with the
// arithmetic rather than with itself.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:expnd/models/models.dart';
import 'package:expnd/store/app_store.dart';

class _FakeBox implements Box {
  final Map<dynamic, dynamic> _m = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => _m[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _m[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Months back from today, so a fixture can be "three installments in"
/// regardless of when the suite runs.
///
/// The day must not sit *after* today's, or [Emi.monthsPaid] counts one fewer
/// whole month than intended — so it is today's day, capped at 28 so shifting
/// back never lands on a date the target month doesn't have.
DateTime monthsAgo(int n) {
  final now = DateTime.now();
  final day = now.day < 28 ? now.day : 28;
  return DateTime(now.year, now.month - n, day);
}

void main() {
  group('monthlyAmount', () {
    test('matches the closed-form EMI formula', () {
      final e = Emi(
        accountId: 'a',
        name: 'Car',
        principal: 500000,
        annualRate: 12,
        tenureMonths: 60,
      );

      const r = 12 / 12 / 100; // 1% a month
      final f = math.pow(1 + r, 60).toDouble();
      final expected = 500000 * r * f / (f - 1);

      expect(e.monthlyAmount, closeTo(expected, 0.01));
      // Sanity against a known figure: 5 lakh over 5 years at 12% is ~11,122/mo.
      expect(e.monthlyAmount, closeTo(11122.22, 1));
    });

    test('a zero-interest loan is just principal split evenly', () {
      final e = Emi(
        accountId: 'a',
        name: 'Phone',
        principal: 1200,
        annualRate: 0,
        tenureMonths: 12,
      );
      expect(e.monthlyAmount, closeTo(100, 0.0001));
      expect(e.totalInterest, closeTo(0, 0.0001));
    });

    test('a zero tenure never divides by zero', () {
      final e = Emi(
        accountId: 'a',
        name: 'Bad',
        principal: 1000,
        annualRate: 10,
        tenureMonths: 0,
      );
      expect(e.monthlyAmount, 0);
      expect(e.outstandingPrincipal, 0);
      expect(e.progress, 0);
    });
  });

  group('interest', () {
    test('total payable exceeds principal by the interest', () {
      final e = Emi(
        accountId: 'a',
        name: 'Car',
        principal: 500000,
        annualRate: 12,
        tenureMonths: 60,
      );
      expect(e.totalPayable, closeTo(e.monthlyAmount * 60, 0.01));
      expect(e.totalInterest, closeTo(e.totalPayable - 500000, 0.01));
      // Borrowing 5L at 12% for 5 years costs roughly 1.67L in interest.
      expect(e.totalInterest, closeTo(167333, 500));
    });

    test('a higher rate costs more interest for the same principal', () {
      Emi at(double rate) => Emi(
        accountId: 'a',
        name: 'L',
        principal: 100000,
        annualRate: rate,
        tenureMonths: 24,
      );
      expect(at(18).totalInterest, greaterThan(at(9).totalInterest));
    });
  });

  group('progress', () {
    test('counts whole elapsed months and clamps to the tenure', () {
      final e = Emi(
        accountId: 'a',
        name: 'Phone',
        principal: 1200,
        annualRate: 0,
        tenureMonths: 12,
        startDate: monthsAgo(3),
      );
      expect(e.monthsPaid, 3);
      expect(e.monthsRemaining, 9);
      expect(e.progress, closeTo(0.25, 0.0001));
      expect(e.isActive, isTrue);
    });

    test('a finished loan reports no remaining months and is inactive', () {
      final e = Emi(
        accountId: 'a',
        name: 'Old',
        principal: 1200,
        annualRate: 0,
        tenureMonths: 6,
        startDate: monthsAgo(24),
      );
      expect(e.monthsPaid, 6, reason: 'clamped to the tenure, not 24');
      expect(e.monthsRemaining, 0);
      expect(e.progress, 1.0);
      expect(e.isActive, isFalse);
    });

    test('a future-dated loan has not started paying', () {
      final now = DateTime.now();
      final e = Emi(
        accountId: 'a',
        name: 'Soon',
        principal: 1200,
        annualRate: 0,
        tenureMonths: 12,
        startDate: DateTime(now.year, now.month + 1, 1),
      );
      expect(e.monthsPaid, 0);
      expect(e.progress, 0);
    });
  });

  group('outstandingPrincipal', () {
    test('starts at the full principal and ends at zero', () {
      Emi at(int elapsed) => Emi(
        accountId: 'a',
        name: 'Car',
        principal: 500000,
        annualRate: 12,
        tenureMonths: 60,
        startDate: monthsAgo(elapsed),
      );

      expect(at(0).outstandingPrincipal, closeTo(500000, 1));
      expect(at(60).outstandingPrincipal, closeTo(0, 1));
    });

    test('matches the standard balance formula part-way through', () {
      final e = Emi(
        accountId: 'a',
        name: 'Car',
        principal: 500000,
        annualRate: 12,
        tenureMonths: 60,
        startDate: monthsAgo(12),
      );

      const r = 0.01;
      final full = math.pow(1 + r, 60).toDouble();
      final paid = math.pow(1 + r, 12).toDouble();
      final expected = 500000 * (full - paid) / (full - 1);

      expect(e.outstandingPrincipal, closeTo(expected, 0.01));
    });

    test('falls only slowly at first — interest front-loads', () {
      final e = Emi(
        accountId: 'a',
        name: 'Car',
        principal: 500000,
        annualRate: 12,
        tenureMonths: 60,
        startDate: monthsAgo(12),
      );
      // A fifth of the term is done, but well over a fifth is still owed.
      expect(e.outstandingPrincipal, greaterThan(500000 * 0.8));
    });

    test('a zero-interest loan pays principal down evenly', () {
      final e = Emi(
        accountId: 'a',
        name: 'Phone',
        principal: 1200,
        annualRate: 0,
        tenureMonths: 12,
        startDate: monthsAgo(3),
      );
      expect(e.outstandingPrincipal, closeTo(900, 0.01));
    });
  });

  group('recording installments', () {
    late AppStore store;
    late Account bank;
    late Emi loan;

    setUp(() {
      store = AppStore(_FakeBox());
      bank = Account(
        name: 'HDFC',
        type: AccountType.bank,
        currencyCode: 'USD',
        balance: 10000,
      );
      store.addAccount(bank);
      loan = Emi(
        accountId: 'card',
        name: 'iPhone',
        principal: 1200,
        annualRate: 0,
        tenureMonths: 12,
        startDate: monthsAgo(2),
      );
      store.addEmi(loan);
    });

    test('paying posts a real expense against the funding account', () {
      final before = store.balanceFor(bank);
      final t = store.payEmiInstallment(loan, accountId: bank.id);

      expect(t.type, TransactionType.expense);
      expect(t.emiId, loan.id);
      expect(t.accountId, bank.id);
      expect(t.amount, closeTo(100, 0.01));
      // The money really left, so the balance moves.
      expect(store.balanceFor(bank), closeTo(before - 100, 0.01));
    });

    test('a custom amount overrides the scheduled installment', () {
      store.payEmiInstallment(loan, accountId: bank.id, amount: 105.50);
      expect(store.paidOn(loan), closeTo(105.50, 0.01));
    });

    test('installments are tracked and totalled', () {
      expect(store.installmentsOn(loan), isEmpty);
      expect(store.paidOn(loan), 0);

      store.payEmiInstallment(
        loan,
        accountId: bank.id,
        date: DateTime(2026, 1, 10),
      );
      store.payEmiInstallment(
        loan,
        accountId: bank.id,
        date: DateTime(2026, 2, 10),
      );

      expect(store.installmentsOn(loan).length, 2);
      expect(store.paidOn(loan), closeTo(200, 0.01));
    });

    test('a month with a recorded payment is reported paid', () {
      final march = DateTime(2026, 3, 10);
      expect(store.isInstallmentPaid(loan, march), isFalse);
      store.payEmiInstallment(loan, accountId: bank.id, date: march);
      expect(store.isInstallmentPaid(loan, march), isTrue);
      expect(store.isInstallmentPaid(loan, DateTime(2026, 4, 10)), isFalse);
    });

    test('the schedule stays time-based, untouched by what was logged', () {
      final before = loan.outstandingPrincipal;
      store.payEmiInstallment(loan, accountId: bank.id);
      expect(loan.monthsPaid, 2, reason: 'still derived from the start date');
      expect(loan.outstandingPrincipal, closeTo(before, 0.01));
    });

    test('deleting the loan keeps the payments but untags them', () {
      store.payEmiInstallment(loan, accountId: bank.id);
      final balance = store.balanceFor(bank);

      store.deleteEmi(loan);

      expect(store.emis, isEmpty);
      // The money really moved, so the expense — and the balance — stay put.
      expect(store.balanceFor(bank), closeTo(balance, 0.01));
      expect(store.transactions.where((t) => t.emiId != null), isEmpty);
    });
  });
}
