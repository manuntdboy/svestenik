import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/church_banner.dart';
import '../widgets/common.dart';
import '../widgets/requests.dart';

final _dm = DateFormat('d MMM', 'bg');
final _dmy = DateFormat('d MMMM y', 'bg');

String fmtDutyPeriod(DateTime a, DateTime b) {
  if (a == b) return _dm.format(a);
  if (a.month == b.month && a.year == b.year) return '${a.day} – ${_dm.format(b)}';
  return '${_dm.format(a)} – ${_dm.format(b)}';
}

String _month(DateTime d) => DateFormat('LLLL y', 'bg').format(d);

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// „Дежурен тази седмица“ – видимо за всички в храма (Начало и графика).
class DutyNowCard extends StatelessWidget {
  final bool compact;
  const DutyNowCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId;
    if (church == null) return const SizedBox.shrink();
    final now = s.currentDuty(church);
    final next = s.nextDuty(church);
    final manager = s.isManagerOf(church);
    if (now == null && next == null) {
      if (!manager || !compact) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DutyScreen())),
          icon: const Icon(Icons.event_repeat_rounded),
          label: const Text('Направете график на дежурствата'),
        ),
      );
    }
    final d = now ?? next!;
    final color = p.priest(s.priestIndex(church, d.userId));
    final user = s.membersOf(church).where((m) => m.$1.id == d.userId).firstOrNull?.$1;
    final mine = d.userId == s.currentUser?.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color.withValues(alpha: p.dark ? .22 : .13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: color, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: compact
              ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DutyScreen()))
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              PriestBadge(name: s.priestName(d.userId), color: color, size: 42, userId: d.userId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(now != null ? (mine ? 'Вие сте дежурен' : 'Дежурен') : 'Следващ дежурен',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.textMuted, letterSpacing: .3)),
                  Text(s.priestName(d.userId),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(fmtDutyPeriod(d.start, d.end), style: const TextStyle(fontSize: 14.5)),
                ]),
              ),
              if (!mine && (user?.phone ?? '').isNotEmpty)
                IconButton(
                  tooltip: 'Обади се',
                  onPressed: () => ContactButtons.call(context, user!.phone),
                  icon: const Icon(Icons.call_rounded),
                ),
              if (compact) Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Раздел „График на дежурствата“.
class DutyScreen extends StatefulWidget {
  const DutyScreen({super.key});

  @override
  State<DutyScreen> createState() => _DutyScreenState();
}

