import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_detail.dart';
import 'event_form.dart';
import 'leaves.dart';
import 'search.dart';
import '../widgets/requests.dart';

enum CalView { day, week, month }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selected = _dateOnly(DateTime.now());
  CalView _view = CalView.day;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _weekStart =>
      _selected.subtract(Duration(days: _selected.weekday - DateTime.monday));

  void _shift(int dir) {
    setState(() {
      switch (_view) {
        case CalView.day:
        case CalView.week:
          _selected = _dateOnly(_selected.add(Duration(days: 7 * dir)));
        case CalView.month:
          final m = DateTime(_selected.year, _selected.month + dir, 1);
          _selected = m;
      }
    });
  }

  void _openNew() {
    final s = AppScope.read(context);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => EventFormScreen(draft: s.newEventDraft(_selected))));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    List<Color> dotsFor(DateTime d) => [
          for (final id in s.priestsOn(d)) p.priest(s.priestIndex(s.currentChurchId!, id)),
        ];
    final monthTitle = capitalize(DateFormat('LLLL', 'bg').format(_selected));
    final showYear = _selected.year != DateTime.now().year;

    return Stack(
      children: [
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(showYear ? '$monthTitle ${_selected.year}' : monthTitle,
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ),
                _RoundButton(Icons.search_rounded, 'Търсене',
                    () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
                const SizedBox(width: 8),
                _RoundButton(Icons.beach_access_outlined, 'Почивки',
                    () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const LeavesScreen()))),
                const SizedBox(width: 8),
                _RoundButton(Icons.chevron_left_rounded,
                    _view == CalView.month ? 'Предишен месец' : 'Предишна седмица',
                    () => _shift(-1)),
                const SizedBox(width: 8),
                _RoundButton(Icons.chevron_right_rounded,
                    _view == CalView.month ? 'Следващ месец' : 'Следваща седмица',
                    () => _shift(1)),
              ],
            ),
            const SizedBox(height: 14),
            _ViewSwitch(value: _view, onChanged: (v) => setState(() => _view = v)),
            const SizedBox(height: 14),
            if (_view != CalView.month)
              _WeekStrip(
                weekStart: _weekStart,
                selected: _selected,
                dots: dotsFor,
                onSelect: (d) => setState(() => _selected = d),
              )
            else
              _MonthGrid(
                month: _selected,
                selected: _selected,
                dots: dotsFor,
                onSelect: (d) => setState(() {
                  _selected = d;
                  _view = CalView.day;
                }),
              ),
            const SizedBox(height: 14),
            ...requestCards(s),
            if (_view == CalView.day || _view == CalView.month)
              ..._dayList(context, s, p, _selected)
            else
              for (var i = 0; i < 7; i++)
                ..._dayList(context, s, p, _weekStart.add(Duration(days: i)), compact: true),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'new-event',
            onPressed: _openNew,
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
            shape: const StadiumBorder(),
            icon: const Icon(Icons.add_rounded, size: 26),
            label: const Text('Ново събитие',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  List<Widget> _dayList(BuildContext context, AppState s, Palette p, DateTime day,
      {bool compact = false}) {
    final events = s.eventsOn(day);
    final leaves = s.leavesOn(s.currentChurchId!, day);
    if (compact && events.isEmpty && leaves.isEmpty) return [];
    final now = DateTime.now();
    final nextId = s.nextEvent?.id;
    return [
      Padding(
        padding: EdgeInsets.only(bottom: 10, top: compact ? 6 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(fmtDayHeading(day),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Text(eventsCount(events.length), style: TextStyle(fontSize: 14, color: p.textMuted)),
          ],
        ),
      ),
      // Почивки в този ден: одобрените виждат всички, чакащите – председателят и заявилият.
      for (final l in leaves)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: p.chipBg,
              borderRadius: BorderRadius.circular(16),
              border: l.status == LeaveStatus.pending ? Border.all(color: Palette.yellow, width: 2) : null,
            ),
            child: Row(children: [
              Icon(Icons.beach_access_outlined, color: p.chipText),
              const SizedBox(width: 10),
              PriestBadge(
                  name: s.priestName(l.userId), color: p.priest(s.priestIndex(l.churchId, l.userId)), size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '${s.priestName(l.userId)} – почивка'
                    '${l.start == l.end ? '' : ' (${fmtLeavePeriod(l)})'}'
                    '${l.status == LeaveStatus.pending ? ' · чака одобрение' : ''}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.chipText)),
              ),
            ]),
          ),
        ),
      if (events.isEmpty)
        SurfaceCard(
          radius: 20,
          child: Text('Няма събития за този ден.',
              style: TextStyle(fontSize: 17, color: p.textMuted)),
        ),
      for (final e in events)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _EventRow(
            event: e,
            past: e.startsAt.isBefore(now) || e.isCancelled,
            isNext: e.id == nextId,
            // Кой е записал – вижда се от всички.
            owner: e.ownerId == s.currentUser?.id ? 'записах аз' : 'записа ${s.ownerName(e)}',
            confirmation: e.awaitsConfirmation
                ? 'чака потвърждение от ${s.priestName(e.assigneeId)}'
                : e.isDeclined
                    ? 'отказано – решава председателят'
                    : null,
            priestName: s.priestName(e.assigneeId),
            priestColor: p.priest(s.priestIndex(e.churchId, e.assigneeId)),
            forMe: s.isMine(e),
            overlapping: (s.canEdit(e) && s.overlapsFor(e).isNotEmpty) ||
                s.placeOverlapsFor(e).isNotEmpty,
          ),
        ),
    ];
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 26),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        backgroundColor: p.surface,
        foregroundColor: p.text,
        side: BorderSide(color: p.border),
      ),
    );
  }
}

