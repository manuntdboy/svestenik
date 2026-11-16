import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'church_connect.dart';
import 'diocese.dart';
import 'metro_chat.dart';

/// Митрополитският изглед – собствено меню и начален екран, в пурпур и злато.
class MetroShell extends StatefulWidget {
  const MetroShell({super.key});

  @override
  State<MetroShell> createState() => _MetroShellState();
}

class _MetroShellState extends State<MetroShell> {
  String tab = '';

  /// Менюто според длъжността: митрополитът – всичко; служителят – чат,
  /// календар и профил; останалите – епархия, чат (ако са в администрацията).
  List<(String, IconData, String, int)> _items(AppState s) => [
        if (s.isMetropolitan) ('home', Icons.home_rounded, 'Начало', 0),
        if (s.hasDioceseView) ('diocese', Icons.account_balance_outlined, 'Епархия', 0),
        if (s.isAdmin) ('chat', Icons.chat_bubble_outline_rounded, 'Чат', s.metroUnreadAll),
        if (s.isMetropolitan || s.myStaff.any((e) => e.role == StaffRole.secretary))
          ('programs', Icons.airport_shuttle_outlined, 'Програми', 0),
        if (s.isMetropolitan || s.isEmployee) ('calendar', Icons.calendar_month_outlined, 'Календар', 0),
        ('profile', Icons.person_outline_rounded, 'Профил', 0),
      ];

  void _open(String id) => setState(() => tab = id);

  Widget _page(String id) => switch (id) {
        'home' => _MetroHome(onOpen: (i) => _open(const ['home', 'diocese', 'programs', 'calendar'][i])),
        'diocese' => const DioceseScreen(embedded: true),
        'chat' => const MetroChatScreen(embedded: true),
        'programs' => const _Soon('Програми за архиерейски служения',
            'Секретарят съставя програмата – групи, коли, служещи, гости на обяд. Владиката я утвърждава, '
                'всеки участник получава известие със своята част, а документът излиза готов за печат.'),
        'calendar' => const _Soon('Календар',
            'Срещи, посещения и служения. Владиката и секретарят записват в календара на владиката; '
                'при служителите събитията влизат сами, когато са вписани някъде (напр. шофьор в програма).'),
        _ => const _MetroProfile(),
      };

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context);
    if (s.isAdmin) s.loadMetroPeople();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final items = _items(s);
    final ids = items.map((e) => e.$1).toList();
    final current = ids.contains(tab) ? tab : ids.first;
    final index = ids.indexOf(current);
    Widget icon((String, IconData, String, int) it) =>
        it.$4 > 0 ? Badge(label: Text('${it.$4}'), child: Icon(it.$2)) : Icon(it.$2);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            backgroundColor: p.surfaceAlt,
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => _open(ids[i]),
            destinations: [
              for (final it in items) NavigationRailDestination(icon: icon(it), label: Text(it.$3)),
            ],
          ),
          Expanded(
            child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: _page(current))),
          ),
        ]),
      );
    }
    return Scaffold(
      body: _page(current),
      bottomNavigationBar: items.length < 2
          ? null
          : NavigationBar(
              backgroundColor: p.surfaceAlt,
              selectedIndex: index,
              onDestinationSelected: (i) => _open(ids[i]),
              destinations: [for (final it in items) NavigationDestination(icon: icon(it), label: it.$3)],
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
                e.role == StaffRole.employee ? (e.title ?? e.role.label) : e.role.label,
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
        if (s.myChurches.isEmpty && !s.isMetropolitan)
          OutlinedButton.icon(
            icon: const Icon(Icons.church_outlined),
            label: const Text('Свържи се с храм'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ChurchConnectScreen(pushed: true))),
          ),
        const SizedBox(height: 12),
        TextButton(onPressed: s.logout, child: const Text('Изход')),
      ]),
    );
  }
}
