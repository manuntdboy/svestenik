import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'data/app_state.dart';
import 'data/notifier.dart';
import 'screens/church_connect.dart';
import 'screens/login.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('bg');
  Intl.defaultLocale = 'bg';
  await Notifier.init();
  final state = AppState();
  await state.load();
  // Обновява напомнянията (например след промяна на версията).
  if (state.isLoggedIn) state.rescheduleReminders();
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
        return MediaQuery(
          data: mq.copyWith(
            alwaysUse24HourFormat: true,
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * s.textScale),
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
    if (!s.isLoggedIn) return const LoginScreen();
    if (s.currentChurch == null) return const ChurchConnectScreen();
    // Ключът кара таблото да започне отначало при смяна на потребител или храм.
    return Shell(key: ValueKey('${s.currentUser!.id}-${s.currentChurch!.id}'));
  }
}
