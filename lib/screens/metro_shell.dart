import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'diocese.dart';

/// Митрополитският изглед – собствено меню и начален екран, в пурпур и злато.
class MetroShell extends StatefulWidget {
  const MetroShell({super.key});

  @override
  State<MetroShell> createState() => _MetroShellState();
}

class _MetroShellState extends State<MetroShell> {
  int tab = 0;

  static const _items = [
    (Icons.home_rounded, 'Начало'),
    (Icons.account_balance_outlined, 'Епархия'),
    (Icons.airport_shuttle_outlined, 'Програми'),
    (Icons.calendar_month_outlined, 'Календар'),
    (Icons.person_outline_rounded, 'Профил'),
  ];

  Widget _page() => switch (tab) {
        0 => _MetroHome(onOpen: (i) => setState(() => tab = i)),
        1 => const DioceseScreen(embedded: true),
        2 => const _Soon('Програми за архиерейски служения',
            'Секретарят съставя програмата – групи, коли, служещи, гости на обяд. Владиката я утвърждава, '
                'всеки участник получава известие със своята част, а документът излиза готов за печат.'),
        3 => const _Soon('Календар на владиката',
            'Срещи, посещения и служения – записват ги владиката и секретарят. Утвърдените програми '
                'влизат сами, а личните записи остават само за владиката.'),
        _ => const _MetroProfile(),
      };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            backgroundColor: p.surfaceAlt,
            selectedIndex: tab,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: [
              for (final it in _items) NavigationRailDestination(icon: Icon(it.$1), label: Text(it.$2)),
            ],
          ),
          Expanded(
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: _page())),
          ),
        ]),
      );
    }
    return Scaffold(
      body: _page(),
      bottomNavigationBar: NavigationBar(
        backgroundColor: p.surfaceAlt,
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [for (final it in _items) NavigationDestination(icon: Icon(it.$1), label: it.$2)],
      ),
    );
  }
}

class _MetroHome extends StatefulWidget {
  final ValueChanged<int> onOpen;
  const _MetroHome({required this.onOpen});

  @override
  State<_MetroHome> createState() => _MetroHomeState();
}

class _MetroHomeState extends State<_MetroHome> {
  (int, int, int)? counts;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).dioceseOverview().then((d) {
      final secs = (d['sections'] as List? ?? const []);
      var ch = 0;
      final pr = <String>{};
      for (final s in secs) {
        for (final c in ((s as Map)['churches'] as List? ?? const [])) {
          ch++;
          for (final x in ((c as Map)['priests'] as List? ?? const [])) {
            pr.add('${(x as Map)['user_id']}');
          }
        }
      }
      if (mounted) setState(() => counts = (secs.length, ch, pr.length));
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final me = s.currentUser;
    final mine = s.myStaff.where((e) => e.role == StaffRole.metropolitan).firstOrNull;
    final name = me == null ? '' : withRank(ClergyRank.metropolitan, me.name);
    Widget tile(IconData i, String t, int tab) => Expanded(
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => widget.onOpen(tab),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(i, color: p.primary, size: 26),
                  const SizedBox(height: 8),
                  Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 24), children: [
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(16)),
              child: Center(child: Text('☦', style: TextStyle(fontSize: 30, color: p.onPrimary))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                Text(s.dioceseName(mine?.dioceseId) ?? '', style: TextStyle(fontSize: 15, color: p.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.primary.withValues(alpha: .35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ДНЕС И ПРЕДСТОЯЩИ',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: p.primary)),
              const SizedBox(height: 8),
              Text('Тук ще са служенията и срещите от календара на владиката.',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            for (final n in [
              ('${counts?.$1 ?? '–'}', 'раздела'),
              ('${counts?.$2 ?? '–'}', 'храма'),
              ('${counts?.$3 ?? '–'}', 'свещеници'),
            ])
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    Text(n.$1, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: p.primary)),
                    Text(n.$2, style: TextStyle(fontSize: 13, color: p.textMuted)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            tile(Icons.account_balance_outlined, 'Епархия', 1),
            const SizedBox(width: 10),
            tile(Icons.search_rounded, 'Търсене', 1),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            tile(Icons.airport_shuttle_outlined, 'Програми', 2),
            const SizedBox(width: 10),
            tile(Icons.calendar_month_outlined, 'Календар', 3),
          ]),
        ]),
      ),
    );
  }
}

class _Soon extends StatelessWidget {
  final String title;
  final String text;
  const _Soon(this.title, this.text);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const YellowTag('Предстои'),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(fontSize: 17, color: p.textMuted)),
      ]),
    );
  }
}

class _MetroProfile extends StatelessWidget {
  const _MetroProfile();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final me = s.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Профил'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(me == null ? '' : withRank(me.rank, me.name),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (me != null) Text('@${me.username}', style: TextStyle(color: p.textMuted)),
        const SizedBox(height: 6),
        for (final e in s.myStaff)
          Text(
              [
                e.role.label,
                s.dioceseName(e.dioceseId) ?? '',
                if (e.vicariateId != null) s.vicariateName(e.vicariateId) ?? '',
              ].where((x) => x.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 15, color: p.textMuted)),
        const SizedBox(height: 24),
        if (s.myChurches.isNotEmpty)
          OutlinedButton.icon(
            icon: const Icon(Icons.church_outlined),
            label: const Text('Към храма'),
            onPressed: () => s.setMetroMode(false),
          ),
        const SizedBox(height: 12),
        TextButton(onPressed: s.logout, child: const Text('Изход')),
      ]),
    );
  }
}
