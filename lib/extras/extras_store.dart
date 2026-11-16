import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../notification_service.dart';
import '../providers.dart' show vaultServiceProvider, vaultPathProvider;
import '../vault_service.dart';
import 'extras_models.dart';

/// A list kept in its own vault file (so it is part of local backups,
/// daily snapshots and Drive sync like every other tab).
abstract class VaultListNotifier<T> extends Notifier<List<T>> {
  String get fileName;
  String get jsonKey;
  T fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson(T item);
  String idOf(T item);

  /// Runs after every load and change, e.g. to schedule notifications.
  Future<void> afterChange(List<T> items) async {}

  Future<void>? _init;
  Future<void> get ready => _init ?? Future.value();

  @override
  List<T> build() {
    ref.watch(vaultPathProvider);
    _init = _load();
    return [];
  }

  Future<void> _load() async {
    final raw = await ref.read(vaultServiceProvider).loadExtraList(fileName, jsonKey);
    final items = <T>[];
    for (final e in raw) {
      try {
        items.add(fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {
        // Keep a copy of the file before the next save drops this entry.
        VaultService.markUnreadable(fileName);
      }
    }
    state = items;
  }

  Future<void> _write(List<T> items) async {
    state = items;
    await ref.read(vaultServiceProvider).saveExtraList(fileName, jsonKey, items.map(toJson).toList());
    await afterChange(items);
  }

  /// Adds the item, or replaces the one with the same id.
  Future<void> save(T item) async {
    await ready;
    final id = idOf(item);
    final exists = state.any((e) => idOf(e) == id);
    await _write(exists ? [for (final e in state) idOf(e) == id ? item : e] : [...state, item]);
  }

  Future<void> remove(String id) async {
    await ready;
    await _write(state.where((e) => idOf(e) != id).toList());
  }

  Future<void> removeMany(Set<String> ids) async {
    await ready;
    await _write(state.where((e) => !ids.contains(idOf(e))).toList());
  }

  /// Puts deleted items back (Undo).
  Future<void> restoreMany(List<T> items) async {
    await ready;
    final ids = items.map(idOf).toSet();
    await _write([...state.where((e) => !ids.contains(idOf(e))), ...items]);
  }
}

// ── Notifications ────────────────────────────────────────────────────────────

int _alertId(String key, int base, int slot) => (key.hashCode & 0x00FFFFFF) | ((base + slot) << 24);
const _medicineBase = 64; // slots 0-15
const _refillBase = 90;
const _dateBase = 100; // +0 on the day, +1 the day before
const _maxMedicineTimes = 16;

Future<void> _notify(int id, String title, String body, DateTime when, {DateTimeComponents? match}) async {
  try {
    await NotificationService().flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_extras_channel',
          'Medicines & dates',
          channelDescription: 'Medicine times, birthdays and anniversaries',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: match,
      payload: 'extra',
    );
  } catch (e) {
    // ignore: avoid_print
    print('Could not schedule $title: $e');
  }
}

Future<void> _cancel(int id) => NotificationService().cancelNotification(id);

DateTime _nextAt(int hour, int minute) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, hour, minute);
  return today.isAfter(now) ? today : today.add(const Duration(days: 1));
}

