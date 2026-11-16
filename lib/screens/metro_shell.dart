import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/desk_chrome.dart';
import 'church_connect.dart';
import 'creator.dart';
import 'diocese.dart';
import 'metro_cabinet.dart';
import 'metro_chat.dart';

/// Митрополитският изглед – собствено меню и начален екран, в пурпур и злато.
class MetroShell extends StatefulWidget {
  const MetroShell({super.key});

  @override
  State<MetroShell> createState() => _MetroShellState();
}

class _MetroShellState extends State<MetroShell> with WidgetsBindingObserver {
  String tab = '';

  /// Менюто според длъжността: митрополитът и секретарят – начало, епархия,
  /// чат, календар на владиката, програми (предстои); служителят – чат,
  /// календар и профил; наместникът – епархия.
  List<(String, IconData, String, int)> _items(AppState s) {
    final cabinet = s.isMetropolitan || s.isSecretary;
    return [
      if (cabinet) ('home', Icons.home_rounded, 'Начало', 0),
      if (s.hasDioceseView) ('diocese', Icons.account_balance_outlined, 'Епархия', 0),
      if (s.isAdmin) ('chat', Icons.chat_bubble_outline_rounded, 'Чат', s.metroUnreadAll),
      if (cabinet || s.isEmployee) ('calendar', Icons.calendar_month_outlined, 'Календар', 0),
      if (cabinet) ('programs', Icons.airport_shuttle_outlined, 'Програми', 0),
      ('profile', Icons.person_outline_rounded, 'Профил', 0),
    ];
  }

  void _open(String id) => setState(() => tab = id);

  Map<String, dynamic>? _overview; // за търсачката горе

  Widget _desktop(BuildContext context, AppState s, List<(String, IconData, String, int)> items, String current) {
    final p = Palette.of(context);
    final me = s.currentUser;
    final mine = s.myStaff.firstOrNull;
    final dio = s.dioceseName(mine?.dioceseId) ?? '';
    final role = mine == null ? '' : (mine.role == StaffRole.employee ? (mine.title ?? mine.role.label) : mine.role.label);
    if (_overview == null && s.hasDioceseView) {
      _overview = const {};
      s.dioceseOverview().then((d) {
        if (mounted) setState(() => _overview = d);
      }).catchError((_) {});
    }
    String? section(String id) => switch (id) {
          'calendar' => 'Служение',
          'profile' => 'Аз',
          _ => null,
        };
    return DeskFrame(
      logoColor: s.isMetropolitan ? p.primary : Palette.yellow,
      logoSuffix: 'Митрополия',
      onLogo: () {
        _open(items.first.$1);
        s.refresh();
      },
      chipIcon: '☦',
      chipTitle: dio.isEmpty ? 'Митрополия' : dio,
      chipSubtitle: role,
      searchHint: s.hasDioceseView ? 'Търсене: име, сан, храм, село, околия…' : 'Търсене…',
      search: (q) => _deskSearch(context, s, q),
      bell: s.metroUnreadAll,
      bellTooltip: 'Непрочетени в чата',
      onBell: s.isAdmin ? () => _open('chat') : null,
      userInitials: (me?.name ?? '?').trim().isEmpty ? '?' : (me!.name.trim().characters.first).toUpperCase(),
      userName: me == null ? '' : withRank(s.isMetropolitan ? ClergyRank.metropolitan : me.rank, me.name),
      userMenu: [
        DeskMenuAction(Icons.person_outline_rounded, 'Профил', () => _open('profile')),
        if (s.myChurches.isNotEmpty) DeskMenuAction(Icons.church_outlined, 'Към храма', () => s.setMetroMode(false)),
        DeskMenuAction(Icons.refresh_rounded, 'Обнови', s.refresh),
        DeskMenuAction(Icons.logout_rounded, 'Изход', s.logout),
      ],
      items: [
        for (final it in items) DeskNavItem(it.$1, it.$2, it.$3, badge: it.$4, section: section(it.$1)),
      ],
      current: current,
      onSelect: _open,
      footer: 'Кайрос · Митрополия · Beta',
      body: Container(
        color: p.bg,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: current == 'diocese' ? 1400 : 980),
            child: _page(s, current),
          ),
        ),
      ),
    );
  }

  List<SearchHit> _deskSearch(BuildContext context, AppState s, String query) {
    final q = query.trim().toLowerCase();
    final ids = _items(s).map((e) => e.$1).toSet();
    final hits = <SearchHit>[
      for (final it in _items(s))
        if (q.isEmpty || it.$3.toLowerCase().contains(q)) SearchHit(it.$2, it.$3, 'Раздел', () => _open(it.$1)),
    ];
    if (q.length < 2) return hits;
    if (ids.contains('calendar') && (s.isMetropolitan || s.isSecretary)) {
      final df = DateFormat('d MMM y', 'bg');
      for (final e in s.metroEvents) {
        if ('${e.title} ${e.place ?? ''} ${e.note ?? ''}'.toLowerCase().contains(q)) {
          hits.add(SearchHit(Icons.event_outlined, e.title,
              [df.format(e.startsAt), if ((e.place ?? '').isNotEmpty) e.place!].join(' · '),
              () => editMetroEvent(context, e: e)));
        }
      }
    }
    final d = _overview;
    if (d == null || d.isEmpty) return hits;
    List<Map<String, dynamic>> list(Object? v) =>
        (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final qd = q.replaceAll(' ', '');
    for (final sec in list(d['sections'])) {
      for (final c in list(sec['churches'])) {
        final cText = '${c['name']} ${c['settlement']} ${sec['name']}'.toLowerCase();
        if (cText.contains(q)) {
          hits.add(SearchHit(Icons.church_outlined, '${c['name']}', '${c['settlement']} · ${sec['name']}', () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Theme(
                        data: Theme.of(context),
                        child: DioceseChurchScreen(churchId: '${c['id']}', title: '${c['name']}'))));
          }));
        }
        for (final pr in list(c['priests'])) {
          final name = withRank(ClergyRank.fromCode(pr['rank']), '${pr['name'] ?? ''}');
          final phone = '${pr['phone'] ?? ''}'.trim();
          if (name.toLowerCase().contains(q) || (qd.length >= 3 && phone.replaceAll(' ', '').contains(qd))) {
            hits.add(SearchHit(Icons.person_outline_rounded, name,
                ['${c['name']} – ${c['settlement']}', if (phone.isNotEmpty) phone].join(' · '),
                () => _showPerson(context, name, '${c['name']} – ${c['settlement']} · ${sec['name']}', phone)));
          }
        }
      }
    }
    return hits;
  }

  void _showPerson(BuildContext context, String name, String where, String phone) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(name),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(where, style: TextStyle(color: Palette.of(ctx).textMuted)),
            const SizedBox(height: 10),
            SelectableText(phone.isEmpty ? 'Няма въведен телефон.' : phone,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Затвори'))],
        ),
      );

  Widget _page(AppState s, String id) => switch (id) {
        'home' => s.isMetropolitan ? _MetroHome(onOpen: _open) : _SecretaryHome(onOpen: _open),
        'diocese' => const DioceseScreen(embedded: true),
        'chat' => const MetroChatScreen(embedded: true),
        'programs' => const LockedScreen(lockPrograms),
        'calendar' => s.isMetropolitan || s.isSecretary
            ? const MetroCalendarScreen(embedded: true)
            : const _Soon('Календар',
                'Вашият календар в митрополията. Събитията влизат сами, когато сте вписани някъде '
                    '(напр. шофьор в програма за архиерейско служение).'),
        _ => const _MetroProfile(),
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = AppScope.read(context);
    if (s.isAdmin) s.loadMetroPeople();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppScope.read(context).refresh();
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
    if (wide) return _desktop(context, s, items, current);
    return Scaffold(
      body: _page(s, current),
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
  final ValueChanged<String> onOpen;
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
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 24), children: [
            _Header(icon: '☦', title: name, subtitle: s.dioceseName(mine?.dioceseId) ?? ''),
            const SizedBox(height: 18),
            const CallButton(),
            const CallsMadeCard(),
            const SizedBox(height: 14),
            UpcomingMetroEvents(onOpen: () => widget.onOpen('calendar')),
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
            _Tiles(onOpen: widget.onOpen),
            const LockedGrid(lockedForMetropolitan),
          ]),
        ),
      ),
    );
  }
}

