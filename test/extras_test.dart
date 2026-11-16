import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/extras/extras_models.dart';

void main() {
  group('Important dates', () {
    final bday = ImportantDate(title: 'Amma', month: 3, day: 15, year: 1970);

    test('next occurrence is this year when still ahead, else next year', () {
      expect(bday.nextFrom(DateTime(2026, 1, 1)), DateTime(2026, 3, 15));
      expect(bday.nextFrom(DateTime(2026, 3, 16)), DateTime(2027, 3, 15));
    });

    test('today counts as 0 days, and the age is shown', () {
      expect(bday.daysUntil(DateTime(2026, 3, 15, 18)), 0);
      expect(bday.yearsOnNext(DateTime(2026, 3, 15)), 56);
    });

    test('29 February falls on 28 February in other years', () {
      final leap = ImportantDate(title: 'Leap', month: 2, day: 29);
      expect(leap.nextFrom(DateTime(2027, 1, 1)), DateTime(2027, 2, 28));
      expect(leap.nextFrom(DateTime(2028, 1, 1)), DateTime(2028, 2, 29));
    });

    test('survives saving and loading', () {
      final again = ImportantDate.fromJson(bday.toJson());
      expect([again.title, again.month, again.day, again.year], ['Amma', 3, 15, 1970]);
    });
  });

  group('Money', () {
    test('remaining goes down with payments and settles', () {
      final e = MoneyEntry(person: 'Ravi', amount: 1000, lent: true, date: DateTime(2026, 1, 1));
      final part = e.copyWith(payments: [MoneyPayment(amount: 400, date: DateTime(2026, 2, 1))]);
      expect(part.remaining, 600);
      expect(part.settled, isFalse);
      final done = part.copyWith(payments: [...part.payments, MoneyPayment(amount: 600, date: DateTime(2026, 3, 1))]);
      expect(done.settled, isTrue);
    });

    test('overdue only when unpaid and past the due date', () {
      final e = MoneyEntry(person: 'A', amount: 100, lent: false, date: DateTime(2026, 1, 1), dueDate: DateTime(2026, 2, 1));
      expect(e.isOverdue(DateTime(2026, 2, 2)), isTrue);
      expect(e.isOverdue(DateTime(2026, 1, 31)), isFalse);
      expect(MoneyEntry.fromJson(e.toJson()).dueDate, DateTime(2026, 2, 1));
    });
  });

  group('Medicines', () {
    test('ticks per day and stock survive saving and loading', () {
      final m = Medicine(name: 'Dolo', times: ['21:00', '08:00'], stock: 10, taken: {
        '2026-11-16': ['08:00'],
      });
      expect(m.times, ['08:00', '21:00']); // kept in time order
      final again = Medicine.fromJson(m.toJson());
      expect(again.isTaken('2026-11-16', '08:00'), isTrue);
      expect(again.isTaken('2026-11-16', '21:00'), isFalse);
      expect(again.stock, 10);
      expect(again.copyWith(stock: 4).isLow, isTrue);
    });
  });

  test('journal entry keeps its day and mood', () {
    final j = JournalEntry(day: DateTime(2026, 11, 16), text: 'Good day', mood: '🙂');
    final again = JournalEntry.fromJson(j.toJson());
    expect(dayKey(again.day), '2026-11-16');
    expect(again.mood, '🙂');
  });
}
