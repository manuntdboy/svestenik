import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/call_watcher.dart' show hm;
import '../widgets/church_address.dart' show NavigateButtons;
import '../widgets/common.dart';

final _dayF = DateFormat('EEEE, d MMMM', 'bg');
final _dmF = DateFormat('d MMMM', 'bg');

String _personName(Map<String, dynamic>? x) =>
    x == null ? '' : withRank(ClergyRank.fromCode(x['rank']), '${x['name'] ?? ''}');

String _staffRole(Map<String, dynamic> x) {
  final r = StaffRole.fromCode(x['role']);
  if (r == StaffRole.employee) return '${x['title'] ?? r!.label}';
  return r?.label ?? '';
}

// =================================================================== Повикай

/// „Повикай“ – владиката избира един или няколко души от администрацията.
Future<void> showCallSheet(BuildContext context) async {
  final s = AppScope.read(context);
  await s.loadMetroPeople();
  if (!context.mounted) return;
  final me = s.currentUser?.id;
  final people = s.metroPeople.where((x) => x['user_id'] != me).toList();
  final picked = <String>{};
  final note = TextEditingController();
  var busy = false;
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final p = Palette.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
            const Text('Повикай в кабинета', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Повиканият получава известие със звънец и отговаря „Идвам“ или „Не мога“.',
                style: TextStyle(color: p.textMuted)),
            const SizedBox(height: 12),
            if (people.isEmpty)
              Text('Още няма служители в администрацията. Добавете ги от „Епархия“.',
                  style: TextStyle(color: p.textMuted, fontSize: 16)),
            for (final x in people)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: picked.contains(x['user_id']),
                onChanged: (v) => set(() => v == true ? picked.add('${x['user_id']}') : picked.remove(x['user_id'])),
                title: Text(_personName(x), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                subtitle: Text(_staffRole(x)),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Бележка (по желание)', hintText: 'напр. „С папката за Шипка“'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.notifications_active_rounded),
              label: Text(picked.length > 1 ? 'Повикай (${picked.length})' : 'Повикай'),
              onPressed: picked.isEmpty || busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        final n = await s.metroCall(picked.toList(), note.text.trim().isEmpty ? null : note.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) showMessage(context, n == 1 ? 'Повикан.' : 'Повикани: $n.');
                      } on AppError catch (e) {
                        set(() => busy = false);
                        if (ctx.mounted) showMessage(ctx, e.message);
                      }
                    },
            ),
          ]),
        ),
      );
    }),
  );
}

/// Последните повиквания на владиката и отговорите.
class CallsMadeCard extends StatelessWidget {
  const CallsMadeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final calls = s.myCallsMade.take(6).toList();
    if (calls.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ПОВИКАНИ ДНЕС',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: p.primary)),
        const SizedBox(height: 6),
        for (final c in calls)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Text(hm(c.createdAt), style: TextStyle(color: p.textMuted)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_personName(s.metroPeople.where((x) => x['user_id'] == c.calleeId).firstOrNull),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              _AnswerTag(c),
            ]),
          ),
      ]),
    );
  }
}