class _DutyScreenState extends State<DutyScreen> {
  bool _past = false;
  DateTime _shown = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final manager = s.isManagerOf(church);
    final today = _today();
    final all = s.dutiesOf(church);
    final list = _past
        ? all.where((d) => d.end.isBefore(today)).toList().reversed.toList()
        : all.where((d) => !d.end.isBefore(today)).toList();
    final mySwaps = s.swapsOf(church).where((w) => w.fromUser == s.currentUser?.id).take(6).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('График на дежурствата')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const ChurchBanner(title: 'Дежурства'),
              const SizedBox(height: 12),
              const DutyNowCard(),
              // Месец с датите в цвета на дежурния.
              _DutyMonth(
                month: _shown,
                onShift: (d) => setState(() => _shown = DateTime(_shown.year, _shown.month + d, 1)),
              ),
              const SizedBox(height: 12),
              for (final w in s.swapsForMe(church))
                Padding(padding: const EdgeInsets.only(bottom: 12), child: DutySwapCard(swap: w)),
              for (final w in s.swapsForChair(church))
                Padding(padding: const EdgeInsets.only(bottom: 12), child: DutySwapCard(swap: w)),
              if (manager) ...[
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => showDutyForm(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Дежурство'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const DutySeriesScreen())),
                      icon: const Icon(Icons.event_repeat_rounded),
                      label: const Text('Серия по ред'),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text('Вие избирате началото и края – всеки храм сменя дежурството в свой ден.',
                    style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                const SizedBox(height: 12),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Графика прави председателят. Можете да предложите размяна на свое дежурство '
                      '– натиснете го в списъка.',
                      style: TextStyle(fontSize: 14.5, color: p.textMuted)),
                ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Предстоящи')),
                  ButtonSegment(value: true, label: Text('Минали')),
                ],
                selected: {_past},
                onSelectionChanged: (v) => setState(() => _past = v.first),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Text(_past ? 'Няма минали дежурства.' : 'Няма предстоящи дежурства.',
                    style: TextStyle(fontSize: 16, color: p.textMuted)),
              for (final (i, d) in list.indexed) ...[
                if (i == 0 || _month(list[i - 1].start) != _month(d.start))
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(capitalize(_month(d.start)),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                _DutyRow(duty: d),
              ],
              if (mySwaps.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Моите молби за размяна', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final w in mySwaps) _MySwapRow(swap: w),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DutyRow extends StatelessWidget {
  final Duty duty;
  const _DutyRow({required this.duty});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final d = duty;
    final church = d.churchId;
    final color = p.priest(s.priestIndex(church, d.userId));
    final today = _today();
    final current = d.covers(today);
    final leave = s.leaveConflict(church, d.userId, d.start, d.end);
    final swap = s.openSwapFor(d.id);
    final manager = s.isManagerOf(church);
    final mine = d.userId == s.currentUser?.id;
    final future = !d.end.isBefore(today);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: current ? color : p.border, width: current ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: manager
              ? () => showDutyForm(context, duty: d)
              : (mine && future && swap == null)
                  ? () => showSwapSheet(context, d)
                  : null,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 8, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(fmtDutyPeriod(d.start, d.end),
                            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                      ),
                      Text(d.days == 1 ? '1 ден' : '${d.days} дни', style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                    ]),
                    const SizedBox(height: 2),
                    Text(s.priestName(d.userId), style: const TextStyle(fontSize: 15.5)),
                    if (d.note.isNotEmpty) Text(d.note, style: TextStyle(fontSize: 14, color: p.textMuted)),
                    if (current)
                      Text('дежурен сега', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
                    if (leave != null && future)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            'В почивка ${fmtLeavePeriod(leave)}${manager ? ' – натиснете, за да смените дежурния' : ''}',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error)),
                      ),
                    if (swap != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Размяна: ${swap.statusLabel}',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFFB7791F))),
                      ),
                    if (!manager && mine && future && swap == null)
                      Text('Натиснете, за да предложите размяна',
                          style: TextStyle(fontSize: 13, color: p.textMuted)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MySwapRow extends StatelessWidget {
  final DutySwap swap;
  const _MySwapRow({required this.swap});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final w = swap;
    final a = s.dutyById(w.fromDuty);
    final b = s.dutyById(w.toDuty);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${a == null ? '' : fmtDutyPeriod(a.start, a.end)} ⇄ ${b == null ? '' : fmtDutyPeriod(b.start, b.end)}',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              Text('с ${s.priestName(w.toUser)} · ${w.statusLabel}', style: TextStyle(fontSize: 14, color: p.textMuted)),
              if (w.reason.isNotEmpty)
                Text('„${w.reason}“', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
            ]),
          ),
          if (w.isOpen)
            TextButton(
              onPressed: () async {
                final ok = await confirm(context, 'Оттегли молбата?', 'Размяната няма да стане.', 'Оттегли');
                if (!ok || !context.mounted) return;
                try {
                  await s.cancelSwap(w);
                } on AppError catch (e) {
                  if (context.mounted) showMessage(context, e.message);
                }
              },
              child: const Text('Оттегли'),
            ),
        ]),
      ),
    );
  }
}

