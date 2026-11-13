import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/whats_new.dart' show buildNumber;

/// Изпраща кратко описание на грешка в приложението на сървъра (без лични
/// данни) – създателят го вижда в „Кайрос в числа“ → „Грешки“.
class ErrorReport {
  static final Set<String> _sent = {};
  static int _count = 0;
  static DateTime? _lastPush;

  /// Последният отворен екран – за по-лесно намиране на грешката.
  static String screen = '';

  static void install() {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      prev?.call(d);
      send(d.exceptionAsString(), d.stack);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      send(e.toString(), st);
      return true;
    };
  }

  static void send(String message, StackTrace? stack) {
    // Грешки при липса на интернет не са грешки на приложението.
    final low = message.toLowerCase();
    if (low.contains('socketexception') || low.contains('failed host lookup') || low.contains('connection')) return;
    final key = message.length > 200 ? message.substring(0, 200) : message;
    if (_count >= 10 || !_sent.add(key)) return;
    _count++;
    unawaited(_post(message, stack));
  }

  static Future<void> _post(String message, StackTrace? stack) async {
    try {
      final db = Supabase.instance.client;
      if (db.auth.currentUser == null) return;
      final st = (stack?.toString() ?? '').split('\n').take(12).join('\n');
      final id = await db.rpc('report_error', params: {
        'p_build': buildNumber,
        'p_screen': screen,
        'p_message': message.length > 600 ? message.substring(0, 600) : message,
        'p_stack': st,
      });
      final now = DateTime.now();
      if (id != null && (_lastPush == null || now.difference(_lastPush!).inMinutes >= 30)) {
        _lastPush = now;
        await db.functions.invoke('notify', body: {'type': 'creator_event', 'kind': 'error'});
      }
    } catch (_) {}
  }
}
