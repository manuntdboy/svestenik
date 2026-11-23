import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/call_watcher.dart' show hm;
import '../widgets/common.dart';
import 'metro_cabinet.dart' show editMetroEvent, MetroCalendarScreen;

// Началният екран на митрополията: „Днес“ със седмицата, оперативката,
// „Чака вас“, „Задачи от митрополита“ и календарът за месеца.

final _dayF = DateFormat('EEEE d MMMM', 'bg');
final _dmF = DateFormat('d.MM', 'bg');
final _monthF = DateFormat('LLLL y', 'bg');
const _wd = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
DateTime get _today => _d(DateTime.now());

/// Кратко име на човек от администрацията: длъжността (или титлата), иначе името.
String metroShortName(AppState s, String userId) {
  final x = s.metroPeople.where((e) => '${e['user_id']}' == userId).firstOrNull;
  if (x == null) return '…';
  final r = StaffRole.fromCode(x['role']);
  final sameRole = s.metroPeople.where((e) => e['role'] == x['role'] && e['title'] == x['title']).length;
  if (r != null && r != StaffRole.employee && sameRole == 1) return r.label;
  final t = '${x['title'] ?? ''}'.trim();
  if (t.isNotEmpty && sameRole == 1) return t;
  return withRank(ClergyRank.fromCode(x['rank']), '${x['name'] ?? ''}');
}

String _deadline(MetroNote n) {
  final d = n.deadline;
  if (d == null) return '';
  return n.deadlineHasTime ? 'до ${_dmF.format(d)} ${hm(d)}' : 'до ${_dmF.format(d)}';
}

List<MetroEvent> metroEventsOn(AppState s, DateTime day) => s.metroEvents.where((e) {
      final a = _d(e.startsAt), b = _d(e.endsAt ?? e.startsAt);
      return !day.isBefore(a) && !day.isAfter(b);
    }).toList();

/// Рамка на карта с надпис горе (като в макета).
class DeskCard extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget child;
  final Widget? trailing;
  const DeskCard({super.key, required this.title, this.action, this.onAction, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: p.primary)),
          ),
          if (trailing != null) trailing!,
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text('$action ›', style: TextStyle(fontSize: 14, color: p.textMuted)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        child,
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool filled;
  final Color? color;
  const _Tag(this.text, {this.filled = false, this.color});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: .18) : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: .6)),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600)),
    );
  }
}

// ======================================================= Днес + седмицата

class MetroTodayCard extends StatefulWidget {
  final VoidCallback onOpenCalendar;
  final String? title; // напр. „Календар на митрополита“ (за секретаря)
  const MetroTodayCard({super.key, required this.onOpenCalendar, this.title});

  @override
  State<MetroTodayCard> createState() => _MetroTodayCardState();
}

class _MetroTodayCardState extends State<MetroTodayCard> {
  DateTime day = _today;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final monday = _today.subtract(Duration(days: _today.weekday - 1));
    final events = metroEventsOn(s, day);
    final isToday = day == _today;
    return DeskCard(
      title: widget.title != null
          ? '${widget.title} · ${isToday ? 'днес' : _dayF.format(day)}'
          : '${isToday ? 'Днес · ' : ''}${_dayF.format(day)}',
      action: 'Календар',
      onAction: widget.onOpenCalendar,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(child: () {
              final d = DateTime(monday.year, monday.month, monday.day + i);
              final sel = d == day;
              final has = metroEventsOn(s, d).isNotEmpty;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => day = d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? p.primary.withValues(alpha: .16) : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    Text(_wd[i], style: TextStyle(fontSize: 13, color: p.textMuted)),
                    Text('${d.day}',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: d == _today ? p.primary : (d.isBefore(_today) ? p.textMuted : p.text))),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: has ? p.primary : Colors.transparent, shape: BoxShape.circle),
                    ),
                  ]),
                ),
              );
            }()),
        ]),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(isToday ? 'Днес няма записи.' : 'Няма записи.', style: TextStyle(color: p.textMuted)),
          ),
        for (final e in events) MetroEventRow(e),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Запис'),
            onPressed: () => editMetroEvent(context, day: day),
          ),
        ),
      ]),
    );
  }
}

