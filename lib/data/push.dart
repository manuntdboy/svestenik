import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notifier.dart';

/// Настройки на Firebase за push известия. Не са тайни (същите стоят във
/// всяко Android приложение); подават се при изграждането.
const _apiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '993081880916');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'kairos-6a1c7');

/// Push известия през Firebase Cloud Messaging: когато колега запише
/// събитие за вас, сървърът праща известие на телефона.
class Push {
  static bool _ready = false;
  static bool get ready => _ready;

  /// Извиква се при всяко ново известие, докато приложението е отворено,
  /// и при натискане на известие – за да се обновят данните.
  static VoidCallback? onEvent;

  static Future<void> init() async {
    if (_apiKey.isEmpty || _appId.isEmpty) {
      debugPrint('Push е изключен: няма FIREBASE_ANDROID_API_KEY / FIREBASE_APP_ID.');
      return;
    }
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      // Докато приложението е отворено, Android не показва известието само –
      // показваме го ние.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) {
          Notifier.showNow(n.title ?? 'Кайрос', n.body ?? '',
              data: m.data.map((k, v) => MapEntry(k, '$v')));
        }
        onEvent?.call();
      });
      // Натиснато известие: отваряме съответния екран.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        Notifier.opened.value = m.data.map((k, v) => MapEntry(k, '$v'));
        onEvent?.call();
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        Notifier.opened.value = initial.data.map((k, v) => MapEntry(k, '$v'));
      }
      _ready = true;
    } catch (e) {
      debugPrint('Push не тръгна: $e');
    }
  }

  /// Токенът на това устройство (за сървъра), или null.
  static Future<String?> token() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Няма push токен: $e');
      return null;
    }
  }

  static Stream<String> get tokenRefresh =>
      _ready ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  static Future<void> deleteToken() async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