class _AnswerTag extends StatelessWidget {
  final MetroCall c;
  const _AnswerTag(this.c);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (text, color) = switch (c.answer) {
      'coming' => ('идва', const Color(0xFF4E9A6A)),
      'cannot' => ('не може', const Color(0xFFB0473F)),
      _ => ('чака отговор', p.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

/// Голям бутон „Повикай“ (началният екран и профилът на митрополита).
class CallButton extends StatelessWidget {
  const CallButton({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          icon: const Icon(Icons.notifications_active_rounded, size: 26),
          label: const Text('Повикай'),
          onPressed: () => showCallSheet(context),
        ),
      );
}

// ============================================================ Календар на митрополита

String _when(MetroEvent e) {
  if (e.allDay) return 'цял ден';
  final end = e.endsAt;
  return end == null ? hm(e.startsAt) : '${hm(e.startsAt)} – ${hm(end)}';
}

/// Предстоящите записи (за началния екран).
class UpcomingMetroEvents extends StatelessWidget {
  final int max;
  final VoidCallback? onOpen;
  const UpcomingMetroEvents({super.key, this.max = 5, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final list = s.metroEvents
        .where((e) => !DateUtils.dateOnly(e.endsAt ?? e.startsAt).isBefore(today))
        .take(max)
        .toList();
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), side: BorderSide(color: p.primary.withValues(alpha: .35))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ДНЕС И ПРЕДСТОЯЩИ',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: p.primary)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Text('Няма записи в календара.', style: TextStyle(fontSize: 15, color: p.textMuted)),
            for (final e in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                        DateUtils.isSameDay(e.startsAt, today) ? 'днес\n${_when(e)}' : '${_dmF.format(e.startsAt)}\n${_when(e)}',
                        style: TextStyle(color: p.textMuted, fontSize: 13.5)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if ((e.place ?? '').isNotEmpty) Text(e.place!, style: TextStyle(color: p.textMuted)),
                    ]),
                  ),
                  if (e.private) Icon(Icons.lock_outline_rounded, size: 18, color: p.textMuted),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class MetroCalendarScreen extends StatelessWidget {
  final bool embedded;
  const MetroCalendarScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final all = s.metroEvents;
    final upcoming = all.where((e) => !DateUtils.dateOnly(e.endsAt ?? e.startsAt).isBefore(today)).toList();
    final past = all.where((e) => DateUtils.dateOnly(e.endsAt ?? e.startsAt).isBefore(today)).toList().reversed.toList();
    final children = <Widget>[];
    DateTime? day;
    for (final e in upcoming) {
      final d = DateUtils.dateOnly(e.startsAt);
      if (day == null || d != day) {
        day = d;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(
              (DateUtils.isSameDay(d, today) ? 'Днес · ' : '') + _dayF.format(d),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.primary)),
        ));
      }
      children.add(_EventTile(e));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.isMetropolitan ? 'Календар' : 'Календар на митрополита'),
        automaticallyImplyLeading: !embedded,
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Нов запис'),
        onPressed: () => editMetroEvent(context),
      ),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          if (s.isSecretary && !s.isMetropolitan)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Записите тук вижда и митрополитът.',
                  style: TextStyle(color: p.textMuted)),
            ),
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('Няма предстоящи записи. Добавете среща, посещение или служба с „Нов запис“.',
                  style: TextStyle(fontSize: 16, color: p.textMuted)),
            ),
          ...children,
          if (past.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ExpansionTile(
                shape: const Border(),
                tilePadding: EdgeInsets.zero,
                title: Text('Минали (${past.length})', style: TextStyle(color: p.textMuted)),
                children: [for (final e in past) _EventTile(e, showDate: true)],
              ),
            ),
        ]),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final MetroEvent e;
  final bool showDate;
  const _EventTile(this.e, {this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => editMetroEvent(context, e: e),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 78,
                child: Text(showDate ? '${_dmF.format(e.startsAt)}\n${_when(e)}' : _when(e),
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.primary)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  if ((e.place ?? '').isNotEmpty) Text(e.place!, style: TextStyle(color: p.textMuted)),
                  if ((e.note ?? '').isNotEmpty)
                    Text(e.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted)),
                ]),
              ),
              if (e.private)
                Tooltip(message: 'Само за мен', child: Icon(Icons.lock_outline_rounded, size: 20, color: p.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Нов запис или промяна в календара на митрополита.
Future<void> editMetroEvent(BuildContext context, {MetroEvent? e}) async {
  final s = AppScope.read(context);
  final title = TextEditingController(text: e?.title ?? '');
  final place = TextEditingController(text: e?.place ?? '');
  final note = TextEditingController(text: e?.note ?? '');
  final now = DateTime.now();
  var date = DateUtils.dateOnly(e?.startsAt ?? now);
  var start = e == null ? const TimeOfDay(hour: 10, minute: 0) : TimeOfDay.fromDateTime(e.startsAt);
  TimeOfDay? end = e?.endsAt == null ? null : TimeOfDay.fromDateTime(e!.endsAt!);
  var allDay = e?.allDay ?? false;
  var private = e?.private ?? false;
  var busy = false;
  String fmtT(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final p = Palette.of(ctx);
      Future<void> save() async {
        if (title.text.trim().isEmpty) {
          showMessage(ctx, 'Напишете какво е – напр. „Среща с кмета“.');
          return;
        }
        final st = allDay ? date : DateTime(date.year, date.month, date.day, start.hour, start.minute);
        final en = allDay || end == null ? null : DateTime(date.year, date.month, date.day, end!.hour, end!.minute);
        if (en != null && en.isBefore(st)) {
          showMessage(ctx, 'Краят е преди началото.');
          return;
        }
        set(() => busy = true);
        try {
          await s.metroEventSave(
            id: e?.id,
            startsAt: st,
            endsAt: en,
            allDay: allDay,
            title: title.text.trim(),
            place: place.text.trim(),
            note: note.text.trim(),
            private: private,
          );
          if (ctx.mounted) Navigator.pop(ctx);
        } on AppError catch (err) {
          set(() => busy = false);
          if (ctx.mounted) showMessage(ctx, err.message);
        }
      }

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(e == null ? 'Нов запис' : 'Запис', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            maxLength: 150,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Какво', hintText: 'Среща, посещение, служба…'),
          ),
          TextField(
            controller: place,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Къде (по желание)'),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(_dayF.format(date)),
            onPressed: () async {
              final d = await showDatePicker(
                  context: ctx,
                  initialDate: date,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 3));
              if (d != null) set(() => date = d);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Цял ден'),
            value: allDay,
            onChanged: (v) => set(() => allDay = v),
          ),
          if (!allDay)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: ctx, initialTime: start);
                    if (t != null) set(() => start = t);
                  },
                  child: Text('От ${fmtT(start)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: ctx, initialTime: end ?? TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute));
                    if (t != null) set(() => end = t);
                  },
                  child: Text(end == null ? 'До … (по желание)' : 'До ${fmtT(end!)}'),
                ),
              ),
            ]),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Бележка (по желание)'),
          ),
          if (s.isMetropolitan)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Само за мен'),
              subtitle: Text('Секретарят няма да вижда този запис.', style: TextStyle(color: p.textMuted)),
              value: private,
              onChanged: (v) => set(() => private = v),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: busy ? null : save, child: const Text('Запиши')),
          if (e != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!await confirm(ctx, 'Изтриване', 'Да изтрия ли „${e.title}“?', 'Изтрий')) return;
                      try {
                        await s.metroEventDelete(e.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on AppError catch (err) {
                        if (ctx.mounted) showMessage(ctx, err.message);
                      }
                    },
              child: const Text('Изтрий'),
            ),
          ],
        ]),
      );
    }),
  );
}