/// Ред „час · какво · къде“.
class MetroEventRow extends StatelessWidget {
  final MetroEvent e;
  const MetroEventRow(this.e, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => editMetroEvent(context, e: e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 66,
            child: Text(e.allDay ? 'цял ден' : hm(e.startsAt),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.primary)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
              if ((e.place ?? '').isNotEmpty || e.private)
                Text(
                    [
                      if ((e.place ?? '').isNotEmpty) e.place!,
                      if (e.private) '🔒 само за мен',
                    ].join(' · '),
                    style: TextStyle(fontSize: 14, color: p.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ============================================================ Оперативка

class OperativkaCard extends StatelessWidget {
  const OperativkaCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final notes = s.notesForDay(_today);
    return DeskCard(
      title: 'Оперативка · днес',
      action: 'Стари',
      onAction: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => Theme(data: Theme.of(context), child: const OperativkaScreen()))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Празно. Запишете какво трябва да се свърши днес.', style: TextStyle(color: p.textMuted)),
          ),
        for (final n in notes) NoteRow(n),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Бележка'),
            onPressed: () => editMetroNote(context, day: _today),
          ),
        ),
      ]),
    );
  }
}

/// Ред от оперативката: отметка, текст, кой е на задачата и срокът.
class NoteRow extends StatelessWidget {
  final MetroNote n;
  final bool showDay;
  const NoteRow(this.n, {super.key, this.showDay = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final carried = n.day.isBefore(_today) && !showDay;
    final tags = <Widget>[
      if (n.assignees.length > 1) _Tag('${n.doneCount} от ${n.assignees.length} ✓', filled: n.complete),
      for (final a in n.assignees)
        _Tag(a.done ? '✓ ${metroShortName(s, a.userId)}' : metroShortName(s, a.userId), filled: a.done),
      if (n.deadline != null && !n.complete)
        _Tag(_deadline(n),
            color: n.deadline!.isBefore(DateTime.now()) ? const Color(0xFFE08A84) : null),
      if (carried) _Tag('от ${_dmF.format(n.day)}', color: p.textMuted),
      if (showDay) _Tag(_dmF.format(n.day), color: p.textMuted),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showNoteDetails(context, n),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: n.complete,
            onChanged: (v) async {
              try {
                await s.metroNoteDone(n.id, v == true);
              } on AppError catch (e) {
                if (context.mounted) showMessage(context, e.message);
              }
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.body,
                    style: TextStyle(
                      fontSize: 16.5,
                      height: 1.3,
                      color: n.complete ? p.textMuted : p.text,
                      decoration: n.complete ? TextDecoration.lineThrough : null,
                    )),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(spacing: 6, runSpacing: 4, children: tags),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Подробно за бележка: кой какво е направил, „Върни“, промяна, изтриване.
Future<void> showNoteDetails(BuildContext context, MetroNote note) async {
  final s = AppScope.read(context);
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final p = Palette.of(ctx);
      final n = AppScope.of(ctx).metroNotes.where((x) => x.id == note.id).firstOrNull ?? note;
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text(n.body, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            [
              'Оперативка ${_dmF.format(n.day)}',
              if (n.deadline != null) 'срок ${_deadline(n).substring(3)}',
              if (n.complete) 'готово',
            ].join(' · '),
            style: TextStyle(color: p.textMuted)),
        const SizedBox(height: 14),
        if (n.assignees.isNotEmpty) ...[
          Text('Възложено на', style: TextStyle(fontWeight: FontWeight.w800, color: p.primary)),
          for (final a in n.assignees)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(a.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: a.done ? p.primary : p.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(metroShortName(s, a.userId), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (a.done)
                      Text('Изпълнено ${_dmF.format(a.doneAt!)} ${hm(a.doneAt!)}${(a.doneNote ?? '').isEmpty ? '' : ' · ${a.doneNote}'}',
                          style: TextStyle(color: p.textMuted)),
                    if (!a.done && a.returnedAt != null)
                      Text('Върната ${_dmF.format(a.returnedAt!)}${(a.returnNote ?? '').isEmpty ? '' : ' · ${a.returnNote}'}',
                          style: const TextStyle(color: Color(0xFFE08A84))),
                    if (!a.done && a.returnedAt == null) Text('Още не е изпълнено', style: TextStyle(color: p.textMuted)),
                  ]),
                ),
                if (a.done)
                  TextButton(
                    onPressed: () async {
                      final reason = await _askText(ctx, 'Върни задачата', 'Защо? (по желание)', 'Върни');
                      if (reason == null) return;
                      try {
                        await s.metroTaskReturn(n.id, a.userId, reason: reason);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on AppError catch (e) {
                        if (ctx.mounted) showMessage(ctx, e.message);
                      }
                    },
                    child: const Text('Върни'),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
        ],
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Промени'),
              onPressed: () {
                Navigator.pop(ctx);
                editMetroNote(context, note: n);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Изтрий'),
              onPressed: () async {
                if (!await confirm(ctx, 'Изтриване', 'Да изтрия ли бележката?', 'Изтрий')) return;
                try {
                  await s.metroNoteDelete(n.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on AppError catch (e) {
                  if (ctx.mounted) showMessage(ctx, e.message);
                }
              },
            ),
          ),
        ]),
      ]);
    },
  );
}

