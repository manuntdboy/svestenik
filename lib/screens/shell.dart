import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/notifier.dart';
import '../theme.dart';
import 'alarm_ring.dart';
import 'calendar.dart';
import 'cash.dart';
import 'stock.dart';
import 'event_detail.dart';
import 'leaves.dart';
import 'chat.dart';
import 'duties.dart';
import 'home.dart';
import 'profile.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Notifier.requestPermissions();
      _openFromNotification();
    });
    Notifier.opened.addListener(_openFromNotification);
    _ringing = Alarm.ringing.listen(_onRinging);
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
      nav.push(MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)));
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

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
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
    final unread = chat ? s.chatUnreadTotal(s.currentChurchId!) : 0;
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
