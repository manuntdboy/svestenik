import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/notifier.dart';
import '../theme.dart';
import '../widgets/desk_chrome.dart';
import '../widgets/layout.dart';
import 'alarm_ring.dart';
import 'calendar.dart';
import 'cash.dart';
import 'stock.dart';
import 'event_detail.dart';
import 'leaves.dart';
import 'chat.dart';
import 'duties.dart';
import 'help.dart';
import 'home.dart';
import 'profile.dart';
import 'program_draft.dart';
import 'diocese.dart' show metroTheme;
import 'metro_chat.dart';

/// Основната рамка с долната лента: Начало, Календар, Профил.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  // 0 Календар (отваря се при стартиране), 1 Начало, 2 Профил.
  int _tab = 0;
  Timer? _tick;
  StreamSubscription<AlarmSet>? _ringing;
  int? _ringingShown; // номерът на алармата, чийто екран е отворен

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Обновява „след 2 часа“ и следващото събитие всяка минута.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // При първото отваряне Android пита дали да се показват известия.
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Notifier.requestPermissions();
        _openFromNotification();
      });
      Notifier.opened.addListener(_openFromNotification);
      _ringing = Alarm.ringing.listen(_onRinging);
    }
  }

  /// Звъни аларма → отваряме екрана с „Спри“; спряна от известието →
  /// затваряме го.
  void _onRinging(AlarmSet set) {
    if (!mounted) return;
    final nav = Navigator.of(context);
    final shown = _ringingShown;
    if (shown != null && !set.alarms.any((a) => a.id == shown)) {
      _ringingShown = null;
      nav.popUntil((r) => r.settings.name != 'alarm');
    }
    if (_ringingShown != null || set.alarms.isEmpty) return;
    final alarm = set.alarms.first;
    _ringingShown = alarm.id;
    nav
        .push(MaterialPageRoute(
          settings: const RouteSettings(name: 'alarm'),
          fullscreenDialog: true,
          builder: (_) => AlarmRingScreen(alarm: alarm),
        ))
        .then((_) {
      if (_ringingShown == alarm.id) _ringingShown = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => desktopShell.value = false);
    Notifier.opened.removeListener(_openFromNotification);
    _ringing?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  /// Натиснато известие → обновяваме и отваряме мястото, за което е.
  Future<void> _openFromNotification() async {
    final data = Notifier.opened.value;
    if (data == null || !mounted) return;
    Notifier.opened.value = null;
    final s = AppScope.read(context);
    final nav = Navigator.of(context);
    await s.refresh();
    if (!mounted) return;
    final type = data['type'] ?? '';
    final eventId = data['event_id'];
    if (type == 'cash') {
      nav.push(MaterialPageRoute(builder: (_) => const CashScreen()));
    } else if (type == 'stock') {
      nav.push(MaterialPageRoute(builder: (_) => const StockScreen()));
    } else if (type == 'chat') {
      final thread = data['thread'] ?? 'c';
      // Съобщение от друг храм – първо минаваме в него.
      final cid = data['church_id'];
      if (cid != null && cid.isNotEmpty && cid != s.currentChurchId && s.myChurches.any((c) => c.id == cid)) {
        await s.selectChurch(cid);
      }
      nav.push(MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)));
    } else if (type == 'metro_call' || type == 'metro_call_answer') {
      // Повикването се показва само (CallWatcher) – тук нищо не отваряме.
    } else if (type == 'metro_chat' && s.isAdmin) {
      final thread = data['thread'] ?? 'c';
      await s.loadMetroPeople();
      final x = s.metroPeople.where((e) => e['user_id'] == thread).firstOrNull;
      nav.push(MaterialPageRoute(
          builder: (_) => (s.isMetropolitan ? metroTheme : (Widget w) => w)(MetroThreadScreen(
              thread: thread,
              title: thread == 'c' ? 'Администрация' : withRank(ClergyRank.fromCode(x?['rank']), '${x?['name'] ?? ''}')))));
    } else if (type.startsWith('duty')) {
      nav.push(MaterialPageRoute(builder: (_) => const DutyScreen()));
    } else if (type.startsWith('leave_')) {
      final rid = data['request_id'];
      nav.push(MaterialPageRoute(
          builder: (_) => rid == null ? const LeavesScreen() : LeaveRequestScreen(requestId: rid)));
    } else if (eventId != null && s.eventById(eventId) != null) {
      // Молба за потвърждение и др. – детайлите имат „Приемам / Отказвам“.
      setState(() => _tab = 0);
      nav.push(MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: eventId)));
    } else {
      setState(() => _tab = 1); // заявка за присъединяване, одобрение и т.н.
    }
  }

  /// При връщане в приложението изтегля новостите от сървъра.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppScope.read(context).refresh();
  }

  // ---------------------------------------------------------- компютър
  // Широк екран: меню отстрани, а всеки раздел има своя навигация, така че
  // отворените екрани остават в дясната част и менюто винаги се вижда.
  String _dest = 'calendar';
  final _visited = <String>{'calendar'};
  final _navKeys = <String, GlobalKey<NavigatorState>>{};
  String? _chatThread;

  void _go(String d) {
    if (d == _dest) {
      _navKeys[d]?.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _dest = d;
      _visited.add(d);
    });
  }

  Widget _deskPage(String d, AppState s) {
    switch (d) {
      case 'calendar':
        return const CalendarScreen();
      case 'home':
        return HomeScreen(openCalendar: () => _go('calendar'));
      case 'chat':
        return const SizedBox.shrink(); // чатът е на две колони, без вътрешна навигация
      case 'leaves':
        return const LeavesScreen();
      case 'duties':
        return const DutyScreen();
      case 'cash':
        return const CashScreen();
      case 'stock':
        return const StockScreen();
      case 'program':
        return const ProgramDraftScreen();
      default:
        return const ProfileScreen();
    }
  }

  Widget _desktop(BuildContext context, AppState s) {
    final p = Palette.of(context);
    final church = s.currentChurch;
    final items = <DeskNavItem>[
      const DeskNavItem('calendar', Icons.calendar_month_outlined, 'Календар'),
      DeskNavItem('home', Icons.home_outlined, 'Начало', badge: church == null ? 0 : s.waitingIn(church.id)),
      if (s.chatOn) DeskNavItem('chat', Icons.chat_bubble_outline_rounded, 'Чат', badge: s.chatUnreadAll()),
      const DeskNavItem('leaves', Icons.beach_access_outlined, 'Почивки', section: 'Храм'),
      const DeskNavItem('duties', Icons.shield_outlined, 'Дежурства'),
      if (church?.cashEnabled != false) const DeskNavItem('cash', Icons.payments_outlined, 'Каса'),
      if (church?.stockEnabled != false) const DeskNavItem('stock', Icons.inventory_2_outlined, 'Склад'),
      const DeskNavItem('profile', Icons.person_outline_rounded, 'Профил', section: 'Аз'),
      // Проба на програмите за архиерейски служения – само за създателя, само в уеб.
      if (kIsWeb && s.isCreator) const DeskNavItem('program', Icons.directions_car_outlined, 'Програма (проба)'),
    ];
    if (!items.any((i) => i.id == _dest)) _dest = 'home';
    Widget pane(String d) {
      if (d == 'chat') {
        return Row(children: [
          SizedBox(
            width: 380,
            child: ChatListScreen(onOpen: (t) => setState(() => _chatThread = t)),
          ),
          VerticalDivider(width: 1, color: p.border),
          Expanded(
            child: _chatThread == null
                ? Center(
                    child: Text('Изберете разговор отляво.',
                        style: TextStyle(fontSize: 17, color: p.textMuted)))
                : ChatScreen(key: ValueKey(_chatThread), thread: _chatThread!),
          ),
        ]);
      }
      final key = _navKeys.putIfAbsent(d, () => GlobalKey<NavigatorState>());
      // Работните раздели (календар, каса…) са на две колони и заемат ширината;
      // профилът и всички отворени отгоре екрани (събитие, форми, „Кайрос в числа“)
      // стоят в по-тясна колона в средата.
      final t = _DeskTransitions(wideRoot: d != 'profile');
      return Theme(
        data: Theme.of(context).copyWith(
          pageTransitionsTheme: PageTransitionsTheme(builders: {
            for (final pl in TargetPlatform.values) pl: t,
          }),
        ),
        child: Navigator(
          key: key,
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _deskPage(d, s)),
        ),
      );
    }

    final me = s.currentUser;
    final role = church == null
        ? ''
        : s.isManagerOf(church.id)
            ? 'Председател'
            : s.canSeeCash(church.id)
                ? 'Касиер'
                : 'Свещеник';
    final others = s.myChurches.where((c) => c.id != church?.id).toList();
    return DeskFrame(
      logoColor: Palette.yellow,
      onLogo: () {
        _go('calendar');
        _navKeys['calendar']?.currentState?.popUntil((r) => r.isFirst);
        calendarToday.value++;
        s.refresh();
      },
      chipIcon: '⛪',
      chipTitle: church?.name ?? 'Кайрос',
      chipSubtitle: [role, if (church != null) church.settlement].where((x) => x.isNotEmpty).join(' · '),
      chipMenu: [
        for (final c in others)
          DeskMenuAction(Icons.swap_horiz_rounded, 'Към „${c.name}“', () => s.selectChurch(c.id)),
      ],
      searchHint: 'Търсене: събитие, човек, телефон, раздел…',
      search: (q) => _deskSearch(context, s, q),
      bell: church == null ? 0 : s.waitingIn(church.id),
      bellTooltip: 'Чака вас',
      onBell: () => _go('home'),
      userInitials: _initials(me?.name ?? ''),
      userName: me == null ? '' : withRank(me.rank, me.name),
      userMenu: [
        DeskMenuAction(Icons.person_outline_rounded, 'Профил', () => _go('profile')),
        if (s.isMetropolitan) DeskMenuAction(Icons.account_balance_outlined, 'Митрополитски изглед', () => s.setMetroMode(true)),
        DeskMenuAction(Icons.help_outline_rounded, 'Как работи Кайрос',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen()))),
        DeskMenuAction(Icons.refresh_rounded, 'Обнови', s.refresh),
        DeskMenuAction(Icons.logout_rounded, 'Изход', s.logout),
      ],
      items: items,
      current: _dest,
      onSelect: _go,
      footer: 'Кайрос за компютър · Beta',
      banner: s.syncError == null
          ? null
          : Material(
              color: Palette.yellow,
              child: InkWell(
                onTap: s.refresh,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text('${s.syncError} Натиснете, за да опитате пак.',
                      style: const TextStyle(color: Palette.onYellow, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
      body: Container(
        color: p.bg,
        child: IndexedStack(
          index: items.indexWhere((i) => i.id == _dest),
          children: [
            for (final it in items)
              _visited.contains(it.id)
                  ? (it.id == 'chat'
                      ? pane(it.id)
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1320),
                            child: pane(it.id),
                          ),
                        ))
                  : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (w.isEmpty) return '?';
    return (w.first.characters.first + (w.length > 1 ? w.last.characters.first : '')).toUpperCase();
  }

  /// Търсачката горе: разделите, хората в храма и събитията.
  List<SearchHit> _deskSearch(BuildContext context, AppState s, String query) {
    final q = query.trim().toLowerCase();
    final church = s.currentChurch;
    final hits = <SearchHit>[];
    const sections = [
      ('calendar', Icons.calendar_month_outlined, 'Календар'),
      ('home', Icons.home_outlined, 'Начало'),
      ('chat', Icons.chat_bubble_outline_rounded, 'Чат'),
      ('leaves', Icons.beach_access_outlined, 'Почивки'),
      ('duties', Icons.shield_outlined, 'Дежурства'),
      ('cash', Icons.payments_outlined, 'Каса'),
      ('stock', Icons.inventory_2_outlined, 'Склад'),
      ('profile', Icons.person_outline_rounded, 'Профил'),
    ];
    for (final (id, icon, label) in sections) {
      if (q.isEmpty || label.toLowerCase().contains(q)) {
        if (id == 'cash' && church?.cashEnabled == false) continue;
        if (id == 'stock' && church?.stockEnabled == false) continue;
        if (id == 'chat' && !s.chatOn) continue;
        hits.add(SearchHit(icon, label, 'Раздел', () => _go(id)));
      }
    }
    if (q.isEmpty || church == null) return hits;
    final qd = q.replaceAll(' ', '');
    for (final (u, m) in s.membersOf(church.id)) {
      final name = withRank(u.rank, u.name);
      if (name.toLowerCase().contains(q) || (qd.length >= 3 && u.phone.replaceAll(' ', '').contains(qd))) {
        hits.add(SearchHit(Icons.person_outline_rounded, name,
            [if (m.isManager) 'председател', if (m.isCashier) 'касиер', if (u.phone.isNotEmpty) u.phone].join(' · '),
            () => _go('profile')));
      }
    }
    final df = DateFormat('d MMM y, HH:mm', 'bg');
    for (final e in s.search(q).take(25)) {
      hits.add(SearchHit(Icons.event_outlined, e.forWhom.isEmpty ? e.kind.label : '${e.kind.label} · ${e.forWhom}',
          [df.format(e.startsAt), s.priestName(e.assigneeId)].where((x) => x.isNotEmpty).join(' · '), () {
        _go('calendar');
        WidgetsBinding.instance.addPostFrameCallback((_) => _navKeys['calendar']
            ?.currentState
            ?.push(MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: e.id))));
      }));
    }
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    // Истинската ширина на прозореца (не на колоната в средата).
    final view = View.of(context);
    final wide = view.physicalSize.width / view.devicePixelRatio >= 1000;
    if (desktopShell.value != wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) => desktopShell.value = wide);
    }
    if (wide) return _desktop(context, s);
    final pages = [
      RefreshIndicator(onRefresh: s.refresh, child: const CalendarScreen()),
      RefreshIndicator(
        onRefresh: s.refresh,
        child: HomeScreen(openCalendar: () => setState(() => _tab = 0)),
      ),
      const ProfileScreen(),
      RefreshIndicator(onRefresh: s.refresh, child: const ChatListScreen()),
    ];
    final chat = s.chatOn;
    if (!chat && _tab == 3) _tab = 1;
    final unread = chat ? s.chatUnreadAll() : 0;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (s.syncError != null)
              Material(
                color: Palette.yellow,
                child: InkWell(
                  onTap: s.refresh,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.cloud_off_rounded, color: Palette.onYellow),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${s.syncError} Натиснете, за да опитате пак.',
                            style: const TextStyle(
                                fontSize: 15,
                                color: Palette.onYellow,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ),
              ),
            Expanded(child: IndexedStack(index: _tab, children: pages)),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                _NavItem(Icons.calendar_month_outlined, 'Календар', _tab == 0,
                    () => setState(() => _tab = 0)),
                _NavItem(Icons.home_outlined, 'Начало', _tab == 1, () => setState(() => _tab = 1)),
                if (chat)
                  _NavItem(Icons.chat_bubble_outline_rounded, 'Чат', _tab == 3, () => setState(() => _tab = 3),
                      badge: unread),
                _NavItem(Icons.person_outline_rounded, 'Профил', _tab == 2,
                    () => setState(() => _tab = 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;
  const _NavItem(this.icon, this.label, this.active, this.onTap, {this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = active ? p.primary : p.textMuted;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: Icon(icon, size: 26, color: color),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Преходи в изгледа за компютър: всеки екран, освен първия на работен раздел,
/// се показва в колона до 760 точки в средата.
class _DeskTransitions extends PageTransitionsBuilder {
  final bool wideRoot;
  const _DeskTransitions({required this.wideRoot});

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final inner = const FadeUpwardsPageTransitionsBuilder()
        .buildTransitions(route, context, animation, secondaryAnimation, child);
    if (route.isFirst && wideRoot) return inner;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: inner),
    );
  }
}
