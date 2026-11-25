import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Номер на изграждането (подава се от GitHub). 0 = местно изграждане.
const buildNumber = int.fromEnvironment('BUILD_NUMBER');

/// Камбанката „Какво е новото“ се показва само в тестовите версии.
const isTestBuild = bool.fromEnvironment('TEST_BUILD', defaultValue: true);

const _kSeen = 'whats_new_seen_build';

/// Една версия в камбанката.
class WhatsNewRelease {
  final String date;
  final List<String> added;
  final List<String> test;
  WhatsNewRelease(this.date, this.added, this.test);
}

/// Бележките се трупат версия след версия (най-новата първа). Отметната
/// проверка изчезва от камбанката; версия без неотметнати проверки се скрива
/// (освен най-новата), за да виждат тестерите и пропуснатите обновления.
class WhatsNew {
  final List<WhatsNewRelease> releases;
  WhatsNew(this.releases);

  static Map<String, dynamic>? _json;

  /// [creator] – профилът на създателя вижда и бележките „само за вас“.
  static Future<WhatsNew> load({bool creator = false}) async {
    final j = _json ??=
        jsonDecode(await rootBundle.loadString('assets/whats_new.json')) as Map<String, dynamic>;
    final raw = (j['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [j];
    return WhatsNew([
      for (final r in raw)
        () {
          List<String> list(String k) => ((r[k] as List?) ?? const []).cast<String>();
          return WhatsNewRelease(
            (r['date'] as String?) ?? '',
            [if (creator) ...list('creator'), ...list('added')],
            [if (creator) ...list('creator_test'), ...list('test')],
          );
        }(),
    ].where((r) => r.added.isNotEmpty || r.test.isNotEmpty).toList());
  }
}

/// Камбанка с червена точка, докато тестерът не отвори бележките на тази версия.
class WhatsNewBell extends StatefulWidget {
  const WhatsNewBell({super.key});

  @override
  State<WhatsNewBell> createState() => _WhatsNewBellState();
}

class _WhatsNewBellState extends State<WhatsNewBell> {
  bool _unseen = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getInt(_kSeen) ?? -1;
    if (mounted) setState(() => _unseen = seen != buildNumber);
  }

  Future<void> _open() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeen, buildNumber);
    if (mounted) setState(() => _unseen = false);
    if (mounted) await showWhatsNew(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: _unseen ? 'Какво е новото – има нова версия' : 'Какво е новото',
      button: true,
      excludeSemantics: true,
      child: IconButton(
        tooltip: 'Какво е новото',
        onPressed: _open,
        style: IconButton.styleFrom(
          fixedSize: const Size(44, 44),
          backgroundColor: p.surface,
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
        ),
        icon: Stack(clipBehavior: Clip.none, children: [
          const Icon(Icons.notifications_none_rounded, size: 24),
          if (_unseen)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFD64545),
                  shape: BoxShape.circle,
                  border: Border.all(color: p.surface, width: 1.5),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

const _kTested = 'whats_new_tested';

/// Прозорецът „Какво е новото“.
Future<void> showWhatsNew(BuildContext context) async {
  final notes = await WhatsNew.load(creator: AppScope.read(context).isCreator);
  // Отметнатите проверки се пазят на телефона (по текст, за всички версии).
  final prefs = await SharedPreferences.getInstance();
  final done = (prefs.getStringList(_kTested) ?? const <String>[]).toSet();
  // Отметнатото преди отварянето вече не се показва; отметнатото сега се
  // задрасква и изчезва при следващото отваряне.
  final hidden = {...done};
  final shown = <WhatsNewRelease>[
    for (var i = 0; i < notes.releases.length; i++)
      if (i == 0 || notes.releases[i].test.any((t) => !hidden.contains(t))) notes.releases[i],
  ];
  if (!context.mounted) return;
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final p = Palette.of(ctx);
      Widget item(String text, IconData icon, Color color) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: color)),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.35))),
            ]),
          );
      return StatefulBuilder(builder: (ctx, setSheet) {
        Widget check(String t) => CheckboxListTile(
              value: done.contains(t),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              visualDensity: VisualDensity.compact,
              title: Text(t,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    color: done.contains(t) ? p.textMuted : null,
                    decoration: done.contains(t) ? TextDecoration.lineThrough : null,
                  )),
              onChanged: (v) {
                setSheet(() => v == true ? done.add(t) : done.remove(t));
                prefs.setStringList(_kTested, done.toList());
              },
            );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              const Text('Какво е новото', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              if (buildNumber > 0)
                Text('Тестова версия $buildNumber', style: TextStyle(fontSize: 15, color: p.textMuted)),
              Text('Отметнете всяка проверка, когато я изпробвате – при следващото отваряне изчезва.',
                  style: TextStyle(fontSize: 14, color: p.textMuted)),
              for (final (i, r) in shown.indexed) ...[
                const SizedBox(height: 18),
                if (r.date.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: i == 0 ? p.primary.withValues(alpha: 0.12) : p.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: p.border)),
                    child: Text(i == 0 ? 'Най-новото · ${r.date}' : 'По-рано · ${r.date}',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                            color: i == 0 ? p.primary : p.textMuted)),
                  ),
                const SizedBox(height: 10),
                if (r.added.isNotEmpty) ...[
                  const Text('Добавено', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final a in r.added) item(a, Icons.add_circle_outline_rounded, p.primary),
                ],
                if (r.test.any((t) => !hidden.contains(t))) ...[
                  const SizedBox(height: 6),
                  const Text('Какво да тествате', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  for (final t in r.test)
                    if (!hidden.contains(t)) check(t),
                ] else if (r.test.isNotEmpty)
                  Text('Всичко от тази версия е изпробвано. Благодаря!',
                      style: TextStyle(fontSize: 15, color: p.textMuted)),
              ],
              const SizedBox(height: 12),
              Text('Пишете на Димитър за всичко, което не работи или обърква.',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
            ],
          ),
        );
      });
    },
  );
}
