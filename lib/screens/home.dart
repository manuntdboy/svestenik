import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_detail.dart';
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
    final todayCount = s.eventsOn(now).length;
    final next = s.nextEvent;

    return Stack(
      children: [
        ListView(
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
                      Text(s.currentUser!.fullName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
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
            const SizedBox(height: 14),
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
                  Text(count == 1 ? 'събитие днес' : 'събития днес',
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
