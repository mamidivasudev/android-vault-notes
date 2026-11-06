import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault_notes/models.dart';
import 'package:vault_notes/vault_service.dart';

void main() {
  group('Models', () {
    test('deletedAt survives JSON and can be cleared with copyWith', () {
      final when = DateTime(2026, 1, 2, 3, 4);
      final note = Note(title: 't', content: 'c', category: 'General', deletedAt: when);
      final back = Note.fromJson(note.toJson());
      expect(back.deletedAt, when);
      expect(back.copyWith(deletedAt: null).deletedAt, isNull);
      expect(back.copyWith(title: 'x').deletedAt, when);

      final exp = Expense(title: 'e', amount: 1, category: 'A', date: DateTime(2020), deletedAt: when);
      expect(Expense.fromJson(exp.toJson()).deletedAt, when);
      final link = LinkItem(title: 'l', url: 'https://x.y', category: 'All', deletedAt: when);
      expect(LinkItem.fromJson(link.toJson()).deletedAt, when);
    });

    test('Bill.copyWith can clear lastPaidDate', () {
      final bill = Bill(title: 'Card', dueDate: 5, isPaid: true, lastPaidDate: DateTime(2026, 5, 1));
      expect(bill.copyWith(isPaid: false, lastPaidDate: null).lastPaidDate, isNull);
      expect(bill.copyWith(title: 'x').lastPaidDate, DateTime(2026, 5, 1));
    });
  });

  group('VaultService', () {
    late Directory dir;
    late VaultService service;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vault_test');
      SharedPreferences.setMockInitialValues({'vault_path': dir.path});
      service = VaultService()..clearCache();
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('Recycle Bin purge uses deletedAt, not the item date', () async {
      final now = DateTime.now();
      final file = File('${dir.path}/deleted_data.json');
      await file.writeAsString(json.encode({
        'notes': [
          // Old note deleted recently -> must be kept.
          {'id': 'keep', 'title': 'a', 'content': '', 'createdAt': '2020-01-01T00:00:00.000', 'deletedAt': now.toIso8601String()},
          // Deleted 40 days ago -> purged.
          {'id': 'gone', 'title': 'b', 'content': '', 'createdAt': now.toIso8601String(), 'deletedAt': now.subtract(const Duration(days: 40)).toIso8601String()},
          // From an older app version without deletedAt -> kept and stamped.
          {'id': 'legacy', 'title': 'c', 'content': '', 'createdAt': '2020-01-01T00:00:00.000'},
        ],
        'expenses': [
          // Old transaction date, deleted today -> kept.
          {'id': 'e1', 'title': 'x', 'amount': 5, 'date': '2019-01-01T00:00:00.000', 'deletedAt': now.toIso8601String()},
        ],
        'links': [],
      }));

      await service.purgeOldDeletedItems();
      final data = await service.loadDeletedData();
      final ids = (data['notes'] as List).map((n) => n['id']).toList();
      expect(ids, containsAll(['keep', 'legacy']));
      expect(ids, isNot(contains('gone')));
      expect((data['notes'] as List).firstWhere((n) => n['id'] == 'legacy')['deletedAt'], isNotNull);
      expect((data['expenses'] as List).length, 1);
    });

    test('Deleted notes/expenses/links are saved side by side', () async {
      await service.saveDeletedNotes([Note(title: 'n', content: '', category: 'General')]);
      await service.saveDeletedExpenses([Expense(title: 'e', amount: 1, category: 'A', date: DateTime.now())]);
      await service.saveDeletedLinks([LinkItem(title: 'l', url: 'https://a.b', category: 'All')]);
      final data = await service.loadDeletedData();
      expect((data['notes'] as List).length, 1);
      expect((data['expenses'] as List).length, 1);
      expect((data['links'] as List).length, 1);
    });

    test('SharedPreferences-only data round-trips through app_settings.json', () async {
      SharedPreferences.setMockInitialValues({
        'vault_path': dir.path,
        'grocery_items': ['{"id":"1","name":"Rice","isPurchased":false,"createdAt":"2026-01-01T00:00:00.000"}'],
        'expense_budgets': '{"Food":5000.0}',
        'last_service_odo': 1500.0,
      });
      await service.exportAppSettings();
      expect(await File('${dir.path}/app_settings.json').exists(), isTrue);

      // Simulate a fresh install pointed at the same vault.
      SharedPreferences.setMockInitialValues({'vault_path': dir.path});
      await service.importAppSettings();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('grocery_items'), hasLength(1));
      expect(prefs.getString('expense_budgets'), '{"Food":5000.0}');
      expect(prefs.getDouble('last_service_odo'), 1500.0);
    });

    test('clearCache makes replaced files visible', () async {
      await service.saveReminders([Reminder(title: 'a', description: '', dateTime: DateTime.now())]);
      expect((await service.loadVaultData())['reminders'], hasLength(1));
      // A restore writes the file directly...
      await File('${dir.path}/reminders_data.json').writeAsString(json.encode({'reminders': []}));
      service.clearCache();
      expect((await service.loadVaultData())['reminders'], isEmpty);
    });

    test('Manual monthly snapshots are flagged', () async {
      await service.addOrUpdateMonthlySnapshot(2026, 5, 10, 20, manual: true);
      final reports = await service.loadMonthlyReports();
      expect(reports.single['manual'], isTrue);
    });
  });
}