Future<String?> _askText(BuildContext context, String title, String hint, String action) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 300,
        maxLines: 3,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отказ')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(action)),
      ],
    ),
  );
}

/// Нова бележка или промяна: текст, „Възложи на…“, срок.
Future<void> editMetroNote(BuildContext context, {MetroNote? note, DateTime? day}) async {
  final s = AppScope.read(context);
  if (s.metroPeople.isEmpty) await s.loadMetroPeople();
  if (!context.mounted) return;
  final me = s.currentUser?.id;
  final people = s.metroPeople.where((x) => '${x['user_id']}' != me).toList();
  final body = TextEditingController(text: note?.body ?? '');
  final users = <String>{...?note?.assignees.map((a) => a.userId)};
  DateTime? date = note?.deadline == null ? null : _d(note!.deadline!);
  TimeOfDay? time = note?.deadline != null && note!.deadlineHasTime ? TimeOfDay.fromDateTime(note.deadline!) : null;
  var busy = false;
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final p = Palette.of(ctx);
      Future<void> save() async {
        if (body.text.trim().isEmpty) {
          showMessage(ctx, 'Напишете бележката.');
          return;
        }
        set(() => busy = true);
        try {
          final dl = date == null
              ? null
              : time == null
                  ? date
                  : DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute);
          await s.metroNoteSave(
            id: note?.id,
            day: note?.day ?? day ?? _today,
            body: body.text.trim(),
            deadline: dl,
            hasTime: time != null && date != null,
            users: users.toList(),
          );
          if (ctx.mounted) Navigator.pop(ctx);
        } on AppError catch (e) {
          set(() => busy = false);
          if (ctx.mounted) showMessage(ctx, e.message);
        }
      }

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(note == null ? 'Бележка' : 'Промяна', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: body,
            autofocus: note == null,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                hintText: 'Какво трябва да се свърши…', helperText: 'Може и с диктовка – микрофонът на клавиатурата.'),
          ),
          const SizedBox(height: 12),
          Text('Възложи на (по желание)', style: TextStyle(fontWeight: FontWeight.w800, color: p.primary)),
          const SizedBox(height: 6),
          if (people.isEmpty) Text('Няма хора в администрацията.', style: TextStyle(color: p.textMuted)),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final x in people)
              FilterChip(
                label: Text(metroShortName(s, '${x['user_id']}')),
                selected: users.contains('${x['user_id']}'),
                onSelected: (v) => set(() => v ? users.add('${x['user_id']}') : users.remove('${x['user_id']}')),
              ),
          ]),
          const SizedBox(height: 14),
          Text('Срок (по желание)', style: TextStyle(fontWeight: FontWeight.w800, color: p.primary)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(date == null ? 'Без срок' : DateFormat('d MMMM', 'bg').format(date!)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: date ?? _today,
                    firstDate: _today.subtract(const Duration(days: 30)),
                    lastDate: _today.add(const Duration(days: 730)));
                if (d != null) set(() => date = d);
              },
            ),
            if (date != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: Text(time == null ? 'Час (по желание)' : time!.format(ctx)),
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: time ?? const TimeOfDay(hour: 12, minute: 0));
                  if (t != null) set(() => time = t);
                },
              ),
            if (date != null)
              IconButton(
                tooltip: 'Без срок',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => set(() {
                  date = null;
                  time = null;
                }),
              ),
          ]),
          if (date != null && users.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  time == null
                      ? 'Изпълнителят получава напомняне в 9:00 в деня на срока.'
                      : 'Изпълнителят получава напомняне час преди срока.',
                  style: TextStyle(fontSize: 13.5, color: p.textMuted)),
            ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: busy ? null : save,
            child: Text(users.isEmpty ? 'Запиши' : 'Запиши и възложи'),
          ),
        ]),
      );
    }),
  );
}

