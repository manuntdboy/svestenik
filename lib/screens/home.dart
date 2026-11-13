import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_detail.dart';
import 'church_priests.dart';
import 'my_profile.dart';
import '../widgets/requests.dart';
import '../widgets/whats_new.dart';
import '../widgets/church_banner.dart';
import 'event_form.dart';
import 'cash.dart';
import 'stock.dart';

/// Начален екран – табло, вариант Б.
class HomeScreen extends StatelessWidget {
  final VoidCallback openCalendar;
  const HomeScreen({super.key, required this.openCalendar});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final now = DateTime.now();
    final todayCount = s.eventsOn(now).where((e) => s.isMine(e) && !e.isCancelled).length;
    final next = s.nextEvent;

    return Stack(
      children: [
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDayLong(now),
                          style: TextStyle(
                              fontSize: 15, color: p.textMuted, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const MyProfileScreen())),
                        child: Text(s.currentUser!.fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Камбанката „Какво е новото“ – само в тестовите версии.
                if (isTestBuild) ...[
                  const WhatsNewBell(),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const ChurchBanner(),
            const SizedBox(height: 12),
            _PriestsStrip(churchId: s.currentChurchId!),
            const SizedBox(height: 12),
            // Моля, потвърдете · отказани събития · заявки за почивка
            ...requestCards(s),
            if (s.isManagerOf(s.currentChurchId!))
              for (final (u, _) in s.pendingRequests(s.currentChurchId!))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PendingCard(churchId: s.currentChurchId!, user: u),
                ),
            _NextEventCard(event: next),
            const SizedBox(height: 14),
            SizedBox(
              height: 124 * 2 + 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _CalendarTile(count: todayCount, onTap: openCalendar)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Каса: председател и касиер – цялата; свещеник – предава приходи.
                        Expanded(child: _CashTile(churchId: s.currentChurchId!)),
                        const SizedBox(height: 12),
                        Expanded(child: _StockTile(churchId: s.currentChurchId!)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NextEventCard extends StatelessWidget {
  final ChurchEvent? event;
  const _NextEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final e = event;
    final until = e == null ? null : timeUntil(e.startsAt);
    return Material(
      color: p.heroBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: p.heroBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (e != null) {
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: e.id)));
          } else {
            final s = AppScope.read(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EventFormScreen(draft: s.newEventDraft(DateTime.now()))));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('СЛЕДВАЩО СЪБИТИЕ',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: p.heroMuted,
                              letterSpacing: 0.4)),
                    ),
                    if (until != null) YellowTag(until),
                  ],
                ),
                const SizedBox(height: 14),
                if (e == null) ...[
                  const Text('Няма предстоящи събития',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Натиснете тук, за да добавите събитие.',
                      style: TextStyle(fontSize: 15, color: p.heroMuted)),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtTime(e.startsAt),
                          style: const TextStyle(
                              fontSize: 60,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -2)),
                      const SizedBox(width: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: KindChip(e.kind, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(e.forWhom.isEmpty ? e.kind.label : e.forWhom,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  Text(
                      sameDay(e.startsAt, DateTime.now())
                          ? e.placeLabel
                          : '${fmtDayLong(e.startsAt)} · ${e.placeLabel}',
                      style: TextStyle(fontSize: 15, color: p.heroMuted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _CalendarTile({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.calendarTile,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: p.onCalendarTile.withValues(alpha: p.dark ? 0.12 : 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.calendar_month_outlined, size: 30, color: p.onCalendarTile),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count',
                      style: TextStyle(
                          fontSize: 44,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: p.onCalendarTile)),
                  const SizedBox(height: 2),
                  Text(count == 1 ? 'ваше събитие днес' : 'ваши събития днес',
                      style: TextStyle(fontSize: 15, color: p.calendarTileMuted)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text('Календар',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700, color: p.onCalendarTile)),
                    const SizedBox(width: 8),
                    // Днешната дата като дд.мм.
                    Text(
                        '${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')}.',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800, color: p.onCalendarTile)),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashTile extends StatelessWidget {
  final String churchId;
  const _CashTile({required this.churchId});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final holder = s.canSeeCash(churchId);
    final waiting = holder ? s.cashToDecide(churchId).length : 0;
    final (cash, bank) = cashBalance(s.cashEntries(churchId));
    final negative = holder && cash + bank < 0;
    final pending = holder && s.cashEntries(churchId).any((e) => e.isPending);
    return Material(
      color: negative ? const Color(0xFFB23A3A).withValues(alpha: p.dark ? .30 : .14) : p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
              color: pending ? Palette.yellow : (negative ? const Color(0xFFB23A3A) : p.border),
              width: pending || negative ? 3 : 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.payments_outlined, size: 22, color: p.chipText),
                ),
                const Spacer(),
                if (waiting > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Palette.yellow, borderRadius: BorderRadius.circular(11)),
                    child: Text('$waiting чака',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: Palette.onYellow)),
                  ),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Каса', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(holder ? 'в брой ${fmtEur(cash)}' : 'Предай приход',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: negative ? const Color(0xFFB23A3A) : p.textMuted,
                        fontWeight: negative ? FontWeight.w800 : FontWeight.w400)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  final String churchId;
  const _StockTile({required this.churchId});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final holder = s.canSeeCash(churchId);
    if (!holder) return const _SoonTile(Icons.inventory_2_outlined, 'Склад', locked: true);
    final low = s.lowStock(churchId);
    final bal = s.stockOf(churchId);
    final out = low.any((i) => bal[i]! <= 0);
    final waiting = s.stockToDecide(churchId).length;
    final warn = out ? const Color(0xFFB23A3A) : (low.isNotEmpty || waiting > 0 ? Palette.yellow : null);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: warn ?? p.border, width: warn != null ? 3 : 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.inventory_2_outlined, size: 22, color: p.chipText),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Склад', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                    waiting > 0
                        ? '$waiting чака одобрение'
                        : low.isEmpty
                            ? 'Наличностите са наред'
                            : 'Заредете: ${low.length} ${low.length == 1 ? 'вид' : 'вида'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: out ? const Color(0xFFB23A3A) : p.textMuted,
                        fontWeight: low.isEmpty && waiting == 0 ? FontWeight.w400 : FontWeight.w700)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoonTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool locked;
  const _SoonTile(this.icon, this.label, {this.locked = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: locked ? '$label, само за председател и касиер' : '$label, скоро',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration:
                      BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 22, color: p.chipText),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration:
                      BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(11)),
                  child: locked
                      ? Icon(Icons.lock_outline_rounded, size: 16, color: p.chipText)
                      : Text('Скоро',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: p.chipText)),
                ),
              ],
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (locked)
                Text('Председател и касиер',
                    style: TextStyle(fontSize: 13, color: p.textMuted)),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Ред с цветните знаци на свещениците в храма; отваря списъка им.
