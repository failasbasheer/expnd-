// Basic smoke test for model serialization.
import 'package:flutter_test/flutter_test.dart';
import 'package:expnd/models/models.dart';

void main() {
  test('Transaction round-trips through JSON', () {
    final t = Transaction(
      note: 'Coffee',
      amount: 4.5,
      category: TransactionCategory.food,
      type: TransactionType.expense,
    );
    final copy = Transaction.fromJson(t.toJson());
    expect(copy.amount, 4.5);
    expect(copy.category, TransactionCategory.food);
    expect(copy.type, TransactionType.expense);
    expect(copy.note, 'Coffee');
  });
}
