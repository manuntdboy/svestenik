import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/whats_new.dart' show buildNumber;

/// Обновяване от самото приложение: проверява последната версия за тестерите
/// (GitHub Releases, „latest“) и я изтегля и инсталира с едно натискане.
class Updater extends ChangeNotifier {
  Updater._();
  static final Updater i = Updater._();

  static const _latest = 'https://api.github.com/repos/manuntdboy/svestenik/releases/latest';

  int latestBuild = 0;
  String? apkUrl;
  DateTime? _checked;

  /// 0..100 по време на изтегляне; null – нищо не тече.
  int? progress;
  String? error;

  bool get available => buildNumber > 0 && latestBuild > buildNumber && apkUrl != null;

  /// Проверка най-много веднъж на 30 минути (или винаги с force).
  Future<void> check({bool force = false}) async {
    if (kIsWeb || !Platform.isAndroid || buildNumber == 0) return;
    if (!force && _checked != null && DateTime.now().difference(_checked!) < const Duration(minutes: 30)) return;
    _checked = DateTime.now();
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await c.getUrl(Uri.parse(_latest));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final n = int.tryParse('${j['tag_name']}'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      String? url;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = '${(a as Map)['name']}';
        if (name.endsWith('.apk')) url = '${a['browser_download_url']}';
      }
      c.close();
      if (n != latestBuild || url != apkUrl) {
        latestBuild = n;
        apkUrl = url;
        notifyListeners();
      }
    } catch (_) {
      // без интернет или GitHub не отговаря – опитваме по-късно
    }
  }

  /// Изтегля и пуска инсталирането. При проблем – отваря файла в браузъра.
  Future<void> install() async {
    final url = apkUrl;
    if (url == null || progress != null) return;
    error = null;
    progress = 0;
    notifyListeners();
    try {
      await for (final e in OtaUpdate().execute(url, destinationFilename: 'kairos-$latestBuild.apk')) {
        final st = e.status.toString().split('.').last;
        if (st == 'DOWNLOADING') {
          progress = int.tryParse(e.value ?? '') ?? progress;
          notifyListeners();
        } else if (st == 'INSTALLING' || st == 'INSTALLATION_DONE') {
          progress = null;
          notifyListeners();
        } else if (st == 'PERMISSION_NOT_GRANTED_ERROR') {
          progress = null;
          error = 'Разрешете на Кайрос да инсталира приложения (екранът се отвори) и натиснете „Обнови“ отново.';
          notifyListeners();
        } else if (st.contains('ERROR')) {
          progress = null;
          notifyListeners();
          await _browser(url);
        }
      }
    } catch (_) {
      progress = null;
      notifyListeners();
      await _browser(url);
    }
  }

  Future<void> _browser(String url) async {
    error = 'Изтеглянето продължава в браузъра – отворете файла, когато свърши.';
    notifyListeners();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
