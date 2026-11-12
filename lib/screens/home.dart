import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_detail.dart';
import 'church_priests.dart';
import 'my_profile.dart';
import 'event_form.dart';

/// Начален екран – табло, вариант Б.
class HomeScreen extends StatelessWidget {
  final VoidCallback openCalendar;
  const HomeScreen({super.key, required this.openCalendar});

  void _pickChurch(BuildContext context) {
    final s = AppScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in s.myChurches)
              ListTile(
                minTileHeight: 56,
                title: Text(c.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                subtitle: Text(c.place),
                trailing: c.id == s.currentChurchId ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  s.selectChurch(c.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

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
                Flexible(
                  child: OutlinedButton(
                    onPressed: s.myChurches.length > 1 ? () => _pickChurch(context) : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      foregroundColor: p.text,
                      backgroundColor: p.surface,
                      disabledForegroundColor: p.text,
                      side: BorderSide(color: p.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(s.currentChurch!.name, overflow: TextOverflow.ellipsis),
                        ),
                        if (s.myChurches.length > 1) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.expand_more_rounded, size: 20),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PriestsStrip(churchId: s.currentChurchId!),
            const SizedBox(height: 12),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _SoonTile(Icons.menu_book_outlined, 'Регистър')),
                        SizedBox(height: 12),
                        Expanded(child: _SoonTile(Icons.payments_outlined, 'Каса')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(
              height: 112,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _SoonTile(Icons.inventory_2_outlined, 'Склад')),
                  SizedBox(width: 12),
                  Expanded(child: _SoonTile(Icons.description_outlined, 'Отчети')),
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
                  Text('Календар',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: p.onCalendarTile)),
                ],
              ),
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
  const _SoonTile(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: '$label, скоро',
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
                  child: Text('Скоро',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: p.chipText)),
                ),
              ],
            ),
            Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                      name: u.fullName, color: p.priest(s.priestIndex(churchId, u.id)), size: 34),
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