class _ViewSwitch extends StatelessWidget {
  final CalView value;
  final ValueChanged<CalView> onChanged;
  const _ViewSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget item(CalView v, String label) {
      final active = v == value;
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          child: Material(
            color: active ? p.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(v),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                          color: active ? p.onPrimary : p.chipText)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        item(CalView.day, 'Ден'),
        const SizedBox(width: 4),
        item(CalView.week, 'Седмица'),
        const SizedBox(width: 4),
        item(CalView.month, 'Месец'),
      ]),
    );
  }
}

const _weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool selected;
  final List<Color> dots;
  final bool dimmed;
  final VoidCallback onTap;
  const _DayCell(
      {required this.day,
      required this.selected,
      required this.dots,
      required this.onTap,
      this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final today = sameDay(day, DateTime.now());
    final label = DateFormat('EEEE, d MMMM', 'bg').format(day) +
        (today ? ', днес' : '') +
        (selected ? ', избран' : '') +
        (dots.isNotEmpty ? ', има събития' : '');
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkResponse(
            onTap: onTap,
            radius: 22,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? p.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: today && !selected ? Border.all(color: p.primary, width: 2) : null,
              ),
              child: Text('${day.day}',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: selected || today ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? p.onPrimary
                          : dimmed
                              ? p.textMuted.withValues(alpha: 0.5)
                              : p.text)),
            ),
          ),
          const SizedBox(height: 2),
          // Точки под деня: по една в цвета на всеки свещеник със събитие.
          SizedBox(
            height: 7,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in dots.take(3))
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final DateTime weekStart;
  final DateTime selected;
  final List<Color> Function(DateTime) dots;
  final ValueChanged<DateTime> onSelect;
  const _WeekStrip(
      {required this.weekStart,
      required this.selected,
      required this.dots,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SurfaceCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 7; i++)
            Builder(builder: (context) {
              final d = weekStart.add(Duration(days: i));
              final today = sameDay(d, DateTime.now());
              return Column(
                children: [
                  Text(_weekdayShort[i],
                      style: TextStyle(
                          fontSize: 13,
                          color: today ? p.text : p.textMuted,
                          fontWeight: today ? FontWeight.w700 : FontWeight.w400)),
                  const SizedBox(height: 2),
                  _DayCell(
                    day: d,
                    selected: sameDay(d, selected),
                    dots: dots(d),
                    onTap: () => onSelect(d),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final List<Color> Function(DateTime) dots;
  final ValueChanged<DateTime> onSelect;
  const _MonthGrid(
      {required this.month,
      required this.selected,
      required this.dots,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - DateTime.monday));
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((first.weekday - 1) + daysInMonth + 6) ~/ 7 * 7;
    return SurfaceCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final w in _weekdayShort)
                SizedBox(
                  width: 44,
                  child: Text(w,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: p.textMuted)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < cells ~/ 7; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var col = 0; col < 7; col++)
                    Builder(builder: (context) {
                      final d = DateTime(start.year, start.month, start.day + row * 7 + col);
                      return SizedBox(
                        width: 44,
                        child: _DayCell(
                          day: d,
                          selected: sameDay(d, selected),
                          dots: dots(d),
                          dimmed: d.month != month.month,
                          onTap: () => onSelect(d),
                        ),
                      );
                    }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final ChurchEvent event;
  final bool past;
  final bool isNext;
  final String? owner;
  final bool overlapping;
  final String priestName;
  final Color priestColor;
  final bool forMe;
  final String? confirmation;
  const _EventRow(
      {required this.event,
      required this.past,
      required this.isNext,
      this.owner,
      this.overlapping = false,
      required this.priestName,
      required this.priestColor,
      required this.forMe,
      this.confirmation});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final e = event;
    final until = isNext ? timeUntil(e.startsAt) : null;
    final dark = isNext; // следващото събитие е в тъмна карта
    final mainColor = dark ? Colors.white : (past ? p.textMuted : p.text);
    final subColor = dark ? p.heroMuted : p.textMuted;
    final details = [
      e.placeLabel,
      if (e.shared) 'споделено с храма',
      if (!forMe) priestName,
      if (confirmation != null) confirmation!,
      if (owner != null) owner!,
      if (e.isCancelled)
        'отменено'
      else if (e.isDone)
        'проведено'
      else if (past)
        'приключило',
    ].join(' · ');

    return Material(
      color: dark ? p.heroBg : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dark ? p.heroBorder : p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: e.id))),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: dark ? 14 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtTime(e.startsAt),
                        style: TextStyle(
                            fontSize: dark ? 24 : 20,
                            fontWeight: FontWeight.w800,
                            color: past ? p.textMuted : mainColor)),
                    Text('до ${fmtTime(e.endsAt)}',
                        style: TextStyle(fontSize: 13, color: subColor)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        KindChip(e.kind),
                        const Spacer(),
                        if (until != null) YellowTag(until),
                        const SizedBox(width: 8),
                        PriestBadge(name: priestName, color: priestColor, size: 30),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(e.forWhom.isEmpty ? e.kind.label : e.forWhom,
                        style: TextStyle(
                            fontSize: dark ? 19 : 17,
                            fontWeight: FontWeight.w700,
                            color: e.isCancelled ? p.textMuted : mainColor,
                            decoration: e.isCancelled ? TextDecoration.lineThrough : null)),
                    Text(details, style: TextStyle(fontSize: 14, color: subColor)),
                    if (overlapping && !past && !e.isCancelled)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18, color: dark ? Palette.yellow : const Color(0xFF8A5A00)),
                          const SizedBox(width: 4),
                          Text('Застъпване (свещеник или храм)',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: dark
                                      ? Palette.yellow
                                      : (p.dark ? const Color(0xFFEBCF9C) : const Color(0xFF8A5A00)))),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