/// Добавяне или промяна на дежурство (председателят).
Future<void> showDutyForm(BuildContext context, {Duty? duty, DateTime? day}) async {
  final s = AppScope.read(context);
  final church = s.currentChurchId!;
  final priests = s.priestsOf(church).where((m) => m.$2.isActive).map((m) => m.$1).toList();
  if (priests.isEmpty) return;
  String user = duty?.userId ?? priests.first.id;
  DateTime? start = duty?.start ?? day;
  DateTime? end = duty?.end ?? day?.add(const Duration(days: 6));
  final note = TextEditingController(text: duty?.note ?? '');
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final p = Palette.of(ctx);
      final leave = start == null ? null : s.leaveConflict(church, user, start!, end!);
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(duty == null ? 'Ново дежурство' : 'Дежурство',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: user,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Дежурен свещеник'),
              items: [
                for (final u in priests)
                  DropdownMenuItem(
                    value: u.id,
                    child: Row(children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration:
                            BoxDecoration(color: p.priest(s.priestIndex(church, u.id)), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(u.fullName, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
              ],
              onChanged: (v) => set(() => user = v ?? user),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                final r = await showDateRangePicker(
                  context: ctx,
                  firstDate: DateTime(DateTime.now().year - 1),
                  lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                  initialDateRange: start == null ? null : DateTimeRange(start: start!, end: end!),
                  helpText: 'От кой до кой ден (включително)',
                  saveText: 'Избери',
                  initialEntryMode: DatePickerEntryMode.calendarOnly,
                );
                if (r != null) {
                  set(() {
                    start = DateTime(r.start.year, r.start.month, r.start.day);
                    end = DateTime(r.end.year, r.end.month, r.end.day);
                  });
                }
              },
              icon: const Icon(Icons.date_range_rounded),
              label: Text(start == null
                  ? 'Изберете дните'
                  : '${_dmy.format(start!)} – ${_dmy.format(end!)} · ${end!.difference(start!).inDays + 1} дни'),
            ),
            if (leave != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                    '${s.priestName(user)} е в одобрена почивка ${fmtLeavePeriod(leave)}. Изберете друг свещеник или други дни.',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Бележка (по желание)'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: start == null
                  ? null
                  : () async {
                      if (leave != null) {
                        final ok = await confirm(ctx, 'Свещеникът е в почивка',
                            'Да го запиша ли въпреки това като дежурен?', 'Запиши');
                        if (!ok) return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx, 'save');
                    },
              child: const Text('Запази'),
            ),
            if (duty != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final ok = await confirm(ctx, 'Изтриване на дежурството?',
                      '${s.priestName(duty.userId)} · ${fmtDutyPeriod(duty.start, duty.end)}', 'Изтрий');
                  if (ok && ctx.mounted) Navigator.pop(ctx, 'delete');
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Изтрий дежурството'),
              ),
            ],
          ]),
        ),
      );
    }),
  );
  final text = note.text;
  note.dispose();
  if (result == null || !context.mounted) return;
  try {
    if (result == 'delete') {
      await s.deleteDuty(duty!);
      if (context.mounted) showMessage(context, 'Дежурството е изтрито.');
    } else if (duty == null) {
      await s.addDuty(church, user, start!, end!, text);
      if (context.mounted) showMessage(context, 'Дежурството е записано. Свещеникът ще получи известие.');
    } else {
      await s.updateDuty(duty, user, start!, end!, text);
      if (context.mounted) showMessage(context, 'Дежурството е променено.');
    }
  } on AppError catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

/// Свещеникът предлага размяна на свое дежурство с дежурство на колега.
Future<void> showSwapSheet(BuildContext context, Duty mine) async {
  final s = AppScope.read(context);
  final today = _today();
  final others = s
      .dutiesOf(mine.churchId)
      .where((d) => d.userId != mine.userId && !d.end.isBefore(today) && s.openSwapFor(d.id) == null)
      .toList();
  if (others.isEmpty) {
    showMessage(context, 'Няма предстоящи дежурства на колеги, с които да се разменят.');
    return;
  }
  final picked = await showModalBottomSheet<Duty>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final p = Palette.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
            Text('Размяна на ${fmtDutyPeriod(mine.start, mine.end)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Изберете дежурството на колега. Той трябва да приеме, после одобрява председателят.',
                style: TextStyle(fontSize: 14.5, color: p.textMuted)),
            const SizedBox(height: 10),
            for (final d in others)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PriestBadge(
                    name: s.priestName(d.userId), color: p.priest(s.priestIndex(d.churchId, d.userId)), size: 34),
                title: Text(fmtDutyPeriod(d.start, d.end), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(s.priestName(d.userId)),
                onTap: () => Navigator.pop(ctx, d),
              ),
          ]),
        ),
      );
    },
  );
  if (picked == null || !context.mounted) return;
  final note = await askComment(context,
      title: 'Молба за размяна',
      body: 'Вашето ${fmtDutyPeriod(mine.start, mine.end)} ⇄ ${fmtDutyPeriod(picked.start, picked.end)} '
          'на ${s.priestName(picked.userId)}.',
      hint: 'Причина (по желание), напр. „Имам сватба в родното село“',
      action: 'Изпрати');
  if (note == null || !context.mounted) return;
  try {
    await s.requestSwap(mine, picked, note);
    if (context.mounted) showMessage(context, 'Молбата е изпратена на ${s.priestName(picked.userId)}.');
  } on AppError catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

