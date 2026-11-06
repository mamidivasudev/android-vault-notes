import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/models.dart';
import 'package:vault_notes/widgets/note_card.dart' show noteTimeLabel;

void main() {
  group('Note model', () {
    test('updatedAt, colorIndex and isChecklist survive JSON', () {
      final created = DateTime(2026, 1, 1, 9);
      final edited = DateTime(2026, 2, 1, 10);
      final note = Note(
        title: 't',
        content: '[x] milk',
        category: 'General',
        createdAt: created,
        updatedAt: edited,
        colorIndex: 3,
        isChecklist: true,
      );
      final back = Note.fromJson(note.toJson());
      expect(back.createdAt, created);
      expect(back.updatedAt, edited);
      expect(back.colorIndex, 3);
      expect(back.isChecklist, isTrue);
      expect(back.lastModified, edited);
    });

    test('old notes without the new fields still load', () {
      final back = Note.fromJson({'id': 'a', 'title': 'x', 'content': 'y', 'createdAt': '2025-05-05T10:00:00.000'});
      expect(back.updatedAt, isNull);
      expect(back.colorIndex, 0);
      expect(back.isChecklist, isFalse);
      expect(back.lastModified, back.createdAt);
    });

    test('copyWith can clear updatedAt and keeps createdAt', () {
      final note = Note(title: 't', content: 'c', category: 'G', createdAt: DateTime(2020), updatedAt: DateTime(2021));
      final edited = note.copyWith(content: 'new');
      expect(edited.createdAt, DateTime(2020));
      expect(edited.updatedAt, DateTime(2021));
      expect(note.copyWith(updatedAt: null).updatedAt, isNull);
    });
  });

  group('ChecklistItem', () {
    test('parse and serialize round-trip', () {
      const content = '[ ] eggs\n[x] milk\n[X] bread';
      final items = ChecklistItem.parse(content);
      expect(items.map((i) => i.text), ['eggs', 'milk', 'bread']);
      expect(items.map((i) => i.checked), [false, true, true]);
      expect(ChecklistItem.serialize(items), '[ ] eggs\n[x] milk\n[x] bread');
    });

    test('plain text conversion drops blank lines', () {
      expect(ChecklistItem.fromPlainText('a\n\n  b  \n'), '[ ] a\n[ ] b');
      expect(ChecklistItem.toPlainText('[x] a\n[ ] b'), 'a\nb');
    });

    test('lines without a marker become unchecked items', () {
      final items = ChecklistItem.parse('just text');
      expect(items.single.text, 'just text');
      expect(items.single.checked, isFalse);
    });
  });

  group('noteTimeLabel', () {
    test('shows created date when never edited', () {
      final note = Note(title: '', content: '', category: 'G', createdAt: DateTime(2024, 3, 5));
      expect(noteTimeLabel(note), 'Mar 05, 2024');
    });

    test('shows relative edit time', () {
      final note = Note(
        title: '',
        content: '',
        category: 'G',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(noteTimeLabel(note), 'Edited 2h ago');
    });
  });
}
