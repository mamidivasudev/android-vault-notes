import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault_notes/extras/extras_models.dart';
import 'package:vault_notes/vault_service.dart';

/// The Medicines / Dates / Diary files must be saved to the vault folder,
/// copied into local snapshots and included in Drive backup/restore.
void main() {
  late Directory dir;
  late VaultService vault;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('extras_vault');
    SharedPreferences.setMockInitialValues({'vault_path': dir.path});
    vault = VaultService()..clearCache();
  });

  tearDown(() => dir.delete(recursive: true));

  test('new tab files are part of every backup and Drive sync', () {
    for (final f in ['medicines_data.json', 'dates_data.json', 'date_categories.json', 'journal_data.json']) {
      expect(VaultService.dataFiles, contains(f));
    }
    expect(VaultService.dataFiles, isNot(contains('money_data.json')));
  });

  test('saved items load back exactly', () async {
    final dates = [
      ImportantDate(title: 'Gas', type: 'Household', month: 11, day: 16, year: 2026, remindOn: DateTime(2026, 12, 16)),
      ImportantDate(title: 'My Birthday', month: 12, day: 10, year: 1995),
    ];
    await vault.saveExtraList('dates_data.json', 'dates', dates.map((d) => d.toJson()).toList());
    final back = (await vault.loadExtraList('dates_data.json', 'dates'))
        .map((e) => ImportantDate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    expect(back.map((d) => d.title), ['Gas', 'My Birthday']);
    expect(back.first.isHousehold, isTrue);
    expect(back.first.remindOn, DateTime(2026, 12, 16));
    expect(back.last.year, 1995);
  });

  test('a local snapshot copies the new tab files', () async {
    await vault.saveExtraList('journal_data.json', 'journal', [JournalEntry(day: DateTime(2026, 11, 16, 9), text: 'Hi').toJson()]);
    await vault.saveExtraList('medicines_data.json', 'medicines', [Medicine(name: 'Dolo', times: ['08:00']).toJson()]);
    final snap = await vault.createLocalBackup('test');
    expect(snap, isNotNull);
    expect(File('$snap/journal_data.json').existsSync(), isTrue);
    expect(File('$snap/medicines_data.json').existsSync(), isTrue);
  });

  test('a damaged file is kept aside before it is overwritten', () async {
    final f = File('${dir.path}/dates_data.json');
    await f.writeAsString('{not valid json');
    expect(await vault.loadExtraList('dates_data.json', 'dates'), isEmpty);
    await vault.saveExtraList('dates_data.json', 'dates', []);
    final kept = dir.listSync().where((e) => e.path.contains('dates_data.json.unreadable-'));
    expect(kept, hasLength(1));
    expect(await File(kept.first.path).readAsString(), '{not valid json');
    expect(jsonDecode(await f.readAsString())['dates'], isEmpty);
  });

  test('missing file (nothing saved yet) loads as empty, no error', () async {
    expect(await vault.loadExtraList('journal_data.json', 'journal'), isEmpty);
  });
}
