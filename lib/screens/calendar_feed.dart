import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// „Календар в Google и iPhone“ – лична връзка за абонамент.
class CalendarFeedScreen extends StatefulWidget {
  const CalendarFeedScreen({super.key});

  @override
  State<CalendarFeedScreen> createState() => _CalendarFeedScreenState();
}

class _CalendarFeedScreenState extends State<CalendarFeedScreen> {
  Map<String, dynamic>? feed;
  bool busy = false;

  String get _https => '$supabaseUrl/functions/v1/ical?t=${feed!['token']}';
  String get _webcal => _https.replaceFirst(RegExp('^https://'), 'webcal://');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await AppScope.read(context).calendarFeed();
      if (mounted) setState(() => feed = f);
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _set({String? scope, bool? names}) async {
    final f = feed!;
    final sc = scope ?? '${f['scope']}';
    final nm = names ?? f['with_names'] == true;
    setState(() => feed = {...f, 'scope': sc, 'with_names': nm});
    try {
      await AppScope.read(context).calendarFeedSet(sc, nm);
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final f = feed;
    Widget step(String n, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text(n, style: TextStyle(fontWeight: FontWeight.w800, color: p.primary))),
            Expanded(child: Text(t, style: const TextStyle(fontSize: 15, height: 1.35))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Календар в Google и iPhone')),
      body: f == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 32), children: [
                  Text('Събитията от Кайрос се появяват сами в календара на телефона ви – и в уиджета му. '
                      'Записвате само в Кайрос; Google и iPhone само ги показват.',
                      style: TextStyle(fontSize: 15.5, color: p.textMuted)),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'mine', label: Text('Моите'), icon: Icon(Icons.person_outline_rounded)),
                      ButtonSegment(value: 'church', label: Text('Целият храм'), icon: Icon(Icons.church_outlined)),
                    ],
                    selected: {'${f['scope']}'},
                    onSelectionChanged: (v) => _set(scope: v.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      f['scope'] == 'church'
                          ? 'Вашите събития и дежурства, плюс споделените събития и дежурствата на колегите.'
                          : 'Събитията, на които служите, личните ви събития, дежурствата и почивките ви.',
                      style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('С имената (за кого е събитието)'),
                    subtitle: Text('Изключено: в календара пише само вида и часа, напр. „Кръщене“.',
                        style: TextStyle(color: p.textMuted)),
                    value: f['with_names'] == true,
                    onChanged: (v) => _set(names: v),
                  ),
                  const SizedBox(height: 10),
                  Text('ВАШАТА ЛИЧНА ВРЪЗКА',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: p.primary)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                    child: SelectableText(_https, style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Копирай връзката'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _https));
                      if (context.mounted) showMessage(context, 'Връзката е копирана.');
                    },
                  ),
                  const SizedBox(height: 22),
                  Text('Google Calendar (Android)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  step('1', 'Натиснете „Добави в Google Calendar“ (бутона отдолу). Отваря се страница на Google.'),
                  step('2', 'Ако пита за профил – изберете същия Google профил, който е на телефона.'),
                  step('3', 'Натиснете „Добавяне“.'),
                  step('4', 'Отворете приложението Google Calendar.'),
                  step('5', 'Горе вляво ☰ (трите чертички) → най-долу „Настройки“.'),
                  step('6', 'Отворете „Кайрос“ и включете „Синхронизиране“.'),
                  step('7', 'Готово. След малко (понякога до няколко часа) събитията се появяват в календара и в уиджета.'),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.event_available_rounded),
                    label: const Text('Добави в Google Calendar'),
                    onPressed: () =>
                        _open('https://calendar.google.com/calendar/r?cid=${Uri.encodeComponent(_webcal)}'),
                  ),
                  const SizedBox(height: 22),
                  Text('iPhone', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  step('1', 'Натиснете „Добави в календара на iPhone“ (бутона отдолу).'),
                  step('2', 'Натиснете „Абониране“, после „Добави“.'),
                  step('3', 'Готово – събитията се появяват в Календар и в уиджета.'),
                  step('', 'Ако не стане: копирайте връзката (горе) → Настройки → Календар → Акаунти → Добави акаунт → '
                      'Друго → „Добави абонаментен календар“ → поставете връзката → Напред → Запиши.'),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.phone_iphone_rounded),
                    label: const Text('Добави в календара на iPhone'),
                    onPressed: () => _open(_webcal),
                  ),
                  const SizedBox(height: 22),
                  Text('Google обновява абонаментните календари през няколко часа – новото събитие може да се появи там '
                      'по-късно. За последния момент гледайте в Кайрос; известията идват веднага.',
                      style: TextStyle(fontSize: 14, color: p.textMuted)),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    icon: const Icon(Icons.autorenew_rounded),
                    label: const Text('Нова връзка (старата спира веднага)'),
                    onPressed: busy
                        ? null
                        : () async {
                            if (!await confirm(context, 'Нова връзка',
                                'Старата връзка спира да работи и календарът трябва да се добави наново. Продължаваме?',
                                'Нова връзка')) {
                              return;
                            }
                            setState(() => busy = true);
                            try {
                              final n = await AppScope.read(context).calendarFeedReset();
                              if (mounted) setState(() => feed = n);
                            } on AppError catch (e) {
                              if (context.mounted) showMessage(context, e.message);
                            }
                            if (mounted) setState(() => busy = false);
                          },
                  ),
                ]),
              ),
            ),
    );
  }
}
