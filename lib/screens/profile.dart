import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/notifier.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'church_code.dart';
import 'church_connect.dart';
import 'church_priests.dart';
import 'change_password.dart';
import 'creator.dart';
import 'feedback.dart';
import 'privacy.dart';
import 'my_profile.dart';
import '../widgets/whats_new.dart' show buildNumber, isTestBuild;

/// Viber на създателя за обратна връзка (само в тестовата версия).
const _feedbackViber = '+359888177738';

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
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MyProfileScreen())),
                child: const Text('Моят профил'),
              ),
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
              OutlinedButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChurchPriestsScreen(churchId: church.id))),
                child: Text('Свещеници в храма (${s.priestsOf(church.id).length})'),
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
                        'Известията са изключени. Включете ги от Настройки → Приложения → Кайрос → Известия.');
                  }
                },
                child: const Text('Пробно известие'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await Notifier.requestAlarmPermissions();
                  final on = await Notifier.notificationsEnabled();
                  if (!context.mounted) return;
                  if (on) {
                    final ok = await Notifier.testAlarm();
                    if (context.mounted) {
                      showMessage(
                          context,
                          ok
                              ? 'След 10 секунди ще звънне пробна аларма. Спира се с „Спри“.'
                              : 'Алармата не можа да се нагласи.');
                    }
                  } else {
                    showMessage(context,
                        'Известията са изключени. Включете ги от Настройки → Приложения → Кайрос → Известия.');
                  }
                },
                child: const Text('Пробна аларма'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
          icon: const Icon(Icons.key_rounded),
          label: const Text('Смени паролата'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Лични данни и поверителност'),
        ),
        const SizedBox(height: 20),
        // „За приложението“ – създател и версия. За профила на създателя
        // (решава сървърът) дълго натискане тук отваря „Кайрос в числа“.
        GestureDetector(
          onLongPress: s.isCreator
              ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreatorScreen()))
              : null,
          child: SurfaceCard(
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/logo-kairos.png', width: 52, height: 52),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('За приложението',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Кайрос${buildNumber > 0 ? ' · версия $buildNumber' : ''}',
                      style: TextStyle(fontSize: 15, color: p.textMuted)),
                  const SizedBox(height: 4),
                  const Text('Димитър Костадинов (създател)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        ),
        // Обратна връзка: в приложението (до създателя), а в тестовата версия – и Viber.
        const SizedBox(height: 12),
        Material(
          color: const Color(0xFF7360F2).withValues(alpha: .12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF7360F2), width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => FeedbackScreen(viber: isTestBuild ? _feedbackViber : null))),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF7360F2), size: 30),
                SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Обратна връзка', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Грешка, идея или въпрос – пишете на създателя.', style: TextStyle(fontSize: 15)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => s.logout(),
          child: const Text('Изход'),
        ),
        const SizedBox(height: 16),
        Text('Тестова версия · данните са на сървъра в ЕС (Франкфурт).',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.textMuted)),
      ],
    );
  }
}
