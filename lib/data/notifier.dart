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
        title: '${e.kind.label} в ${fmtTime(e.startsAt)}',
        body: '$day$who${e.placeLabel}',
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: _details,
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
}