class _SecretaryHome extends StatelessWidget {
  final ValueChanged<String> onOpen;
  const _SecretaryHome({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final me = s.currentUser;
    final mine = s.myStaff.where((e) => e.role == StaffRole.secretary).firstOrNull;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 24), children: [
            _Header(
                icon: '✎',
                title: me == null ? '' : withRank(me.rank, me.name),
                subtitle: 'Секретар · ${s.dioceseName(mine?.dioceseId) ?? ''}'),
            const SizedBox(height: 18),
            UpcomingMetroEvents(onOpen: () => onOpen('calendar')),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Запиши в календара на владиката'),
                onPressed: () => editMetroEvent(context),
              ),
            ),
            const SizedBox(height: 6),
            _Tiles(onOpen: onOpen),
            const LockedGrid(lockedForSecretary),
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  const _Header({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(icon, style: TextStyle(fontSize: 30, color: p.onPrimary))),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text(subtitle, style: TextStyle(fontSize: 15, color: p.textMuted)),
        ]),
      ),
    ]);
  }
}

/// Плочките „Епархия · Чат · Календар“ на началния екран.
class _Tiles extends StatelessWidget {
  final ValueChanged<String> onOpen;
  const _Tiles({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    Widget tile(IconData i, String t, String tab, [int badge = 0]) => Expanded(
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onOpen(tab),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  badge > 0
                      ? Badge(label: Text('$badge'), child: Icon(i, color: p.primary, size: 26))
                      : Icon(i, color: p.primary, size: 26),
                  const SizedBox(height: 8),
                  Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.account_balance_outlined, 'Епархия', 'diocese'),
      const SizedBox(width: 10),
      tile(Icons.chat_bubble_outline_rounded, 'Чат', 'chat', s.metroUnreadAll),
      const SizedBox(width: 10),
      tile(Icons.calendar_month_outlined, 'Календар', 'calendar'),
    ]);
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
        if (s.isMetropolitan) ...[
          const SizedBox(height: 20),
          const CallButton(),
        ],
        if (s.isMetropolitan || s.isSecretary)
          LockedGrid(s.isMetropolitan ? lockedForMetropolitan : lockedForSecretary),
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
        if (s.isCreator) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Кайрос в числа'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatorScreen())),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(onPressed: s.logout, child: const Text('Изход')),
      ]),
    );
  }
}