/// Серия дежурства по ред: начало, дни на смяна, свещениците по ред, брой.
class DutySeriesScreen extends StatefulWidget {
  const DutySeriesScreen({super.key});

  @override
  State<DutySeriesScreen> createState() => _DutySeriesScreenState();
}

class _DutySeriesScreenState extends State<DutySeriesScreen> {
  DateTime? _start;
  int _days = 7;
  int _count = 12;
  List<String> _order = [];
  final Set<String> _on = {};
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_order.isEmpty) {
      final s = AppScope.read(context);
      _order = s.priestsOf(s.currentChurchId!).where((m) => m.$2.isActive).map((m) => m.$1.id).toList();
      _on.addAll(_order);
      // Начало по подразбиране – денят след последното дежурство.
      final all = s.dutiesOf(s.currentChurchId!);
      if (all.isNotEmpty) {
        final last = all.map((d) => d.end).reduce((a, b) => a.isAfter(b) ? a : b);
        if (!last.isBefore(_today())) _start = last.add(const Duration(days: 1));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final users = _order.where(_on.contains).toList();
    final endAll = _start?.add(Duration(days: _days * _count - 1));
    final conflicts = <String>[];
    if (_start != null && users.isNotEmpty) {
      for (var i = 0; i < _count; i++) {
        final a = _start!.add(Duration(days: i * _days));
        final b = a.add(Duration(days: _days - 1));
        final u = users[i % users.length];
        final l = s.leaveConflict(church, u, a, b);
        if (l != null) conflicts.add('${fmtDutyPeriod(a, b)} – ${s.priestName(u)} е в почивка');
        if (s.dutiesOf(church).any((d) => d.overlaps(a, b))) {
          conflicts.add('${fmtDutyPeriod(a, b)} – вече има дежурен');
        }
      }
    }
    final overlap = conflicts.any((c) => c.endsWith('вече има дежурен'));

    Widget stepper(String label, int value, int min, int max, ValueChanged<int> on) => Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          IconButton(onPressed: value > min ? () => on(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(
              width: 36,
              child: Text('$value',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(onPressed: value < max ? () => on(value + 1) : null, icon: const Icon(Icons.add_circle_outline)),
        ]);

    return Scaffold(
      appBar: AppBar(title: const Text('Серия дежурства')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Свещениците поемат дежурството по ред, всеки за избрания брой дни.',
                style: TextStyle(fontSize: 15, color: p.textMuted)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _start ?? _today(),
                  firstDate: DateTime(DateTime.now().year - 1),
                  lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                  helpText: 'Първи ден на първото дежурство',
                );
                if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day));
              },
              icon: const Icon(Icons.event_rounded),
              label: Text(_start == null
                  ? 'Първи ден (напр. понеделник или събота)'
                  : 'От ${DateFormat('EEEE, d MMMM y', 'bg').format(_start!)}'),
            ),
            const SizedBox(height: 8),
            stepper('Дни на едно дежурство', _days, 1, 31, (v) => setState(() => _days = v)),
            stepper('Брой дежурства', _count, 1, 104, (v) => setState(() => _count = v)),
            if (endAll != null)
              Text('До ${_dmy.format(endAll)}', style: TextStyle(fontSize: 14.5, color: p.textMuted)),
            const SizedBox(height: 14),
            const Text('Ред на свещениците', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text('Отметнете кои участват; стрелките сменят реда.', style: TextStyle(fontSize: 14, color: p.textMuted)),
            const SizedBox(height: 6),
            for (var i = 0; i < _order.length; i++)
              Builder(builder: (_) {
                final id = _order[i];
                return Row(children: [
                  Checkbox(
                    value: _on.contains(id),
                    onChanged: (v) => setState(() => v == true ? _on.add(id) : _on.remove(id)),
                  ),
                  PriestBadge(name: s.priestName(id), color: p.priest(s.priestIndex(church, id)), size: 30),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.priestName(id), style: const TextStyle(fontSize: 15.5))),
                  IconButton(
                    tooltip: 'Нагоре',
                    onPressed: i == 0
                        ? null
                        : () => setState(() {
                              _order.removeAt(i);
                              _order.insert(i - 1, id);
                            }),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  IconButton(
                    tooltip: 'Надолу',
                    onPressed: i == _order.length - 1
                        ? null
                        : () => setState(() {
                              _order.removeAt(i);
                              _order.insert(i + 1, id);
                            }),
                    icon: const Icon(Icons.arrow_downward_rounded),
                  ),
                ]);
              }),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Внимание', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  for (final c in conflicts.take(8)) Text('• $c', style: const TextStyle(fontSize: 14.5)),
                  if (!overlap)
                    Text('Можете да запишете серията и после да смените дежурния в тези дни.',
                        style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: _busy || _start == null || users.isEmpty || overlap
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await s.addDutySeries(church, _start!, _days, users, _count);
                        if (context.mounted) {
                          showMessage(context, 'Графикът е записан. Свещениците ще получат известие.');
                          Navigator.pop(context);
                        }
                      } on AppError catch (e) {
                        if (context.mounted) showMessage(context, e.message);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Text('Запиши $_count дежурства'),
            ),
          ],
        ),
      ),
    );
  }
}


