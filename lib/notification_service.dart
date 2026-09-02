import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'vault_service.dart';
import 'models.dart';

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
  final reminders = remindersList.map((r) => Reminder.fromJson(r)).toList();

  final index = reminders.indexWhere((r) => r.id == reminderId);
  if (index == -1) return;

  Reminder reminder = reminders[index];

  if (action == 'action_done') {
    if (reminder.repeatType != 'none') {
      // Calculate next date
      DateTime nextDate = reminder.dateTime;
      if (reminder.repeatType == 'daily') {
        nextDate = nextDate.add(const Duration(days: 1));
      } else if (reminder.repeatType == 'weekly') {
        nextDate = nextDate.add(const Duration(days: 7));
      } else if (reminder.repeatType == 'monthly') {
        nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day);
      }
      final nextReminder = Reminder(
        title: reminder.title,
        description: reminder.description,
        dateTime: nextDate,
        isDismissed: false,
        repeatType: reminder.repeatType,
      );
      reminders.add(nextReminder);
      
      // Schedule the next one
      NotificationService().scheduleReminderNotification(
        id: nextReminder.id,
        title: nextReminder.title,
        body: nextReminder.description.isNotEmpty ? nextReminder.description : 'You have a reminder!',
        dateTime: nextReminder.dateTime,
        repeatType: nextReminder.repeatType,
      );
    }
    
    // Mark old as dismissed
    reminders[index] = reminder.copyWith(isDismissed: true);
    // Cancel its notification just in case
    NotificationService().cancelReminderNotification(reminder.id);
  } 
  else if (action == 'action_snooze_1h') {
    reminder = reminder.copyWith(
      dateTime: DateTime.now().add(const Duration(hours: 1)),
      isDismissed: false,
    );
    reminders[index] = reminder;
    NotificationService().scheduleReminderNotification(
      id: reminder.id,
      title: reminder.title,
      body: reminder.description.isNotEmpty ? reminder.description : 'You have a reminder!',
      dateTime: reminder.dateTime,
      repeatType: reminder.repeatType,
    );
  } 
  else if (action == 'action_snooze_1d') {
    reminder = reminder.copyWith(
      dateTime: DateTime.now().add(const Duration(days: 1)),
      isDismissed: false,
    );
    reminders[index] = reminder;
    NotificationService().scheduleReminderNotification(
      id: reminder.id,
      title: reminder.title,
      body: reminder.description.isNotEmpty ? reminder.description : 'You have a reminder!',
      dateTime: reminder.dateTime,
      repeatType: reminder.repeatType,
    );
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
        // App is foreground/background
        onBackgroundNotificationAction(response);
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

  Future<void> scheduleMonthlyBillNotification({
    required int id,
    required String title,
    required String body,
    required int dueDay,
    required int daysBefore,
    required int hour,
    required int minute,
  }) async {
    await flutterLocalNotificationsPlugin.cancel(id); // Cancel existing if any

    final now = tz.TZDateTime.now(tz.local);
    int targetDay = dueDay - daysBefore;
    
    // Handle wrap around for previous month
    tz.TZDateTime scheduledDate;
    if (targetDay <= 0) {
      // Due early in month, reminder is late previous month
      final prevMonth = now.month == 1 ? 12 : now.month - 1;
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      final daysInPrevMonth = DateTime(prevYear, prevMonth + 1, 0).day;
      scheduledDate = tz.TZDateTime(tz.local, prevYear, prevMonth, daysInPrevMonth + targetDay, hour, minute);
    } else {
      scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, targetDay, hour, minute);
    }

    if (scheduledDate.isBefore(now)) {
      // If the date has already passed this month, schedule for next month
      if (targetDay <= 0) {
        final daysInThisMonth = DateTime(now.year, now.month + 1, 0).day;
        scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, daysInThisMonth + targetDay, hour, minute);
      } else {
        scheduledDate = tz.TZDateTime(tz.local, now.year, now.month + 1, targetDay, hour, minute);
      }
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'bills_channel',
      'Bills Reminders',
      channelDescription: 'Reminders for upcoming bills',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime, // Repeat monthly
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
  }) async {
    // 1. Always cancel all existing notifications for this bill
    await cancelBillNotifications(billId);

    // 2. If reminders are disabled, do not schedule any new ones
    if (!enabled) return;

    // 3. Request permissions just in case
    await requestPermissions();

    // 4. Schedule a notification for each day before in the list
    final baseId = billId.hashCode & 0x0FFFFFFF;
    for (int i = 0; i < reminderDaysBeforeList.length; i++) {
      final daysBefore = reminderDaysBeforeList[i];
      final notificationId = baseId + (i * 0x10000000);
      
      final String suffix = daysBefore == 1 ? 'day' : 'days';
      final String body = daysBefore == 0 
          ? 'Your bill is due today!'
          : 'Your bill is due in $daysBefore $suffix!';

      await scheduleMonthlyBillNotification(
        id: notificationId,
        title: title,
        body: body,
        dueDay: dueDay,
        daysBefore: daysBefore,
        hour: hour,
        minute: minute,
      );
    }
  }

  Future<void> cancelBillNotifications(String billId) async {
    final baseId = billId.hashCode & 0x0FFFFFFF;
    for (int i = 0; i < 8; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + (i * 0x10000000));
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> scheduleReminderNotification({
    required String id,
    required String title,
    required String body,
    required DateTime dateTime,
    required String repeatType,
  }) async {
    await cancelReminderNotification(id);

    final scheduledDate = tz.TZDateTime.from(dateTime, tz.local);
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local)) && repeatType == 'none') {
      return; // Do not schedule past non-repeating reminders
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'reminders_channel',
      'Task Reminders',
      channelDescription: 'General reminders for tasks and notes',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_done',
          'Done',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'action_snooze_1h',
          'Snooze 1h',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'action_snooze_1d',
          'Snooze 1d',
          showsUserInterface: true,
        ),
      ],
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    DateTimeComponents? matchDateTimeComponents;
    switch (repeatType.toLowerCase()) {
      case 'daily':
        matchDateTimeComponents = DateTimeComponents.time;
        break;
      case 'weekly':
        matchDateTimeComponents = DateTimeComponents.dayOfWeekAndTime;
        break;
      case 'monthly':
        matchDateTimeComponents = DateTimeComponents.dayOfMonthAndTime;
        break;
      default:
        matchDateTimeComponents = null;
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id.hashCode,
      title,
      body,
      scheduledDate,
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchDateTimeComponents,
      payload: id, // Pass ID in payload so background action knows which reminder
    );
  }

  Future<void> cancelReminderNotification(String reminderId) async {
    await flutterLocalNotificationsPlugin.cancel(reminderId.hashCode);
  }
}
