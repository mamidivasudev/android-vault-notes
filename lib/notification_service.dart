import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:io';
import 'vault_service.dart';
import 'models.dart';

// ── Recurrence maths (pure, unit-tested) ─────────────────────────────────────

/// Occurrence of a monthly series in [year]/[month]: the anchor's day,
/// clamped to the month's length (31st → 28th/29th/30th), at the anchor's time.
DateTime _monthlyOccurrence(DateTime anchor, int year, int month) {
  final first = DateTime(year, month, 1); // normalises month 0 / 13
  final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
  final day = anchor.day > daysInMonth ? daysInMonth : anchor.day;
  return DateTime(first.year, first.month, day, anchor.hour, anchor.minute);
}

/// First occurrence of the series started at [anchor] that is at or after [from].
DateTime reminderOccurrenceOnOrAfter(DateTime anchor, String repeatType, DateTime from) {
  if (!from.isAfter(anchor)) return anchor;
  switch (repeatType.toLowerCase()) {
    case 'daily':
      var c = DateTime(from.year, from.month, from.day, anchor.hour, anchor.minute);
      if (c.isBefore(from)) c = DateTime(from.year, from.month, from.day + 1, anchor.hour, anchor.minute);
      return c;
    case 'weekly':
      final diff = (anchor.weekday - from.weekday) % 7;
      var c = DateTime(from.year, from.month, from.day + diff, anchor.hour, anchor.minute);
      if (c.isBefore(from)) c = DateTime(c.year, c.month, c.day + 7, anchor.hour, anchor.minute);
      return c;
    case 'monthly':
      var c = _monthlyOccurrence(anchor, from.year, from.month);
      if (c.isBefore(from)) c = _monthlyOccurrence(anchor, from.year, from.month + 1);
      return c;
    default:
      return anchor;
  }
}

/// First occurrence of the series strictly after [after].
DateTime reminderOccurrenceAfter(DateTime anchor, String repeatType, DateTime after) {
  final t = DateTime(after.year, after.month, after.day, after.hour, after.minute).add(const Duration(minutes: 1));
  return reminderOccurrenceOnOrAfter(anchor, repeatType, t);
}

/// Next occurrence after [from] for a series anchored at [from].
/// Kept for callers without an anchor; prefer [reminderOccurrenceAfter].
DateTime nextReminderOccurrence(DateTime from, String repeatType) {
  if (repeatType == 'none') return from;
  return reminderOccurrenceAfter(from, repeatType, from);
}

/// Bill reminder times (one per "days before" setting) for the upcoming
/// cycles, skipping the cycle that is already [paidCycle]. At most [perDay]
/// future times per setting.
List<({int dayIndex, DateTime when})> billReminderTimes({
  required int dueDay,
  required List<int> daysBefore,
  required int hour,
  required int minute,
  String? paidCycle,
  DateTime? now,
  int perDay = 2,
}) {
  final ref = now ?? DateTime.now();
  final result = <({int dayIndex, DateTime when})>[];
  for (int i = 0; i < daysBefore.length && i < 8; i++) {
    var found = 0;
    for (int offset = -1; offset <= 3 && found < perDay; offset++) {
      final due = billDueDate(ref.year, ref.month + offset, dueDay);
      if (paidCycle != null && billCycleKey(due) == paidCycle) continue;
      final when = DateTime(due.year, due.month, due.day - daysBefore[i], hour, minute);
      if (!when.isAfter(ref)) continue;
      result.add((dayIndex: i, when: when));
      found++;
    }
  }
  return result;
}

// ── Notification actions without the app UI ─────────────────────────────────

