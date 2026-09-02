import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'currency_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _dailyReminderId = 21001;
  static const int _travelReturnId = 21002;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    // 專題目前以台灣使用者為主；不用額外套件即可讓排程時間與台灣本地時間一致。
    tz.setLocalLocation(tz.getLocation('Asia/Taipei'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(settings);
    _initialized = true;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'pawpay_reminders',
      'PawPay 提醒',
      channelDescription: '每日記帳與旅行幣別提醒',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> syncFromPreferences() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    await initialize();
    final prefs = await SharedPreferences.getInstance();

    final dailyEnabled = prefs.getBool('setting_daily_reminder') ?? true;
    final dailyTime = prefs.getString('setting_daily_reminder_time') ?? '21:00';
    if (dailyEnabled) {
      final parts = dailyTime.split(':');
      await scheduleDailyReminder(
        hour: int.tryParse(parts.first) ?? 21,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
    } else {
      await cancelDailyReminder();
    }

    final travelEnabled = prefs.getBool(CurrencyService.travelEnabledKey) ?? false;
    final rawEnd = prefs.getString(CurrencyService.travelEndDateKey);
    final endDate = rawEnd == null ? null : DateTime.tryParse(rawEnd);
    if (travelEnabled && endDate != null) {
      final defaultCode = await CurrencyService.instance.getDefaultCurrencyCode();
      await scheduleTravelReturnReminder(
        endDate: endDate,
        defaultCurrencyLabel: CurrencyService.labelForCode(defaultCode),
      );
    } else {
      await cancelTravelReturnReminder();
    }
  }

  Future<void> scheduleDailyReminder({required int hour, required int minute}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    await initialize();

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      _dailyReminderId,
      '今天記帳了嗎？',
      '花一分鐘補登今天的支出與收入，任務進度也會一起更新。',
      next,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_accounting_reminder',
    );
  }

  Future<void> cancelDailyReminder() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    await initialize();
    await _plugin.cancel(_dailyReminderId);
  }

  Future<void> scheduleTravelReturnReminder({
    required DateTime endDate,
    required String defaultCurrencyLabel,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    await initialize();

    final returnDay = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));
    var scheduled = tz.TZDateTime(
      tz.local,
      returnDay.year,
      returnDay.month,
      returnDay.day,
      10,
    );
    final now = tz.TZDateTime.now(tz.local);
    if (!scheduled.isAfter(now)) {
      scheduled = now.add(const Duration(minutes: 1));
    }

    await _plugin.zonedSchedule(
      _travelReturnId,
      '旅行幣別期間已結束',
      '記得把顯示幣別切回 $defaultCurrencyLabel。',
      scheduled,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'travel_currency_return',
    );
  }

  Future<void> cancelTravelReturnReminder() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    await initialize();
    await _plugin.cancel(_travelReturnId);
  }
}