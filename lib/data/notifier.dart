import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../widgets/common.dart';
import 'models.dart';

/// Известия на телефона за напомнянията преди събитие.
/// Планират се в Android предварително, затова идват и при затворено
/// приложение и след рестарт на телефона.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Данните на натиснато известие (push или наше) – приложението отваря
  /// съответния екран. Задава се тук и в push.dart, чете се в Shell.
  static final opened = ValueNotifier<Map<String, String>?>(null);
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
        onDidReceiveNotificationResponse: (r) {
          final payload = r.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            opened.value = Map<String, String>.from(jsonDecode(payload) as Map);
          } catch (_) {}
        },
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
    try {
      await Alarm.init();
      _alarmReady = true;
    } catch (e) {
      debugPrint('Алармите не тръгнаха: $e');
    }
  }

  static bool _alarmReady = false;

  /// Истинска аларма (пакет alarm): свири камбанен звън на силата на
  /// будилника, в цикъл, с вибрация и на цял екран, докато не се спре.
  static Future<bool> _setAlarm(int id, DateTime when, String title, String body) async {
    if (!_alarmReady) return false;
    try {
      return await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: when,
          assetAudioPath: 'assets/alarm.mp3',
          loopAudio: true,
          vibrate: true,
          warningNotificationOnKill: false,
          androidFullScreenIntent: true,
          androidStopAlarmOnTermination: false,
          allowAlarmOverlap: true,
          volumeSettings: VolumeSettings.fade(
            volume: 0.9,
            fadeDuration: const Duration(seconds: 3),
            volumeEnforced: true,
          ),
          notificationSettings: NotificationSettings(
            title: title,
            body: body,
            stopButton: 'Спри',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Не може да се нагласи аларма: $e');
      return false;
    }
  }

  /// Спира звъняща аларма (бутонът „Спри“ на екрана на алармата).
  static Future<void> stopAlarm(int id) async {
    if (_alarmReady) await Alarm.stop(id);
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
    final title = '${e.kind.label} в ${fmtTime(e.startsAt)}';
    final body = '$day$who${e.placeLabel}';
    if (e.alarm && await _setAlarm(_idFor(e.id), when, '⏰ $title', body)) return;
    try {
      await _plugin.zonedSchedule(
        id: _idFor(e.id),
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: await _mode(),
      );
    } catch (err) {
      debugPrint('Не може да се планира напомняне: $err');
    }
  }

  static Future<void> cancel(String eventId) async {
    if (_alarmReady) await Alarm.stop(_idFor(eventId));
    if (!_ready) return;
    await _plugin.cancel(id: _idFor(eventId));
  }

  static Future<void> cancelAll() async {
    if (_alarmReady) await Alarm.stopAll();
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  /// Пренасрочва всички напомняния (при вход или стартиране).
  static Future<void> rescheduleAll(Iterable<ChurchEvent> events, {Iterable<Duty> duties = const []}) async {
    await cancelAll();
    for (final e in events) {
      await schedule(e);
    }
    for (final d in duties) {
      await scheduleDuty(d);
    }
  }

  /// Напомняне вечерта преди дежурството (19:00): „От утре сте дежурен“.
  static Future<void> scheduleDuty(Duty d) async {
    if (!_ready) return;
    final day = d.start.subtract(const Duration(days: 1));
    final when = DateTime(day.year, day.month, day.day, 19);
    if (!when.isAfter(DateTime.now())) return;
    final f = DateFormat('d MMMM', 'bg');
    final period = d.start == d.end ? f.format(d.start) : '${f.format(d.start)} – ${f.format(d.end)}';
    try {
      await _plugin.zonedSchedule(
        id: _idFor('duty:${d.id}'),
        title: 'От утре сте дежурен',
        body: period,
        payload: jsonEncode({'type': 'duty', 'church_id': d.churchId}),
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: await _mode(),
      );
    } catch (err) {
      debugPrint('Не може да се планира напомняне за дежурство: $err');
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
  static Future<bool> testAlarm() => _setAlarm(
        2,
        DateTime.now().add(const Duration(seconds: 10)),
        '⏰ Пробна аларма',
        'Натиснете „Спри“, за да спре звъненето.',
      );

  /// Показва известие веднага (за push, докато приложението е отворено).
  static Future<void> showNow(String title, String body, {Map<String, String>? data}) async {
    if (!_ready) return;
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      payload: data == null ? null : jsonEncode(data),
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
