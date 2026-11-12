import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../widgets/common.dart';
import 'models.dart';

/// Известия на телефона за напомнянията преди събитие.
/// Планират се в Android предварително, затова идват и при затворено
/// приложение и след рестарт на телефона.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Напомняния за събития',
      channelDescription: 'Напомняне преди кръщене, венчавка, служба и други събития',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
  );

  /// Аларма: звук на будилник, звъни, докато не се спре, показва се и
  /// върху заключения екран. Отделен канал, за да има свой звук.
  static final _alarmDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'alarms_v1',
      'Аларми за събития',
      channelDescription: 'Звъни като будилник, докато не натиснете „Спри“',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 600, 800, 600, 800]),
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      // FLAG_INSISTENT: звукът се повтаря, докато известието не бъде спряно.
      additionalFlags: Int32List.fromList([4]),
      actions: const [
        AndroidNotificationAction('stop', 'Спри', cancelNotification: true),
      ],
    ),
  );

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      // Канал за известията от колеги (push) – трябва да съществува,
      // за да ги показва Android със звук.
      await _android?.createNotificationChannel(const AndroidNotificationChannel(
        'events',
        'Събития от колеги',
        description: 'Когато колега запише или промени събитие за вас',
        importance: Importance.high,
      ));
      _ready = true;
    } catch (e) {
      debugPrint('Известията не тръгнаха: $e');
    }
  }

  /// Пита за разрешение за известия (Android 13+) и за точно време.
  static Future<bool> requestPermissions() async {
    final a = _android;
    if (a == null) return false;
    final granted = await a.requestNotificationsPermission() ?? false;
    final exact = await a.canScheduleExactNotifications() ?? false;
    if (!exact) await a.requestExactAlarmsPermission();
    return granted;
  }

  /// Разрешение алармата да се показва на цял екран върху заключен телефон.
  static Future<void> requestAlarmPermissions() async {
    await requestPermissions();
    try {
      await _android?.requestFullScreenIntentPermission();
    } catch (e) {
      debugPrint('Няма разрешение за цял екран: $e');
    }
  }

  static Future<bool> notificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  /// Стабилен номер на известието от номера на събитието.
  static int _idFor(String eventId) {
    var h = 0x811c9dc5;
    for (final c in eventId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  static Future<AndroidScheduleMode> _mode() async {
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    return exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Планира (или пренасрочва) напомнянето за събитието.
  static Future<void> schedule(ChurchEvent e) async {
    if (!_ready) return;
    await cancel(e.id);
    final minutes = e.remindMinutes;
    if (minutes == null) return;
    final when = e.startsAt.subtract(Duration(minutes: minutes));
    if (!when.isAfter(DateTime.now())) return;
    final who = e.forWhom.isEmpty ? '' : '${e.forWhom} · ';
    final day = sameDay(e.startsAt, when) ? '' : '${fmtDayLong(e.startsAt)}, ';
    try {
      await _plugin.zonedSchedule(
        id: _idFor(e.id),
        title: '${e.alarm ? '⏰ ' : ''}${e.kind.label} в ${fmtTime(e.startsAt)}',
        body: '$day$who${e.placeLabel}',
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: e.alarm ? _alarmDetails : _details,
        androidScheduleMode: await _mode(),
      );
    } catch (err) {
      debugPrint('Не може да се планира напомняне: $err');
    }
  }

  static Future<void> cancel(String eventId) async {
    if (!_ready) return;
    await _plugin.cancel(id: _idFor(eventId));
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  /// Пренасрочва всички напомняния (при вход или стартиране).
  static Future<void> rescheduleAll(Iterable<ChurchEvent> events) async {
    await cancelAll();
    for (final e in events) {
      await schedule(e);
    }
  }

  /// Пробно известие след 10 секунди – за проверка, че всичко работи.
  static Future<void> test() async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      id: 1,
      title: 'Пробно напомняне',
      body: 'Така ще изглеждат напомнянията преди събитие.',
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 10)),
      notificationDetails: _details,
      androidScheduleMode: await _mode(),
    );
  }

  /// Пробна аларма след 10 секунди.
  static Future<void> testAlarm() async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      id: 2,
      title: '⏰ Пробна аларма',
      body: 'Натиснете „Спри“, за да спре звъненето.',
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 10)),
      notificationDetails: _alarmDetails,
      androidScheduleMode: await _mode(),
    );
  }

  /// Показва известие веднага (за push, докато приложението е отворено).
  static Future<void> showNow(String title, String body) async {
    if (!_ready) return;
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'events',
          'Събития от колеги',
          channelDescription: 'Когато колега запише или промени събитие за вас',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