// ============================================================ Храм от епархията

/// Храм, гледан от митрополията: адрес, Булстат и навигация (без дежурства).
class DioceseChurchScreen extends StatefulWidget {
  final String churchId;
  final String title;
  const DioceseChurchScreen({super.key, required this.churchId, required this.title});

  @override
  State<DioceseChurchScreen> createState() => _DioceseChurchScreenState();
}

class _DioceseChurchScreenState extends State<DioceseChurchScreen> {
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).dioceseChurch(widget.churchId).then((d) {
      if (mounted) setState(() => data = d);
    }).catchError((Object e) {
      if (mounted) setState(() => error = e is AppError ? e.message : '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final d = data;
    Widget body;
    if (error != null) {
      body = Center(child: Text(error!, style: TextStyle(color: p.textMuted)));
    } else if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final addr = '${d['address'] ?? ''}'.trim();
      final bul = '${d['bulstat'] ?? ''}'.trim();
      final query = [
        addr,
        '${d['settlement'] ?? ''}',
        if ('${d['municipality'] ?? ''}'.isNotEmpty) 'общ. ${d['municipality']}',
        'България',
      ].where((x) => x.trim().isNotEmpty).join(', ');
      body = ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 32), children: [
        Text('${d['name']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        Text('${d['settlement']}', style: TextStyle(fontSize: 16, color: p.textMuted)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.place_rounded, size: 20, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(
              child: Text(addr.isEmpty ? 'Адресът не е въведен.' : '$addr, ${d['settlement']}',
                  style: TextStyle(fontSize: 15, color: addr.isEmpty ? p.textMuted : null))),
        ]),
        if (bul.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.badge_outlined, size: 20, color: p.textMuted),
            const SizedBox(width: 8),
            SelectableText('Булстат $bul', style: const TextStyle(fontSize: 15)),
          ]),
        ],
        const SizedBox(height: 10),
        NavigateButtons(query),
        const SizedBox(height: 22),
      ]);
    }
    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
  }
}

