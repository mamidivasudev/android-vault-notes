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

  group('dates', () {
    final now = DateTime(2026, 11, 23, 10);
    test('no date said means today', () {
      expect(parseSpokenExpense('milk 10 rupees', now: now).date, DateTime(2026, 11, 23));
    });
    test('"on 21st" / "date 22nd" take that day this month, amount kept', () {
      final r = parseSpokenExpense('milk 10 rupees on date 21st', now: now);
      expect(r.date, DateTime(2026, 11, 21));
      expect(r.amount, 10);
      expect(r.title, 'Milk');
      expect(parseSpokenExpense('milk 10 ruppes date 22nd', now: now).date, DateTime(2026, 11, 22));
    });
    test('a day still ahead means last month', () {
      expect(parseSpokenExpense('petrol 500 on 25th', now: now).date, DateTime(2026, 10, 25));
    });
    test('yesterday and a named month', () {
      expect(parseSpokenExpense('tea 20 yesterday', now: now).date, DateTime(2026, 11, 22));
      expect(parseSpokenExpense('rent 8000 on 5th november', now: now).date, DateTime(2026, 11, 5));
      expect(parseSpokenExpense('rent 8000 on 5th november', now: now).amount, 8000);
    });
  });

  test('no number means no amount', () {
    expect(parseSpokenExpense('add milk').amount, isNull);
  });
}