/// Месечен календар на графика: датите са в цвета на дежурния свещеник.
class _DutyMonth extends StatelessWidget {
  final DateTime month;
  final ValueChanged<int> onShift;
  const _DutyMonth({required this.month, required this.onShift});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final manager = s.isManagerOf(church);
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - DateTime.monday));
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((first.weekday - 1) + daysInMonth + 6) ~/ 7;
    final today = _today();
    final shown = <String>{
      for (var i = 1; i <= daysInMonth; i++)
        if (s.dutyOn(church, DateTime(month.year, month.month, i)) case final du?) du.userId,
    };
    const wd = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

    void tap(DateTime d) {
      final du = s.dutyOn(church, d);
      if (du == null) {
        if (manager) showDutyForm(context, day: d);
        return;
      }
      if (manager) {
        showDutyForm(context, duty: du);
      } else if (du.userId == s.currentUser?.id && !du.end.isBefore(today) && s.openSwapFor(du.id) == null) {
        showSwapSheet(context, du);
      } else {
        showMessage(context, '${s.priestName(du.userId)} · ${fmtDutyPeriod(du.start, du.end)}');
      }
    }

    return SurfaceCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
      child: Column(children: [
        Row(children: [
          IconButton(onPressed: () => onShift(-1), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: Text(capitalize(_month(first)),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(onPressed: () => onShift(1), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        Row(children: [
          for (final w in wd)
            Expanded(
                child: Text(w, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.textMuted))),
        ]),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(
                child: Builder(builder: (_) {
                  final d = DateTime(start.year, start.month, start.day + r * 7 + c);
                  final du = s.dutyOn(church, d);
                  final color = du == null ? null : p.priest(s.priestIndex(church, du.userId));
                  final other = d.month != month.month;
                  final isToday = d == today;
                  return InkResponse(
                    onTap: () => tap(d),
                    radius: 22,
                    child: Container(
                      height: 40,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      alignment: Alignment.center,
                      decoration: isToday
                          ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Palette.yellow, width: 2.5))
                          : null,
                      child: Text('${d.day}',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: color != null ? FontWeight.w800 : FontWeight.w500,
                              color: color == null
                                  ? (other ? p.textMuted.withValues(alpha: .5) : p.text)
                                  : color.withValues(alpha: other ? .45 : 1))),
                    ),
                  );
                }),
              ),
          ]),
        // Легенда: кой цвят кой свещеник е.
        Builder(builder: (_) {
          if (shown.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(manager ? 'Няма дежурства този месец – натиснете ден, за да добавите.' : 'Няма дежурства този месец.',
                  style: TextStyle(fontSize: 13.5, color: p.textMuted)),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Wrap(spacing: 12, runSpacing: 6, children: [
              for (final u in shown)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: p.priest(s.priestIndex(church, u)), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(s.priestName(u), style: const TextStyle(fontSize: 13.5)),
                ]),
            ]),
          );
        }),
      ]),
    );
  }
}
