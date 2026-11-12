import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/notifier.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'church_code.dart';
import 'church_connect.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final u = s.currentUser!;
    final church = s.currentChurch!;

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const Text('Профил',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(u.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text('@${u.username}', style: TextStyle(fontSize: 16, color: p.textMuted)),
              if (u.email.isNotEmpty)
                Text(u.email, style: TextStyle(fontSize: 16, color: p.textMuted)),
            ],
          ),
        ),
        heading('Храм'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(church.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(church.place, style: TextStyle(fontSize: 15, color: p.textMuted)),
              Text(s.isManagerOf(church.id) ? 'Вие сте председател' : 'Свещеник',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChurchCodeScreen(churchId: church.id))),
                child: Text('Код за присъединяване: ${church.joinCode}'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ChurchConnectScreen(pushed: true))),
                child: const Text('Добави още един храм'),
              ),
            ],
          ),
        ),
        heading('Тема'),
        SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(44, 52),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Като телефона')),
            ButtonSegment(value: ThemeMode.light, label: Text('Светла')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Тъмна')),
          ],
          selected: {s.themeMode},
          onSelectionChanged: (v) => s.setThemeMode(v.first),
        ),
        heading('Размер на текста'),
        SegmentedButton<double>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(44, 52),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          segments: const [
            ButtonSegment(value: 1.0, label: Text('Обичаен')),
            ButtonSegment(value: 1.15, label: Text('Голям')),
            ButtonSegment(value: 1.3, label: Text('Много голям')),
          ],
          selected: {s.textScale},
          onSelectionChanged: (v) => s.setTextScale(v.first),
        ),
        heading('Напомняния'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'Напомнянията идват като известия на телефона, дори когато приложението е затворено.',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await Notifier.requestPermissions();
                  final on = await Notifier.notificationsEnabled();
                  if (!context.mounted) return;
                  if (on) {
                    await Notifier.test();
                    if (context.mounted) {
                      showMessage(context, 'След 10 секунди ще дойде пробно известие.');
                    }
                  } else {
                    showMessage(context,
                        'Известията са изключени. Включете ги от Настройки → Приложения → Свещеник → Известия.');
                  }
                },
                child: const Text('Пробно известие'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => s.logout(),
          child: const Text('Изход'),
        ),
        const SizedBox(height: 12),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () async {
            final ok = await confirm(
                context,
                'Изтриване на всички данни',
                'Ще се изтрият всички профили, храмове и събития от този телефон. '
                    'Това е само за тестове.',
                'Изтрий всичко');
            if (ok) await s.wipeAll();
          },
          child: const Text('Изтрий всички данни (тест)'),
        ),
        const SizedBox(height: 8),
        Text('Тестова версия 0.1 · данните са само на този телефон.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.textMuted)),
      ],
    );
  }
}
