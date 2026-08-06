import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

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

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    _isInitialized = true;
  }

  Future<void> scheduleExpiryReminder(String docId, String title, DateTime expiryDate) async {
    final id = docId.hashCode & 0x0FFFFFFF;
    
    // Schedule 7 days before
    final reminderDate7 = expiryDate.subtract(const Duration(days: 7));
    if (reminderDate7.isAfter(DateTime.now())) {
      await _schedule(id, 'Document Expiry Warning', '$title expires in 7 days!', reminderDate7);
    }
    
    // Schedule 1 day before
    final reminderDate1 = expiryDate.subtract(const Duration(days: 1));
    if (reminderDate1.isAfter(DateTime.now())) {
      await _schedule(id + 1, 'Document Expiry Alert', '$title expires tomorrow!', reminderDate1);
    }
  }

  Future<void> _schedule(int id, String title, String body, DateTime date) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'expiry_channel', 'Expiry Reminders',
      importance: Importance.max, priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    final scheduledDate = tz.TZDateTime.from(date, tz.local);
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id, title, body, scheduledDate, platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelReminders(String docId) async {
    final id = docId.hashCode & 0x0FFFFFFF;
    await flutterLocalNotificationsPlugin.cancel(id);
    await flutterLocalNotificationsPlugin.cancel(id + 1);
  }
}
