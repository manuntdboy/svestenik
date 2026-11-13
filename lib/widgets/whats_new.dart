import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Номер на изграждането (подава се от GitHub). 0 = местно изграждане.
const buildNumber = int.fromEnvironment('BUILD_NUMBER');

/// Камбанката „Какво е новото“ се показва само в тестовите версии.
const isTestBuild = bool.fromEnvironment('TEST_BUILD', defaultValue: true);

/// Сборка само за създателя (--dart-define=CREATOR=true): има скрития екран
/// „Кайрос в числа“ и бележки „само за вас“. В версиите за тестерите е false
/// и този код изобщо не влиза в приложението.
const isCreatorBuild = bool.fromEnvironment('CREATOR');

const _kSeen = 'whats_new_seen_build';

class WhatsNew {
  final String date;
  final List<String> added;
  final List<String> test;
  WhatsNew(this.date, this.added, this.test);

  static WhatsNew? _cache;

  static Future<WhatsNew> load() async {
    if (_cache != null) return _cache!;
    final j = jsonDecode(await rootBundle.loadString('assets/whats_new.json')) as Map<String, dynamic>;
    return _cache = WhatsNew(
      (j['date'] as String?) ?? '',
      [
        if (isCreatorBuild) ...((j['creator'] as List?) ?? const []).cast<String>(),
        ...((j['added'] as List?) ?? const []).cast<String>(),
      ],
      [
        if (isCreatorBuild) ...((j['creator_test'] as List?) ?? const []).cast<String>(),
        ...((j['test'] as List?) ?? const []).cast<String>(),
      ],
    );
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

/// Прозорецът „Какво е новото“.
Future<void> showWhatsNew(BuildContext context) async {
  final notes = await WhatsNew.load();
  // Отметнатите проверки се пазят на телефона, отделно за всяка версия.
  final prefs = await SharedPreferences.getInstance();
  final key = 'whats_new_tested_$buildNumber';
  final done = (prefs.getStringList(key) ?? const <String>[]).toSet();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
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
      return StatefulBuilder(builder: (ctx, setSheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text('Какво е новото', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text(
                [
                  if (buildNumber > 0) 'Тестова версия $buildNumber',
                  if (notes.date.isNotEmpty) notes.date,
                ].join(' · '),
                style: TextStyle(fontSize: 15, color: p.textMuted)),
            const SizedBox(height: 18),
            const Text('Добавено', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final a in notes.added) item(a, Icons.add_circle_outline_rounded, p.primary),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(
                child: Text('Какво да тествате',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Text('${notes.test.where(done.contains).length} от ${notes.test.length}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.textMuted)),
            ]),
            Text('Отметнете всяка проверка, когато я изпробвате.',
                style: TextStyle(fontSize: 14, color: p.textMuted)),
            const SizedBox(height: 6),
            for (final t in notes.test)
              CheckboxListTile(
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
                  prefs.setStringList(key, done.toList());
                },
              ),
            const SizedBox(height: 8),
            Text('Пишете на Димитър за всичко, което не работи или обърква.',
                style: TextStyle(fontSize: 15, color: p.textMuted)),
          ],
        ),
      ));
    },
  );
}
