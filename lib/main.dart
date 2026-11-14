import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/app_state.dart';
import 'data/error_report.dart';
import 'data/notifier.dart';
import 'data/push.dart';
import 'screens/change_password.dart';
import 'screens/church_connect.dart';
import 'screens/login.dart';
import 'screens/privacy.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('bg');
  Intl.defaultLocale = 'bg';
  await Notifier.init();
  await Push.init();
  if (!supabaseConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  ErrorReport.install();
  final state = AppState();
  await state.load();
  runApp(AppScope(state: state, child: const SvestenikApp()));
}

class SvestenikApp extends StatelessWidget {
  const SvestenikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return MaterialApp(
      title: 'Кайрос',
      debugShowCheckedModeBanner: false,
      locale: const Locale('bg'),
      supportedLocales: const [Locale('bg')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: s.themeMode,
      theme: buildTheme(Palette.light),
      darkTheme: buildTheme(Palette.darkP),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Шрифтът се съобразява с ширината на екрана: на тесни телефони
        // (или при голям системен шрифт) се смалява, за да не се чупят
        // бутоните на два реда. Основа – 400 логически точки ширина.
        final widthFactor = (mq.size.width / 400).clamp(0.8, 1.0);
        // Системният шрифт се приема до 1.0× на тесен екран (320) и до 1.3× на широк (400+);
        // настройката „Размер на текста“ в Кайрос се прилага отгоре.
        final systemCap = 1.0 + (widthFactor - 0.8) * 1.5;
        final scale = mq.textScaler.scale(1).clamp(0.8, systemCap) * s.textScale * widthFactor;
        return MediaQuery(
          data: mq.copyWith(
            alwaysUse24HourFormat: true,
            textScaler: TextScaler.linear(scale.toDouble()),
          ),
          child: child!,
        );
      },
      home: const RootGate(),
    );
  }
}

/// Избира началния екран според състоянието: вход, свързване с храм или табло.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.loading) {
      return const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Зареждане…', style: TextStyle(fontSize: 18)),
          ]),
        ),
      );
    }
    if (!s.isLoggedIn) return const LoginScreen();
    if (s.currentUser?.suspended == true) return const _SuspendedScreen();
    if (s.mustChangePassword) return const ChangePasswordScreen(forced: true);
    if (s.needsPrivacy) return const PrivacyConsentScreen();
    if (s.currentChurch == null) return const ChurchConnectScreen();
    // Ключът кара таблото да започне отначало при смяна на потребител или храм.
    return Shell(key: ValueKey('${s.currentUser!.id}-${s.currentChurch!.id}'));
  }
}

/// Показва се само ако приложението е изградено без адрес на сървъра.
class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Тази версия е изградена без връзка към сървъра (липсват SUPABASE_URL '
                'и SUPABASE_PUBLISHABLE_KEY в GitHub Secrets).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ),
      );
}

/// Профилът е временно спрян от създателя.
class _SuspendedScreen extends StatelessWidget {
  const _SuspendedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.pause_circle_rounded, size: 56),
            const SizedBox(height: 16),
            const Text('Профилът е временно спрян', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text('Свържете се с председателя на храма или със създателя на Кайрос.', style: TextStyle(fontSize: 17)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => AppScope.read(context).logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Изход'),
            ),
          ]),
        ),
      ),
    );
  }
}