// ============================================================ Заключени функции

class LockedFeature {
  final String title;
  final IconData icon;
  final String text;
  const LockedFeature(this.title, this.icon, this.text);
}

const lockPrograms = LockedFeature('Програми', Icons.airport_shuttle_outlined,
    'Програми за архиерейските служения. Секретарят съставя програмата: групи, коли, шофьори, служещи, гости на обяда. '
        'Митрополитът я утвърждава с бутон, всеки участник получава известие със своята част, а документът излиза готов за печат. '
        'Старите програми се пазят и по тях се прави нова.');
const lockCirculars = LockedFeature('Окръжни', Icons.campaign_outlined,
    'Окръжни до всички храмове, до избрани околии или храмове – с номер, дата и прикачени файлове. '
        'Всеки отбелязва „Прочетох“, а секретарят напомня само на непрочелите.');
const lockLeaves = LockedFeature('Отпуски', Icons.beach_access_outlined,
    'Официалните отпуски на свещениците – председателят одобрява, митрополията утвърждава. '
        'Молбата излиза по образец, готова за печат и подпис.');
const lockDocs = LockedFeature('Документи за печат', Icons.print_outlined,
    'Всичко, което се изпраща, и като лист A4 в бланката на епархията. Подписът и печатът остават на ръка.');
const lockGoogle = LockedFeature('Google Calendar', Icons.sync_rounded,
    'Календарът на митрополита се копира сам и в Google Calendar.');
const lockAccounting = LockedFeature('Счетоводство', Icons.account_balance_wallet_outlined,
    'Счетоводството на митрополията – касиер, счетоводител, ревизори.');
const lockCars = LockedFeature('Автопарк', Icons.directions_car_outlined,
    'Служебните автомобили – шофьори, застраховки, винетки, прегледи, с напомняне преди срока.');

const lockedForMetropolitan = [lockPrograms, lockCirculars, lockLeaves, lockDocs, lockGoogle, lockAccounting, lockCars];
const lockedForSecretary = [lockPrograms, lockCirculars, lockLeaves, lockDocs, lockCars];

void showLocked(BuildContext context, LockedFeature f) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(f.icon, size: 36),
        title: Text(f.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const YellowTag('Предстои'),
          const SizedBox(height: 12),
          Text(f.text, style: const TextStyle(fontSize: 16)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Разбрах'))],
      ),
    );

/// Решетка със заключените функции.
class LockedGrid extends StatelessWidget {
  final List<LockedFeature> items;
  const LockedGrid(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text('ПРЕДСТОИ',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: p.textMuted)),
      ),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final f in items)
          Material(
            color: p.surface.withValues(alpha: .6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showLocked(context, f),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(f.icon, color: p.textMuted, size: 22),
                  const SizedBox(width: 8),
                  Text(f.title, style: TextStyle(fontSize: 15.5, color: p.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Icon(Icons.lock_outline_rounded, size: 16, color: p.textMuted),
                ]),
              ),
            ),
          ),
      ]),
    ]);
  }
}

/// Цял екран за заключена функция (когато е в менюто).
class LockedScreen extends StatelessWidget {
  final LockedFeature f;
  const LockedScreen(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(f.title), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Icon(Icons.lock_outline_rounded, color: p.textMuted),
          const SizedBox(width: 8),
          const YellowTag('Предстои'),
        ]),
        const SizedBox(height: 12),
        Text(f.text, style: TextStyle(fontSize: 17, color: p.textMuted)),
      ]),
    );
  }
}
