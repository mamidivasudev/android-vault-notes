import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault_notes/models.dart';
import 'package:vault_notes/notification_service.dart';
import 'package:vault_notes/vault_service.dart';
import 'package:vault_notes/views/mileage_view.dart' show averageMileage;

void main() {
  group('Bill cycles', () {
    test('an early payment covers the upcoming due date', () {
      // Due on the 2nd, paid on Oct 30 -> covers Nov 2.
      final bill = Bill(title: 'Card', dueDate: 2, isPaid: true, lastPaidDate: DateTime(2026, 10, 30));
      expect(bill.paidCycle, '2026-11');
      expect(bill.isPaidForCycle(DateTime(2026, 11, 1)), isTrue); // used to reset on the 1st
      expect(bill.isPaidForCycle(DateTime(2026, 11, 10)), isTrue);
      expect(bill.isPaidForCycle(DateTime(2026, 11, 20)), isFalse); // next cycle (Dec 2)
    });

    test('a late payment covers the due date just passed', () {
      final bill = Bill(title: 'Card', dueDate: 2, isPaid: true, lastPaidDate: DateTime(2026, 11, 4));
      expect(bill.paidCycle, '2026-11');
    });

    test('due day 31 is clamped to short months', () {
      expect(billDueDate(2026, 2, 31), DateTime(2026, 2, 28));
      expect(billDueDate(2028, 2, 31), DateTime(2028, 2, 29));
      expect(billDueDate(2026, 4, 31), DateTime(2026, 4, 30));
      expect(billDueDate(2026, 13, 5), DateTime(2027, 1, 5)); // month overflow
    });

    test('reminders skip a cycle that is already paid', () {
      final now = DateTime(2026, 10, 30, 12);
      final unpaid = billReminderTimes(dueDay: 2, daysBefore: [1], hour: 9, minute: 0, now: now);
      expect(unpaid.first.when, DateTime(2026, 11, 1, 9));
      final paid = billReminderTimes(dueDay: 2, daysBefore: [1], hour: 9, minute: 0, now: now, paidCycle: '2026-11');
      expect(paid.first.when, DateTime(2026, 12, 1, 9));
      expect(paid.every((t) => t.when.isAfter(now)), isTrue);
    });
  });

  group('Reminder recurrence', () {
    test('monthly on the 31st clamps instead of skipping a month', () {
      final anchor = DateTime(2026, 1, 31, 9);
      final feb = reminderOccurrenceAfter(anchor, 'monthly', anchor);
      expect(feb, DateTime(2026, 2, 28, 9)); // used to be Mar 3
      final mar = reminderOccurrenceAfter(anchor, 'monthly', feb);
      expect(mar, DateTime(2026, 3, 31, 9)); // back on the 31st, no drift
    });

    test('done on a missed daily reminder jumps past now', () {
      final anchor = DateTime(2026, 11, 1, 8);
      final now = DateTime(2026, 11, 6, 12);
      expect(reminderOccurrenceAfter(anchor, 'daily', now), DateTime(2026, 11, 7, 8));
    });

    test('weekly keeps the weekday', () {
      final anchor = DateTime(2026, 11, 2, 10); // Monday
      final next = reminderOccurrenceAfter(anchor, 'weekly', DateTime(2026, 11, 4));
      expect(next, DateTime(2026, 11, 9, 10));
      expect(next.weekday, DateTime.monday);
    });
  });

  group('Mileage', () {
    FuelEntry fill(String date, double odo, double litres, {bool? full}) =>
        FuelEntry(date: date, odometer: odo, rupees: 100, liters: litres, isFullTank: full);

    test('unrecorded odometer (0) does not inflate mileage', () {
      final entries = [
        fill('2026-03-19', 71, 1.12),
        fill('2026-03-22', 0, 0.93), // odometer not recorded
        fill('2026-03-23', 74, 1.86),
      ];
      // 3 km over all litres added after the first full fill (0.93 + 1.86)
      expect(averageMileage(entries), closeTo(3 / 2.79, 1e-9));
    });

    test('partial fills are added to the next full-tank segment', () {
      final entries = [
        fill('2026-01-01', 1000, 4, full: true),
        fill('2026-01-05', 1100, 2, full: false),
        fill('2026-01-10', 1200, 3, full: true),
      ];
      expect(averageMileage(entries), closeTo(200 / 5, 1e-9));
    });

    test('old JSON without the new fields still loads', () {
      final e = FuelEntry.fromJson({'date': '2026-01-01', 'odometer': 10, 'rupees': 5});
      expect(e.isFullTank, isNull);
      expect(e.liters, isNull);
      final bad = FuelEntry.fromJson({'date': null, 'odometer': null, 'rupees': null});
      expect(bad.hasOdometer, isFalse);
    });
  });

  group('Vault data safety', () {
    late Directory dir;
    late VaultService service;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vault_safety');
      SharedPreferences.setMockInitialValues({'vault_path': dir.path});
      service = VaultService()..clearCache();
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('an unreadable file is preserved before it is overwritten', () async {
      final file = File('${dir.path}/expenses_data.json');
      await file.writeAsString('{"expenses": [ {"id": "1", BROKEN');
      final data = await service.loadVaultData();
      expect(data['expenses'], isEmpty);

      await service.saveExpenses([Expense(title: 'new', amount: 1, category: 'A', date: DateTime.now())]);

      final copies = dir.listSync().where((f) => f.path.contains('expenses_data.json.unreadable-')).toList();
      expect(copies, hasLength(1));
      expect(await File(copies.first.path).readAsString(), contains('BROKEN'));
      expect(json.decode(await file.readAsString())['expenses'], hasLength(1));
    });

    test('saving notes still works when notes_data.json is corrupt (copy kept)', () async {
      final file = File('${dir.path}/notes_data.json');
      await file.writeAsString('not json');
      await service.saveNotes([Note(title: 'kept', content: 'x', category: 'General')], ['General']);
      final saved = json.decode(await file.readAsString());
      expect((saved['notes'] as List).single['title'], 'kept');
      expect(dir.listSync().any((f) => f.path.contains('notes_data.json.unreadable-')), isTrue);
    });

    test('saving link categories never wipes notes', () async {
      await service.saveNotes([Note(title: 'n', content: '', category: 'General')], ['General']);
      await service.saveLinkCategories(['Work']);
      final saved = json.decode(await File('${dir.path}/notes_data.json').readAsString());
      expect(saved['notes'], hasLength(1));
      expect(saved['linkCategories'], ['Work']);
    });

    test('link categories saved in notes_data win over stale ones in links_data', () async {
      await File('${dir.path}/notes_data.json').writeAsString(json.encode({'notes': [], 'linkCategories': ['New']}));
      await File('${dir.path}/links_data.json').writeAsString(json.encode({'links': [], 'linkCategories': ['Old']}));
      final data = await service.loadVaultData();
      expect(data['linkCategories'], ['New']);
    });

    test('local backups copy every data file and are pruned', () async {
      await service.saveNotes([Note(title: 'n', content: '', category: 'General')], ['General']);
      await service.saveExpenses([]);
      final snap = await service.createLocalBackup('test');
      expect(snap, isNotNull);
      expect(File('$snap/notes_data.json').existsSync(), isTrue);
      expect(File('$snap/expenses_data.json').existsSync(), isTrue);

      for (int i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1100)); // unique timestamps
        await service.createLocalBackup('t$i', keep: 3);
      }
      final root = Directory('${dir.path}/${VaultService.backupFolderName}');
      expect(root.listSync().whereType<Directory>().length, 3);
    });

    test('daily backup runs once per day', () async {
      await service.saveExpenses([]);
      await service.dailyBackupIfNeeded();
      await service.dailyBackupIfNeeded();
      final root = Directory('${dir.path}/${VaultService.backupFolderName}');
      expect(root.listSync().whereType<Directory>().length, 1);
    });
  });
}