Future<void> scheduleMedicine(Medicine m) async {
  for (var slot = 0; slot < _maxMedicineTimes; slot++) {
    await _cancel(_alertId(m.id, _medicineBase, slot));
  }
  if (!m.active) return;
  for (var slot = 0; slot < m.times.length && slot < _maxMedicineTimes; slot++) {
    final parts = m.times[slot].split(':');
    final when = _nextAt(int.tryParse(parts[0]) ?? 8, int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    await _notify(
      _alertId(m.id, _medicineBase, slot),
      '💊 ${m.name}',
      m.dose.isEmpty ? 'Time to take your medicine' : 'Time to take ${m.dose}',
      when,
      match: DateTimeComponents.time,
    );
  }
}

/// "💊 Dolo is running low — 5 left", shown right away.
Future<void> notifyLowStock(Medicine m) async {
  try {
    await NotificationService().flutterLocalNotificationsPlugin.show(
      _alertId(m.id, _refillBase, 0),
      '💊 ${m.name} is running low',
      '${m.stock} left — time to buy more',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_extras_channel',
          'Medicines & dates',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: 'extra',
    );
  } catch (_) {}
}

Future<void> cancelMedicine(String id) async {
  for (var slot = 0; slot < _maxMedicineTimes; slot++) {
    await _cancel(_alertId(id, _medicineBase, slot));
  }
}

Future<void> scheduleDate(ImportantDate d) async {
  await _cancel(_alertId(d.id, _dateBase, 0));
  await _cancel(_alertId(d.id, _dateBase, 1));
  await _cancel(_alertId(d.id, _dateBase, 2));
  if (d.isHousehold) {
    // No yearly alert; just the optional reminder date, at 9 AM.
    final r = d.remindOn;
    if (r == null) return;
    final when = DateTime(r.year, r.month, r.day, 9);
    if (!when.isAfter(DateTime.now())) return;
    final start = d.startDate;
    await _notify(
      _alertId(d.id, _dateBase, 2),
      '🏠 Reminder: ${d.title}',
      'Since ${start.day}/${start.month}/${start.year} · ${when.difference(start).inDays} days',
      when,
    );
    return;
  }
  final now = DateTime.now();
  final emoji = d.type == 'Birthday' ? '🎂' : d.type == 'Anniversary' ? '💍' : '📅';
  final years = d.yearsOnNext(now);
  final extra = years == null || years <= 0 ? '' : d.type == 'Birthday' ? ' (turns $years)' : ' ($years years)';

  // A yearly repeat, starting from the next one still in the future.
  DateTime upcoming(int hour, {int daysBefore = 0}) {
    var y = now.year;
    while (true) {
      final w = d.inYear(y).subtract(Duration(days: daysBefore));
      final at = DateTime(w.year, w.month, w.day, hour);
      if (at.isAfter(now)) return at;
      y++;
    }
  }

  await _notify(_alertId(d.id, _dateBase, 0), '$emoji Today: ${d.title}', '${d.type}$extra', upcoming(9),
      match: DateTimeComponents.dateAndTime);
  if (d.remindDayBefore) {
    await _notify(_alertId(d.id, _dateBase, 1), '$emoji Tomorrow: ${d.title}', '${d.type}$extra',
        upcoming(19, daysBefore: 1),
        match: DateTimeComponents.dateAndTime);
  }
}

Future<void> cancelDate(String id) async {
  await _cancel(_alertId(id, _dateBase, 0));
  await _cancel(_alertId(id, _dateBase, 1));
  await _cancel(_alertId(id, _dateBase, 2));
}

/// Re-schedules every medicine and date alert (app start, after a restore).
Future<void> rescheduleExtrasAlerts(VaultService vault) async {
  try {
    for (final raw in await vault.loadExtraList(MedicinesNotifier.file, 'medicines')) {
      try {
        await scheduleMedicine(Medicine.fromJson(Map<String, dynamic>.from(raw as Map)));
      } catch (_) {}
    }
    for (final raw in await vault.loadExtraList(ImportantDatesNotifier.file, 'dates')) {
      try {
        await scheduleDate(ImportantDate.fromJson(Map<String, dynamic>.from(raw as Map)));
      } catch (_) {}
    }
  } catch (_) {}
}

// ── Providers ────────────────────────────────────────────────────────────────

class MedicinesNotifier extends VaultListNotifier<Medicine> {
  static const file = 'medicines_data.json';
  @override
  String get fileName => file;
  @override
  String get jsonKey => 'medicines';
  @override
  Medicine fromJson(Map<String, dynamic> json) => Medicine.fromJson(json);
  @override
  Map<String, dynamic> toJson(Medicine item) => item.toJson();
  @override
  String idOf(Medicine item) => item.id;

  /// Ticks / unticks one dose for [day]; stock goes down / back up.
  Future<void> toggleTaken(String id, String day, String time) async {
    await ready;
    final m = state.where((e) => e.id == id).firstOrNull;
    if (m == null) return;
    final takenToday = [...?m.taken[day]];
    final wasTaken = takenToday.remove(time);
    if (!wasTaken) takenToday.add(time);
    // Only the last 60 days of ticks are kept.
    final cutoff = dayKey(DateTime.now().subtract(const Duration(days: 60)));
    final taken = {
      for (final e in m.taken.entries)
        if (e.key.compareTo(cutoff) >= 0 && e.key != day) e.key: e.value,
      if (takenToday.isNotEmpty) day: takenToday,
    };
    int? stock = m.stock;
    if (stock != null) stock = (stock + (wasTaken ? m.perDose : -m.perDose)).clamp(0, 1 << 30);
    final updated = m.copyWith(taken: taken, stock: stock);
    await save(updated);
    // Just dropped to the warning level: one refill notification.
    if (!m.isLow && updated.isLow) await notifyLowStock(updated);
  }

  Future<void> delete(String id) async {
    await remove(id);
    await cancelMedicine(id);
  }

  Future<void> deleteMany(Set<String> ids) async {
    await removeMany(ids);
    for (final id in ids) {
      await cancelMedicine(id);
    }
  }

  @override
  Future<void> afterChange(List<Medicine> items) async {
    for (final m in items) {
      await scheduleMedicine(m);
    }
  }
}

final medicinesProvider = NotifierProvider<MedicinesNotifier, List<Medicine>>(MedicinesNotifier.new);

class ImportantDatesNotifier extends VaultListNotifier<ImportantDate> {
  static const file = 'dates_data.json';
  @override
  String get fileName => file;
  @override
  String get jsonKey => 'dates';
  @override
  ImportantDate fromJson(Map<String, dynamic> json) => ImportantDate.fromJson(json);
  @override
  Map<String, dynamic> toJson(ImportantDate item) => item.toJson();
  @override
  String idOf(ImportantDate item) => item.id;

  Future<void> delete(String id) async {
    await remove(id);
    await cancelDate(id);
  }

  Future<void> deleteMany(Set<String> ids) async {
    await ready;
    await _write(state.where((d) => !ids.contains(d.id)).toList());
    for (final id in ids) {
      await cancelDate(id);
    }
  }


  @override
  Future<void> afterChange(List<ImportantDate> items) async {
    for (final d in items) {
      await scheduleDate(d);
    }
  }
}

final importantDatesProvider = NotifierProvider<ImportantDatesNotifier, List<ImportantDate>>(ImportantDatesNotifier.new);

/// The user's own Dates categories (the built-in ones are not stored).
class DateCategoriesNotifier extends VaultListNotifier<DateCategory> {
  static const file = 'date_categories.json';
  @override
  String get fileName => file;
  @override
  String get jsonKey => 'categories';
  @override
  DateCategory fromJson(Map<String, dynamic> json) => DateCategory.fromJson(json);
  @override
  Map<String, dynamic> toJson(DateCategory item) => item.toJson();
  @override
  String idOf(DateCategory item) => item.name.toLowerCase();
}

final dateCategoriesProvider = NotifierProvider<DateCategoriesNotifier, List<DateCategory>>(DateCategoriesNotifier.new);

class JournalNotifier extends VaultListNotifier<JournalEntry> {
  static const file = 'journal_data.json';
  @override
  String get fileName => file;
  @override
  String get jsonKey => 'journal';
  @override
  JournalEntry fromJson(Map<String, dynamic> json) => JournalEntry.fromJson(json);
  @override
  Map<String, dynamic> toJson(JournalEntry item) => item.toJson();
  @override
  String idOf(JournalEntry item) => item.id;
}

final journalProvider = NotifierProvider<JournalNotifier, List<JournalEntry>>(JournalNotifier.new);
