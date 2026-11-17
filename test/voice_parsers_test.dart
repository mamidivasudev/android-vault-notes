import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/utils/voice_parsers.dart';

void main() {
  final now = DateTime(2026, 11, 17, 10);

  group('Dates by voice', () {
    test('gas started today, remind in 30 days', () {
      final d = parseSpokenDate('gas started today, remind in 30 days', now: now);
      expect(d.type, 'Household');
      expect(d.title, 'Gas used date');
      expect(d.date, DateTime(2026, 11, 17));
      expect(d.remindOn, DateTime(2026, 12, 17));
    });

    test('Amma birthday 15 March', () {
      final d = parseSpokenDate('Amma birthday 15 March', now: now);
      expect(d.type, 'Birthday');
      expect(d.title, 'Amma birthday');
      expect(d.date, DateTime(2026, 3, 15));
      expect(d.yearKnown, isFalse);
    });

    test('anniversary with a year, month first', () {
      final d = parseSpokenDate('marriage anniversary May 11 2015', now: now);
      expect(d.type, 'Anniversary');
      expect(d.date, DateTime(2015, 5, 11));
      expect(d.yearKnown, isTrue);
    });

    test('reminder in a month', () {
      final d = parseSpokenDate('oil opened yesterday remind me after 1 month', now: now);
      expect(d.date, DateTime(2026, 11, 16));
      expect(d.remindOn, DateTime(2026, 12, 17));
    });
  });

  group('Medicines by voice', () {
    test('Dolo 650 at 8 AM and 9 PM', () {
      final m = parseSpokenMedicine('Dolo 650 at 8 AM and 9 PM');
      expect(m.name, 'Dolo 650');
      expect(m.times, ['08:00', '21:00']);
    });

    test('a.m. / p.m., minutes, dose and parts of day', () {
      final m = parseSpokenMedicine('vitamin D 1 tablet at 8:30 a.m. and night');
      expect(m.name, 'Vitamin D');
      expect(m.dose, '1 tablet');
      expect(m.times, ['08:30', '21:00']);
    });
  });
}