class _PriestsStrip extends StatelessWidget {
  final String churchId;
  const _PriestsStrip({required this.churchId});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final priests = s.priestsOf(churchId);
    final myColor = p.priest(s.priestIndex(churchId, s.currentUser!.id));
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ChurchPriestsScreen(churchId: churchId))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Свещеници в храма',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Builder(builder: (context) {
                      final now = DateTime.now();
                      final resting = s
                          .leavesOn(churchId, now)
                          .where((l) => l.status == LeaveStatus.approved)
                          .map((l) => s.priestName(l.userId))
                          .toList();
                      if (resting.isEmpty) return const SizedBox.shrink();
                      return Row(children: [
                        Icon(Icons.beach_access_rounded, size: 16, color: p.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text('Днес почива: ${resting.join(', ')}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.textMuted)),
                        ),
                      ]);
                    }),
                    Row(children: [
                      Text('Вашият цвят ', style: TextStyle(fontSize: 14, color: p.textMuted)),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: myColor, shape: BoxShape.circle),
                      ),
                    ]),
                  ],
                ),
              ),
              for (final (u, _) in priests.take(5))
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: PriestBadge(
                      name: u.fullName, color: p.priest(s.priestIndex(churchId, u.id)), size: 34, userId: u.id),
                ),
              if (priests.length > 5)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('+${priests.length - 5}',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.textMuted)),
                ),
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// „Чакат одобрение“: свещеник, въвел кода на храма (вижда го председателят).
class _PendingCard extends StatefulWidget {
  final String churchId;
  final AppUser user;
  const _PendingCard({required this.churchId, required this.user});

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard> {
  bool _busy = false;

  Future<void> _act(bool approve) async {
    final s = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!approve) {
      final ok = await confirm(context, 'Отказ',
          '${widget.user.fullName} няма да бъде добавен в храма.', 'Откажи');
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      if (approve) {
        await s.approveMember(widget.churchId, widget.user.id);
        messenger.showSnackBar(SnackBar(content: Text('${widget.user.fullName} е одобрен.')));
      } else {
        await s.declineMember(widget.churchId, widget.user.id);
      }
    } on AppError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.yellow, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const YellowTag('Чака одобрение'),
            const Spacer(),
            Icon(Icons.person_add_alt_1_rounded, color: p.textMuted),
          ]),
          const SizedBox(height: 10),
          Text(widget.user.fullName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (widget.user.username.isNotEmpty)
            Text('@${widget.user.username}', style: TextStyle(fontSize: 15, color: p.textMuted)),
          Text('въведе кода на храма и иска да се присъедини',
              style: TextStyle(fontSize: 15, color: p.textMuted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _act(false),
                child: const Text('Откажи'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : () => _act(true),
                child: const Text('Одобри'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