/// Всички оперативки: по дни (‹ ›) и търсене в старите.
class OperativkaScreen extends StatefulWidget {
  const OperativkaScreen({super.key});

  @override
  State<OperativkaScreen> createState() => _OperativkaScreenState();
}

class _OperativkaScreenState extends State<OperativkaScreen> {
  DateTime day = _today;
  final q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final query = q.text.trim().toLowerCase();
    final found = query.length < 2
        ? const <MetroNote>[]
        : (s.metroNotes.where((n) => n.body.toLowerCase().contains(query)).toList()
          ..sort((a, b) => b.day.compareTo(a.day)));
    final notes = s.notesForDay(day);
    return Scaffold(
      appBar: AppBar(title: const Text('Оперативка')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Бележка'),
        onPressed: () => editMetroNote(context, day: day),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            TextField(
              controller: q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Търсене в старите бележки',
                suffixIcon: q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(q.clear),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (query.length >= 2) ...[
              Text(found.isEmpty ? 'Нищо не е намерено.' : 'Намерени: ${found.length}',
                  style: TextStyle(color: p.textMuted)),
              for (final n in found) NoteRow(n, showDay: true),
            ] else ...[
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 30),
                  onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: day,
                          firstDate: DateTime(2026),
                          lastDate: _today.add(const Duration(days: 365)));
                      if (d != null) setState(() => day = d);
                    },
                    child: Text(capitalize(_dayF.format(day)) + (day == _today ? ' · днес' : ''),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 30),
                  onPressed: () => setState(() => day = day.add(const Duration(days: 1))),
                ),
              ]),
              if (day != _today)
                Center(child: TextButton(onPressed: () => setState(() => day = _today), child: const Text('Към днес'))),
              const SizedBox(height: 6),
              if (notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text('Няма бележки за този ден.', textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
                ),
              for (final n in notes) NoteRow(n),
            ],
          ]),
        ),
      ),
    );
  }
}

// ============================================================= Чака вас

class WaitingCard extends StatelessWidget {
  final ValueChanged<String> onOpen;
  const WaitingCard({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final doneRecently = s.metroNotes
        .where((n) => n.assignees.any((a) => a.done && a.doneAt!.isAfter(since)))
        .toList();
    final unread = s.metroUnreadAll;
    final items = <(String, String, VoidCallback)>[
      if (unread > 0) ('Чат – $unread непрочетени', 'виж', () => onOpen('chat')),
      for (final n in doneRecently)
        (
          'Изпълнено: ${n.body}',
          n.assignees.length > 1 ? '${n.doneCount} от ${n.assignees.length}' : 'виж',
          () => showNoteDetails(context, n)
        ),
    ];
    return DeskCard(
      title: 'Чака вас',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Нищо не чака.', style: TextStyle(color: p.textMuted)),
          ),
        for (final it in items)
          InkWell(
            onTap: it.$3,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Expanded(
                    child: Text(it.$1, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5))),
                const SizedBox(width: 8),
                _Tag(it.$2, filled: true),
              ]),
            ),
          ),
      ]),
    );
  }
}

// =================================================== Задачи от митрополита

