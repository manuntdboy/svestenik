import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Версия на текста за личните данни. При промяна на текста се вдига –
/// тогава всички го приемат отново.
const kPrivacyVersion = 1;

const _sections = <(String, String)>[
  (
    'Кой обработва данните',
    'Кайрос е създаден от Димитър Костадинов. Приложението служи за организиране '
        'на работата в храма – календар, почивки, дежурства, каса и склад.'
  ),
  (
    'Какво пазим',
    'Име, сан и потребителско име; имейл (само за вход и за помощ при забравена парола – не се '
        'показва на никого); по желание: телефон, три имена, дата на раждане, дата на ръкополагане, '
        'имен ден и снимка. Пазим и това, което въвеждате в приложението: събития, почивки, '
        'дежурства, записи в касата и склада.'
  ),
  (
    'Кой ги вижда',
    'Колегите от вашия храм виждат името, сана, телефона, профила и снимката ви, както и '
        'споделените събития, одобрените почивки и дежурствата. Касата и склада виждат само '
        'председателят и касиерът. Свещеници от други храмове не виждат нищо от това.'
  ),
  (
    'Къде се пазят',
    'На сървър в Европейския съюз (Supabase, Франкфурт, Германия). Известията до телефона минават '
        'през Google Firebase. Данните не се продават и не се използват за реклама.'
  ),
  (
    'Колко време',
    'Докато профилът ви съществува. Записите в касата не се трият, защото са счетоводна история '
        'на храма.'
  ),
  (
    'Вашите права',
    'Можете да видите и поправите данните си в „Моят профил“. Можете да поискате копие или '
        'изтриване на профила си от създателя на приложението. Можете да оттеглите съгласието си, '
        'като поискате изтриване на профила.'
  ),
];

/// Текстът „Лични данни и поверителност“.
class PrivacyText extends StatelessWidget {
  const PrivacyText({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (t, b) in _sections) ...[
        Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(b, style: TextStyle(fontSize: 15.5, height: 1.4, color: p.text)),
        const SizedBox(height: 14),
      ],
    ]);
  }
}

/// Само за четене (от Профил и от регистрацията).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Лични данни')),
        body: const SafeArea(
          child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 8, 20, 24), child: PrivacyText()),
        ),
      );
}

/// Показва се, докато потребителят не приеме текущата версия на текста.
class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Лични данни'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Column(children: [
          const Expanded(
            child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 8, 20, 12), child: PrivacyText()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await s.acceptPrivacy();
                        } on AppError catch (e) {
                          if (context.mounted) showMessage(context, e.message);
                        }
                        if (mounted) setState(() => _busy = false);
                      },
                child: const Text('Съгласен съм'),
              ),
              TextButton(onPressed: () => s.logout(), child: const Text('Не съм съгласен – изход')),
            ]),
          ),
        ]),
      ),
    );
  }
}
