import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/utils/voice_expense.dart';

void main() {
  test('add milk rupees 33', () {
    final r = parseSpokenExpense('add milk rupees 33');
    expect(r.title, 'Milk');
    expect(r.amount, 33);
    expect(r.category, isNull);
  });

  test('different ways of saying it', () {
    expect(parseSpokenExpense('milk 33').amount, 33);
    expect(parseSpokenExpense('Petrol 500 rupees').title, 'Petrol');
    expect(parseSpokenExpense('spent 1,250 on electricity bill').amount, 1250);
    expect(parseSpokenExpense('spent 1,250 on electricity bill').title, 'Electricity bill');
    expect(parseSpokenExpense('₹45 tea and snacks').title, 'Tea snacks');
    expect(parseSpokenExpense('rs 20.50 bus ticket').amount, 20.5);
  });

  test('a named category is picked and removed from the title', () {
    final r = parseSpokenExpense('add vegetables 120 in grocery', categories: ['All', 'Grocery', 'Travel']);
    expect(r.title, 'Vegetables');
    expect(r.amount, 120);
    expect(r.category, 'Grocery');
  });

  test('no number means no amount', () {
    expect(parseSpokenExpense('add milk').amount, isNull);
  });
}