class MyTasksCard extends StatelessWidget {
  /// Карта и когато няма задачи (секретарят); иначе се скрива.
  final bool alwaysShow;
  const MyTasksCard({super.key, this.alwaysShow = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final me = s.currentUser?.id;
    final week = DateTime.now().subtract(const Duration(days: 7));
    final tasks = s.myTasks.where((n) {
      final a = n.assigneeOf(me)!;
      return !a.done || a.doneAt!.isAfter(week);
    }).toList();
    if (tasks.isEmpty && !alwaysShow) return const SizedBox.shrink();
    return DeskCard(
      title: 'Задачи от митрополита',
      trailing: Text('${s.myOpenTasks}', style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w700)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Нямате задачи.', style: TextStyle(color: p.textMuted)),
          ),
        for (final n in tasks) _TaskRow(n),
      ]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final MetroNote n;
  const _TaskRow(this.n);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final a = n.assigneeOf(s.currentUser?.id)!;
    final overdue = !a.done && n.deadline != null && n.deadline!.isBefore(DateTime.now());
    Future<void> toggle() async {
      try {
        if (!a.done) {
          final c = await _askText(context, 'Изпълнено', 'Кратка бележка за митрополита (по желание)', 'Изпълнено ✓');
          if (c == null) return;
          await s.metroTaskDone(n.id, true, comment: c);
          if (context.mounted) showMessage(context, 'Митрополитът е известен.');
        } else {
          if (!await confirm(context, 'Не е готово', 'Да махна ли отметката „Изпълнено“?', 'Махни')) return;
          await s.metroTaskDone(n.id, false);
        }
      } on AppError catch (e) {
        if (context.mounted) showMessage(context, e.message);
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: toggle,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(value: a.done, onChanged: (_) => toggle()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.body,
                  style: TextStyle(
                    fontSize: 16.5,
                    height: 1.3,
                    color: a.done ? p.textMuted : p.text,
                    decoration: a.done ? TextDecoration.lineThrough : null,
                  )),
              Text(
                  [
                    if (n.deadline != null && !a.done) _deadline(n),
                    'от оперативката ${_dmF.format(n.day)}',
                    if (a.done && (a.doneNote ?? '').isNotEmpty) a.doneNote!,
                  ].join(' · '),
                  style: TextStyle(fontSize: 14, color: overdue ? const Color(0xFFE08A84) : p.textMuted)),
              if (!a.done && a.returnedAt != null)
                Text('Върната от митрополита${(a.returnNote ?? '').isEmpty ? '' : ': ${a.returnNote}'}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFFE08A84), fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ======================================================= Календар – месец

/// Календарът на митрополита: месец (като в храмовете) или списък.
class MetroMonthCalendar extends StatefulWidget {
  final bool embedded;
  const MetroMonthCalendar({super.key, this.embedded = false});

  @override
  State<MetroMonthCalendar> createState() => _MetroMonthCalendarState();
}

class _MetroMonthCalendarState extends State<MetroMonthCalendar> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime day = _today;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final first = month;
    final start = first.subtract(Duration(days: first.weekday - 1));
    final events = metroEventsOn(s, day);
    Widget cell(DateTime d) {
      final inMonth = d.month == month.month;
      final sel = d == day;
      final isToday = d == _today;
      final n = metroEventsOn(s, d).length;
      return InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => setState(() {
          day = d;
          if (!inMonth) month = DateTime(d.year, d.month);
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? p.primary : null,
                shape: BoxShape.circle,
                border: isToday && !sel ? Border.all(color: p.primary, width: 2) : null,
              ),
              child: Text('${d.day}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: sel ? p.onPrimary : (inMonth ? p.text : p.textMuted.withValues(alpha: .55)),
                  )),
            ),
            const SizedBox(height: 3),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < n.clamp(0, 3); i++)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                ),
              if (n == 0) const SizedBox(height: 5),
            ]),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.isMetropolitan ? 'Календар' : 'Календар на митрополита'),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
            tooltip: 'Списък',
            icon: const Icon(Icons.view_agenda_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => Theme(data: Theme.of(context), child: const MetroCalendarScreen()))),
          ),
          if (month != DateTime(_today.year, _today.month) || day != _today)
            TextButton(
              onPressed: () => setState(() {
                day = _today;
                month = DateTime(_today.year, _today.month);
              }),
              child: const Text('Днес'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Нов запис'),
        onPressed: () => editMetroEvent(context, day: day),
      ),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: [
          if (s.isSecretary && !s.isMetropolitan)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: Text('Записите тук вижда и митрополитът.', style: TextStyle(color: p.textMuted)),
            ),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 32),
              onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
            ),
            Expanded(
              child: Text(capitalize(_monthF.format(month)),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 32),
              onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
            ),
          ]),
          Row(children: [
            for (final w in _wd)
              Expanded(child: Text(w, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted))),
          ]),
          const SizedBox(height: 4),
          for (var r = 0; r < 6; r++)
            if (DateTime(start.year, start.month, start.day + r * 7).isBefore(DateTime(month.year, month.month + 1)))
              Row(children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: cell(DateTime(start.year, start.month, start.day + r * 7 + c))),
              ]),
          const SizedBox(height: 10),
          DeskCard(
            title: _dayF.format(day),
            trailing: Text(events.isEmpty ? '' : (events.length == 1 ? '1 запис' : '${events.length} записа'),
                style: TextStyle(color: p.textMuted)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (events.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('Няма записи. Добавете с „Нов запис“.', style: TextStyle(color: p.textMuted)),
                ),
              for (final e in events) MetroEventRow(e),
            ]),
          ),
        ]),
      ),
    );
  }
}
