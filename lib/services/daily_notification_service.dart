import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'database_helper.dart';

class DailyNotificationService {
  DailyNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const int _dailyReminderId = 20260608;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    // 這份專題目前主要是台灣使用情境；排程通知用台北時區，避免模擬器/後端時區不同步。
    tz.setLocalLocation(tz.getLocation('Asia/Taipei'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    await _requestNotificationPermission();
    _initialized = true;
  }

  static Future<void> _requestNotificationPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static TimeOfDay parseTime(String text) {
    final parts = text.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 21,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  static DateTime _dateAt(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  static Future<void> cancelDailyReminder() async {
    await initialize();
    await _plugin.cancel(_dailyReminderId);
  }

  static Future<void> scheduleNextDailyReminder() async {
    try {
      await initialize();
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('setting_daily_reminder') ?? true;
      await _plugin.cancel(_dailyReminderId);
      if (!enabled) return;

      final reminderTime = parseTime(prefs.getString('setting_daily_reminder_time') ?? '21:00');
      final now = DateTime.now();

      DateTime target = _dateAt(now, reminderTime);
      if (!target.isAfter(now)) {
        target = _dateAt(now.add(const Duration(days: 1)), reminderTime);
      }

      // 如果排程目標日已經有記帳，就往後找下一個沒有紀錄的日子。
      for (int i = 0; i < 7; i++) {
        var hasRecord = false;
        try {
          hasRecord = await DatabaseHelper.instance.hasTransactionsOnDate(target);
        } catch (e) {
          debugPrint('每日提醒查詢記帳狀態失敗，仍保留通知排程：$e');
        }
        if (!hasRecord) break;
        target = _dateAt(target.add(const Duration(days: 1)), reminderTime);
      }

      await _plugin.zonedSchedule(
        _dailyReminderId,
        '今天還沒記帳嗎？',
        '打開 AI 記帳補登一下，讓月底統計更完整。',
        tz.TZDateTime.from(target, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_accounting_reminder',
            '每日記帳提醒',
            channelDescription: '提醒使用者每天補登收入與支出',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('每日提醒通知排程失敗：$e');
    }
  }
}
