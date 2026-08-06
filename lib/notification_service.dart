import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:io';

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
        // Handle notification tap
      },
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
}