/// Handles notification action buttons when the app's providers are not
/// available (background isolate / app not running). When the app is running,
/// [NotificationService.foregroundActionHandler] is used instead so the
/// in-memory reminders state stays in sync with the file.
@pragma('vm:entry-point')
void onBackgroundNotificationAction(NotificationResponse response) async {
  if (response.actionId == null || response.payload == null) return;
  final String action = response.actionId!;
  final String reminderId = response.payload!;

  // Initialize timezone just in case
  tz.initializeTimeZones();

  final service = VaultService();
  final data = await service.loadVaultData();
  final remindersList = data['reminders'] as List? ?? [];
  final reminders = <Reminder>[];
  for (final r in remindersList) {
    try {
      reminders.add(Reminder.fromJson(Map<String, dynamic>.from(r)));
    } catch (_) {
      return; // never rewrite the file if any reminder can't be read
    }
  }

  final index = reminders.indexWhere((r) => r.id == reminderId);
  if (index == -1) return;

  Reminder reminder = reminders[index];
  final anchor = reminder.referenceDate ?? reminder.dateTime;

  if (action == 'action_done') {
    if (reminder.repeatType != 'none') {
      // Roll the same reminder forward to the next occurrence after now.
      final after = reminder.dateTime.isAfter(DateTime.now()) ? reminder.dateTime : DateTime.now();
      reminder = reminder.copyWith(
        dateTime: reminderOccurrenceAfter(anchor, reminder.repeatType, after),
        isDismissed: false,
        referenceDate: anchor,
      );
      reminders[index] = reminder;
      await NotificationService().scheduleReminderFor(reminder);
    } else {
      reminders[index] = reminder.copyWith(isDismissed: true);
      await NotificationService().cancelReminderNotification(reminder.id);
    }
  } else if (action == 'action_snooze_1h' || action == 'action_snooze_1d') {
    // Snoozing moves only this occurrence; the series keeps its anchor.
    reminder = reminder.copyWith(
      dateTime: DateTime.now().add(action == 'action_snooze_1h' ? const Duration(hours: 1) : const Duration(days: 1)),
      isDismissed: false,
      referenceDate: anchor,
    );
    reminders[index] = reminder;
    await NotificationService().scheduleReminderFor(reminder);
  } else {
    return;
  }

  // Save back to vault
  await service.saveReminders(reminders);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Set by the running app so notification actions update the reminders
  /// provider directly (instead of editing the file behind its back, which the
  /// next in-app save would overwrite).
  static Future<void> Function(String actionId, String reminderId)? foregroundActionHandler;

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final handler = foregroundActionHandler;
        if (handler != null && response.actionId != null && response.payload != null) {
          await handler(response.actionId!, response.payload!);
        } else {
          onBackgroundNotificationAction(response);
        }
      },
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
    );

    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.requestExactAlarmsPermission();
      }
    }
  }

  // ── Bills ──────────────────────────────────────────────────────────────────

  static int _billLegacyId(String billId, int i) => (billId.hashCode & 0x0FFFFFFF) + (i * 0x10000000);
  static int _billSlotId(String billId, int slot) => (billId.hashCode & 0x00FFFFFF) | ((8 + slot) << 24);
  static const int _billSlots = 16; // 8 reminder days × 2 cycles ahead

  /// Schedules a bill's reminders for its next two billing cycles, skipping a
  /// cycle that is already paid. Each reminder is a one-off notification on
  /// the right date (month lengths handled); [rescheduleAllNotifications] tops
  /// them up on every app start.
  Future<void> scheduleBillNotificationsFor(Bill bill, {bool askPermission = true}) {
    return scheduleBillNotifications(
      billId: bill.id,
      title: 'Bill Reminder: ${bill.title}',
      dueDay: bill.dueDate,
      reminderDaysBeforeList: bill.reminderDaysBeforeList,
      hour: bill.reminderHour,
      minute: bill.reminderMinute,
      enabled: bill.reminderEnabled,
      paidCycle: bill.isPaid ? bill.paidCycle : null,
      askPermission: askPermission,
    );
  }

  Future<void> scheduleBillNotifications({
    required String billId,
    required String title,
    required int dueDay,
    required List<int> reminderDaysBeforeList,
    required int hour,
    required int minute,
    required bool enabled,
    String? paidCycle,
    bool askPermission = true,
  }) async {
    // 1. Always cancel all existing notifications for this bill
    await cancelBillNotifications(billId);

    // 2. If reminders are disabled, do not schedule any new ones
    if (!enabled) return;

    if (askPermission) await requestPermissions();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'bills_channel',
        'Bills Reminders',
        channelDescription: 'Reminders for upcoming bills',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    final times = billReminderTimes(
      dueDay: dueDay,
      daysBefore: reminderDaysBeforeList,
      hour: hour,
      minute: minute,
      paidCycle: paidCycle,
    );
    final perDayCount = <int, int>{};
    for (final t in times) {
      final n = perDayCount.update(t.dayIndex, (v) => v + 1, ifAbsent: () => 0);
      final daysBefore = reminderDaysBeforeList[t.dayIndex];
      final body = daysBefore == 0
          ? 'Your bill is due today!'
          : 'Your bill is due in $daysBefore ${daysBefore == 1 ? 'day' : 'days'}!';
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          _billSlotId(billId, t.dayIndex * 2 + n),
          title,
          body,
          tz.TZDateTime.from(t.when, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        print('Could not schedule bill reminder: $e');
      }
    }
  }

  Future<void> cancelBillNotifications(String billId) async {
    for (int i = 0; i < 8; i++) {
      await flutterLocalNotificationsPlugin.cancel(_billLegacyId(billId, i)); // old monthly repeats
    }
    for (int slot = 0; slot < _billSlots; slot++) {
      await flutterLocalNotificationsPlugin.cancel(_billSlotId(billId, slot));
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  // ── Reminders ──────────────────────────────────────────────────────────────

  static int _reminderSlotId(String id, int slot) => (id.hashCode & 0x00FFFFFF) | ((32 + slot) << 24);
  static const int _reminderSlots = 14; // 1 snooze + 13 monthly occurrences

  Future<void> scheduleReminderFor(Reminder r) => scheduleReminderNotification(
        id: r.id,
        title: r.title,
        body: r.description.isNotEmpty ? r.description : 'You have a reminder!',
        dateTime: r.dateTime,
        repeatType: r.repeatType,
        anchor: r.referenceDate,
      );

  /// Schedules a reminder. For repeating reminders [anchor] is the original
  /// date/time of the series; if [dateTime] is not on the series (snoozed),
  /// it fires once at [dateTime] and the series carries on unchanged.
  Future<void> scheduleReminderNotification({
    required String id,
    required String title,
    required String body,
    required DateTime dateTime,
    required String repeatType,
    DateTime? anchor,
  }) async {
    await cancelReminderNotification(id);

    final now = DateTime.now();
    final type = repeatType.toLowerCase();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders_channel',
        'Task Reminders',
        channelDescription: 'General reminders for tasks and notes',
        importance: Importance.max,
        priority: Priority.high,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('action_done', 'Done', showsUserInterface: true),
          AndroidNotificationAction('action_snooze_1h', 'Snooze 1h', showsUserInterface: true),
          AndroidNotificationAction('action_snooze_1d', 'Snooze 1d', showsUserInterface: true),
        ],
      ),
    );

    Future<void> schedule(int notifId, DateTime when, {DateTimeComponents? match}) async {
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          notifId,
          title,
          body,
          tz.TZDateTime.from(when, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: match,
          payload: id, // so the action handler knows which reminder
        );
      } catch (e) {
        print('Could not schedule reminder: $e');
      }
    }

    if (type != 'daily' && type != 'weekly' && type != 'monthly') {
      if (dateTime.isAfter(now)) await schedule(id.hashCode, dateTime);
      return; // past one-off reminders are not scheduled
    }

    final seriesAnchor = anchor ?? dateTime;
    String minuteKey(DateTime d) => '${d.year}-${d.month}-${d.day} ${d.hour}:${d.minute}';
    final onSeries = minuteKey(reminderOccurrenceOnOrAfter(seriesAnchor, type, dateTime)) == minuteKey(dateTime);

    // Snoozed occurrence: fire once at the snoozed time.
    if (!onSeries && dateTime.isAfter(now)) {
      await schedule(_reminderSlotId(id, 0), dateTime);
    }

    // Next regular occurrence of the series.
    final from = onSeries ? dateTime : dateTime.add(const Duration(minutes: 1));
    var next = reminderOccurrenceOnOrAfter(seriesAnchor, type, from);
    if (!next.isAfter(now)) next = reminderOccurrenceAfter(seriesAnchor, type, now);

    if (type == 'daily' || type == 'weekly') {
      await schedule(id.hashCode, next, match: type == 'daily' ? DateTimeComponents.time : DateTimeComponents.dayOfWeekAndTime);
    } else {
      // Monthly: one-off notifications so short months and the 29th–31st work
      // (a repeating "day of month" alarm never fires on the 31st in April).
      for (int k = 0; k < _reminderSlots - 1; k++) {
        await schedule(_reminderSlotId(id, 1 + k), next);
        next = reminderOccurrenceAfter(seriesAnchor, type, next);
      }
    }
  }

  Future<void> cancelReminderNotification(String reminderId) async {
    await flutterLocalNotificationsPlugin.cancel(reminderId.hashCode);
    for (int slot = 0; slot < _reminderSlots; slot++) {
      await flutterLocalNotificationsPlugin.cancel(_reminderSlotId(reminderId, slot));
    }
  }
}
