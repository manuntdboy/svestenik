import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import 'common.dart';
import '../screens/cash.dart' show CashReviewCard, fmtEur;
import '../screens/cash_more.dart' show CloseMonthCard;
import '../screens/stock.dart' show LowStockCard, StockReviewCard;
import '../screens/duties.dart' show fmtDutyPeriod;

final _fmtDm = DateFormat('d MMMM', 'bg');
final _fmtSeen = DateFormat('d MMMM, HH:mm', 'bg');

/// „Видяно днес в 18:12“ / „Видяно 12 ноември, 18:12“ / „Още не е видяно“.
String seenLabel(ChurchEvent e) {
  final t = e.seenAt;
  if (t == null) return 'още не е видяно';
  return sameDay(t, DateTime.now()) ? 'видяно днес в ${fmtTime(t)}' : 'видяно ${_fmtSeen.format(t)}';
}

/// „днес в 18:12“ или датата и часа.
String fmtWhenShort(DateTime t) =>
    sameDay(t, DateTime.now()) ? 'днес в ${fmtTime(t)}' : _fmtSeen.format(t);

/// „12 ноември“ или „12 – 14 ноември“ / „30 ноември – 2 декември“.
String fmtLeavePeriod(LeaveRequest l) {
  if (l.start == l.end) return _fmtDm.format(l.start);
  if (l.start.month == l.end.month) return '${l.start.day} – ${_fmtDm.format(l.end)}';
  return '${_fmtDm.format(l.start)} – ${_fmtDm.format(l.end)}';
}

/// Диалог с поле за коментар (по желание). Връща текста или null при „Отказ“.
Future<String?> askComment(BuildContext context,
    {required String title,
    required String body,
    required String hint,
    required String action,
    String label = 'Коментар'}) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(body, style: const TextStyle(fontSize: 16.5)),
        const SizedBox(height: 12),
        TextField(
          controller: c,
          maxLength: 300,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            border: const OutlineInputBorder(),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  final text = c.text;
  c.dispose();
  return ok == true ? text : null;
}

/// Обща рамка на картите за молби (жълт кант като „Чака одобрение“).
class _RequestFrame extends StatelessWidget {
  final String tag;
  final IconData icon;
  final List<Widget> children;
  const _RequestFrame({required this.tag, required this.icon, required this.children});

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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [YellowTag(tag), const Spacer(), Icon(icon, color: p.textMuted)]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

Widget _eventTitle(BuildContext context, ChurchEvent e) {
  final p = Palette.of(context);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      KindChip(e.kind),
      const SizedBox(width: 8),
      Expanded(
        child: Text('${fmtDayLong(e.startsAt)}, ${fmtRange(e)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ]),
    const SizedBox(height: 6),
    if (e.forWhom.isNotEmpty)
      Text(e.forWhom, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
    Text(e.placeLabel, style: TextStyle(fontSize: 15, color: p.textMuted)),
  ]);
}

Future<void> _guard(BuildContext context, Future<void> Function() action, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done, style: const TextStyle(fontSize: 16))));
  } on AppError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Анкета при отказ: причина (по желание) и предлаган заместник (по желание).
Future<void> showDeclineSheet(BuildContext context, ChurchEvent e) async {
  final s = AppScope.read(context);
  final reason = TextEditingController();
  String? substitute;
  final day = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
  final others = s
      .priestsOf(e.churchId)
      .where((x) => x.$1.id != s.currentUser?.id && !s.isOnLeave(e.churchId, x.$1.id, day))
      .toList();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final p = Palette.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Отказ от събитие',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Отказът отива при председателя. Двете полета са по желание.',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
              const SizedBox(height: 16),
              const FieldLabel('Защо? (по желание)'),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: 'например служба в друг храм'),
              ),
              const SizedBox(height: 8),
              const FieldLabel('Кого предлагате за заместник? (по желание)'),
              DropdownButtonFormField<String?>(
                initialValue: substitute,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Без предложение')),
                  for (final (u, _) in others)
                    DropdownMenuItem<String?>(
                      value: u.id,
                      child: Row(children: [
                        PriestBadge(
                            name: u.fullName, color: p.priest(s.priestIndex(e.churchId, u.id)), size: 26),
                        const SizedBox(width: 10),
                        Flexible(child: Text(u.fullName, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                ],
                onChanged: (v) => setSheet(() => substitute = v),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Изпрати на председателя'),
              ),
              const SizedBox(height: 6),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
            ]),
          ),
        );
      },
    ),
  );
  if (ok != true || !context.mounted) {
    reason.dispose();
    return;
  }
  final text = reason.text;
  reason.dispose();
  await _guard(
      context,
      () => s.respondAssignment(e, accept: false, reason: text, substituteId: substitute),
      'Отказът е изпратен на председателя.');
}

/// „Моля, потвърдете“: събитие, записано от колега за мен.
class AwaitingCard extends StatefulWidget {
  final ChurchEvent event;
  const AwaitingCard({super.key, required this.event});

  @override
  State<AwaitingCard> createState() => _AwaitingCardState();
}

class _AwaitingCardState extends State<AwaitingCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Картата е пред очите на свещеника – отбелязваме „видяно“.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).markSeen(widget.event);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = widget.event;
    return _RequestFrame(tag: 'Моля, потвърдете', icon: Icons.event_available_outlined, children: [
      _eventTitle(context, e),
      const SizedBox(height: 4),
      Text('Записа ${s.ownerName(e)}', style: TextStyle(fontSize: 15, color: p.textMuted)),
      if (e.note.isNotEmpty)
        Text(e.note, style: TextStyle(fontSize: 15, color: p.textMuted)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => showDeclineSheet(context, e),
            child: const Text('Отказвам'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await _guard(context, () => s.respondAssignment(e, accept: true),
                        'Прието – събитието е в календара ви.');
                    if (mounted) setState(() => _busy = false);
                  },
            child: const Text('Приемам'),
          ),
        ),
      ]),
    ]);
  }
}

/// „Отказано събитие“: председателят избира заместник или оставя на същия.
class DeclinedReviewCard extends StatefulWidget {
  final ChurchEvent event;
  const DeclinedReviewCard({super.key, required this.event});

  @override
  State<DeclinedReviewCard> createState() => _DeclinedReviewCardState();
}

class _DeclinedReviewCardState extends State<DeclinedReviewCard> {
  late String? _pick = widget.event.proposedSubstituteId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = widget.event;
    final decliner = e.declinedById ?? e.assigneeId;
    final day = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
    final options = s
        .priestsOf(e.churchId)
        .where((x) => x.$1.id != decliner && !s.isOnLeave(e.churchId, x.$1.id, day))
        .toList();
    if (_pick != null && !options.any((x) => x.$1.id == _pick)) _pick = null;
    final proposed = e.proposedSubstituteId == null ? '' : s.priestName(e.proposedSubstituteId!);

    Future<void> go(String assignee, String done) async {
      setState(() => _busy = true);
      await _guard(context, () => s.resolveDecline(e, assignee), done);
      if (mounted) setState(() => _busy = false);
    }

    return _RequestFrame(tag: 'Отказано събитие', icon: Icons.swap_horiz_rounded, children: [
      _eventTitle(context, e),
      const SizedBox(height: 8),
      Text('${s.priestName(decliner)} отказа', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      Text(e.declineReason.isEmpty ? 'Без посочена причина' : 'Причина: ${e.declineReason}',
          style: TextStyle(fontSize: 15, color: p.textMuted)),
      if (proposed.isNotEmpty)
        Text('Предлага: $proposed', style: TextStyle(fontSize: 15, color: p.textMuted)),
      const SizedBox(height: 12),
      const FieldLabel('Заместник'),
      DropdownButtonFormField<String?>(
        initialValue: _pick,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
        hint: const Text('Изберете свещеник'),
        items: [
          for (final (u, _) in options)
            DropdownMenuItem<String?>(
              value: u.id,
              child: Row(children: [
                PriestBadge(name: u.fullName, color: p.priest(s.priestIndex(e.churchId, u.id)), size: 26),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                      u.id == s.currentUser?.id
                          ? '${u.fullName} (аз)'
                          : u.id == e.proposedSubstituteId
                              ? '${u.fullName} (предложен)'
                              : u.fullName,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
        ],
        onChanged: _busy ? null : (v) => setState(() => _pick = v),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy || _pick == null
            ? null
            : () => go(_pick!,
                _pick == s.currentUser?.id ? 'Поехте събитието.' : 'Изпратено на заместника за потвърждение.'),
        child: Text(_pick == null ? 'Прехвърли на заместник' : 'Прехвърли на ${s.priestName(_pick!)}'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _busy ? null : () => go(decliner, 'Събитието остава на ${s.priestName(decliner)}.'),
        child: Text('Остави на ${s.priestName(decliner)}'),
      ),
    ]);
  }
}

/// Архиерейска Литургия: всеки свещеник в храма потвърждава участие.
class ArchieraticCard extends StatefulWidget {
  final ChurchEvent event;
  const ArchieraticCard({super.key, required this.event});

  @override
  State<ArchieraticCard> createState() => _ArchieraticCardState();
}

class _ArchieraticCardState extends State<ArchieraticCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = widget.event;
    return _RequestFrame(tag: 'Моля, потвърдете', icon: Icons.church_outlined, children: [
      const Text('Архиерейска Литургия', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('${fmtDayLong(e.startsAt)}, ${fmtTime(e.startsAt)} – ${fmtTime(e.endsAt)}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      Text('записа ${s.ownerName(e)}', style: TextStyle(fontSize: 15, color: p.textMuted)),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                await _guard(context, () => s.confirmEvent(e), 'Участието е потвърдено.');
                if (mounted) setState(() => _busy = false);
              },
        icon: const Icon(Icons.check_rounded),
        label: const Text('Приемам'),
      ),
    ]);
  }
}

/// Кой е потвърдил участие в Архиерейската Литургия (вижда се от всички).
class ArchieraticConfirmations extends StatelessWidget {
  final ChurchEvent event;
  const ArchieraticConfirmations({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = event;
    final priests = s.priestsOf(e.churchId);
    final done = priests.where((x) => s.hasConfirmed(e, x.$1.id)).length;
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Text('Потвърждения', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Text('$done от ${priests.length}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.textMuted)),
        ]),
        const SizedBox(height: 6),
        for (final (u, _) in priests)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              PriestBadge(
                  name: u.fullName, color: p.priest(s.priestIndex(e.churchId, u.id)), size: 32, userId: u.id),
              const SizedBox(width: 10),
              Expanded(child: Text(u.fullName, style: const TextStyle(fontSize: 16))),
              if (s.hasConfirmed(e, u.id))
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded, size: 20, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(
                      e.ownerId == u.id
                          ? 'записа'
                          : fmtWhenShort(s.confirmationsFor(e.id)[u.id]!),
                      style: TextStyle(fontSize: 14, color: p.textMuted)),
                ])
              else
                Text('чака', style: TextStyle(fontSize: 14, color: p.textMuted)),
            ]),
          ),
      ]),
    );
  }
}

/// Заявка за почивка за одобрение (вижда я председателят).
class LeaveReviewCard extends StatefulWidget {
  final LeaveRequest leave;
  const LeaveReviewCard({super.key, required this.leave});

  @override
  State<LeaveReviewCard> createState() => _LeaveReviewCardState();
}

class _LeaveReviewCardState extends State<LeaveReviewCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final l = widget.leave;

    Future<void> go(bool approve) async {
      var note = '';
      if (!approve) {
        final c = await askComment(context,
            title: 'Отказ на почивката',
            body: '${s.priestName(l.userId)} · ${fmtLeavePeriod(l)}\nПричината ще получи като известие.',
            hint: 'напр. „Имаме кръщене тогава“',
            label: 'Причина за отказа (по желание)',
            action: 'Откажи');
        if (c == null || !mounted) return;
        note = c;
      }
      setState(() => _busy = true);
      await _guard(context, () => s.decideLeave(l, approve, note: note),
          approve ? 'Почивката е одобрена.' : 'Почивката не е одобрена.');
      if (mounted) setState(() => _busy = false);
    }

    return _RequestFrame(tag: 'Заявка за почивка', icon: Icons.beach_access_outlined, children: [
      Row(children: [
        PriestBadge(name: s.priestName(l.userId), color: p.priest(s.priestIndex(l.churchId, l.userId)), size: 36, userId: l.userId),
        const SizedBox(width: 10),
        Expanded(
          child: Text(s.priestName(l.userId), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 6),
      Text('${fmtLeavePeriod(l)} · ${l.days == 1 ? '1 ден' : '${l.days} дни'}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      if (l.note.isNotEmpty) Text(l.note, style: TextStyle(fontSize: 15, color: p.textMuted)),
      for (final d in s.dutiesOf(l.churchId).where((d) => d.userId == l.userId && d.overlaps(l.start, l.end)))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Внимание: дежурен е ${fmtDutyPeriod(d.start, d.end)}. При одобрение сменете дежурния в графика.',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _busy ? null : () => go(false), child: const Text('Откажи'))),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : () => go(true),
            child: const Text('Одобри'),
          ),
        ),
      ]),
    ]);
  }
}

/// Предложение да стана председател: приемам (с потвърждение) или отказвам.
class ChairOfferCard extends StatefulWidget {
  final Church church;
  const ChairOfferCard({super.key, required this.church});

  @override
  State<ChairOfferCard> createState() => _ChairOfferCardState();
}

class _ChairOfferCardState extends State<ChairOfferCard> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    final s = AppScope.read(context);
    final c = widget.church;
    final from = s.priestName(c.chairProposedById ?? '');
    final ok = await confirm(
        context,
        accept ? 'Ставате председател?' : 'Отказвате?',
        accept
            ? 'Получавате председателските права в ${c.name}: одобрявате свещеници и почивки, '
                'решавате откази, давате права. $from става редови свещеник.'
            : '$from остава председател на ${c.name}.',
        accept ? 'Да, приемам' : 'Отказвам');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await _guard(context, () => s.respondChair(c.id, accept),
        accept ? 'Вече сте председател на ${c.name}.' : 'Отказахте председателството.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final c = widget.church;
    return _RequestFrame(tag: 'Предложение', icon: Icons.workspace_premium_outlined, children: [
      Text('Да станете председател на ${c.name}',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Предлага ${s.priestName(c.chairProposedById ?? '')}. Ако приемете, той става редови свещеник.',
          style: TextStyle(fontSize: 15, color: p.textMuted)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _answer(false), child: const Text('Отказвам'))),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : () => _answer(true),
            child: const Text('Приемам'),
          ),
        ),
      ]),
    ]);
  }
}

/// Всички молби за текущия храм: моите потвърждения, а за председателя –
/// откази и почивки. Слага се на началния екран и в календара.
List<Widget> requestCards(AppState s) {
  final church = s.currentChurchId;
  if (church == null) return [];
  return [
    for (final l in s.leavesToAck(church))
      Padding(padding: const EdgeInsets.only(bottom: 12), child: LeaveDecisionCard(key: ValueKey('la${l.id}'), leave: l)),
    for (final e in s.cashReturnsToAck(church))
      Padding(padding: const EdgeInsets.only(bottom: 12), child: CashReturnedCard(key: ValueKey('cr${e.id}'), entry: e)),
    for (final c in s.chairOffers.where((c) => c.id == church))
      Padding(padding: const EdgeInsets.only(bottom: 12), child: ChairOfferCard(key: ValueKey('ch${c.id}'), church: c)),
    for (final e in s.archieraticToConfirm.where((e) => e.churchId == church))
      Padding(padding: const EdgeInsets.only(bottom: 12), child: ArchieraticCard(key: ValueKey('ar${e.id}'), event: e)),
    for (final e in s.awaitingMyConfirmation.where((e) => e.churchId == church))
      Padding(padding: const EdgeInsets.only(bottom: 12), child: AwaitingCard(key: ValueKey('aw${e.id}'), event: e)),
    for (final e in s.declinedForReview(church))
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DeclinedReviewCard(key: ValueKey('dr${e.id}'), event: e)),
    if (s.lowStock(church).isNotEmpty)
      Padding(padding: const EdgeInsets.only(bottom: 12), child: LowStockCard(items: s.lowStock(church))),
    for (final mv in s.stockToDecide(church))
      Padding(padding: const EdgeInsets.only(bottom: 12), child: StockReviewCard(key: ValueKey('st${mv.id}'), move: mv)),
    for (final per in s.closesToApprove(church))
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CloseMonthCard(key: ValueKey('cm${per.month}'), period: per)),
    for (final c in s.cashToDecide(church))
      Padding(padding: const EdgeInsets.only(bottom: 12), child: CashReviewCard(key: ValueKey('cs${c.id}'), entry: c)),
    for (final w in [...s.swapsForMe(church), ...s.swapsForChair(church)])
      Padding(padding: const EdgeInsets.only(bottom: 12), child: DutySwapCard(key: ValueKey('ds${w.id}'), swap: w)),
    for (final l in s.pendingLeaves(church))
      Padding(
          padding: const EdgeInsets.only(bottom: 12), child: LeaveReviewCard(key: ValueKey('lv${l.id}'), leave: l)),
  ];
}


/// Молба за размяна на дежурства: към колегата (приема/отказва) или към
/// председателя (одобрява/отказва).
class DutySwapCard extends StatefulWidget {
  final DutySwap swap;
  const DutySwapCard({super.key, required this.swap});

  @override
  State<DutySwapCard> createState() => _DutySwapCardState();
}

class _DutySwapCardState extends State<DutySwapCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final w = widget.swap;
    final a = s.dutyById(w.fromDuty);
    final b = s.dutyById(w.toDuty);
    final forChair = w.status == 'chair';
    final ra = a == null ? '' : fmtDutyPeriod(a.start, a.end);
    final rb = b == null ? '' : fmtDutyPeriod(b.start, b.end);

    Future<void> go(bool yes) async {
      var reason = '';
      if (forChair && !yes) {
        final c = await askComment(context,
            title: 'Отказ на размяната',
            body: '${s.priestName(w.fromUser)} ⇄ ${s.priestName(w.toUser)}',
            hint: 'Причина (по желание)',
            action: 'Откажи');
        if (c == null || !mounted) return;
        reason = c;
      }
      setState(() => _busy = true);
      await _guard(
          context,
          () => forChair ? s.decideSwap(w, yes, reason) : s.answerSwap(w, yes),
          yes
              ? (forChair ? 'Размяната е одобрена.' : 'Приехте – чака председателя.')
              : 'Размяната е отказана.');
      if (mounted) setState(() => _busy = false);
    }

    Widget side(String user, String range) => Row(children: [
          PriestBadge(name: s.priestName(user), color: p.priest(s.priestIndex(w.churchId, user)), size: 30, userId: user),
          const SizedBox(width: 8),
          Expanded(child: Text(s.priestName(user), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
          Text(range, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]);

    return _RequestFrame(tag: forChair ? 'Размяна на дежурства' : 'Молба за размяна', icon: Icons.swap_horiz_rounded, children: [
      if (!forChair)
        Text('${s.priestName(w.fromUser)} предлага да си размените дежурствата:',
            style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 6),
      side(w.fromUser, ra),
      const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Icon(Icons.swap_vert_rounded)),
      side(w.toUser, rb),
      if (w.note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('„${w.note}“', style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: p.text)),
        ),
      if (!forChair)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('След като приемете, одобрява председателят.', style: TextStyle(fontSize: 13.5, color: p.textMuted)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _busy ? null : () => go(false), child: const Text('Откажи'))),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : () => go(true),
            child: Text(forChair ? 'Одобри' : 'Приемам'),
          ),
        ),
      ]),
    ]);
  }
}


/// Рамка на известие с „ОК“ – цветна според това дали е добра или лоша новина.
class _AckFrame extends StatefulWidget {
  final Color color;
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Future<void> Function() onOk;
  const _AckFrame({required this.color, required this.icon, required this.title, required this.children, required this.onOk});

  @override
  State<_AckFrame> createState() => _AckFrameState();
}

class _AckFrameState extends State<_AckFrame> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: p.dark ? .18 : .10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.color, width: 2.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(widget.icon, color: widget.color, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        ...widget.children,
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50), backgroundColor: widget.color, foregroundColor: Colors.white),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.onOk();
                  } on AppError catch (e) {
                    if (context.mounted) showMessage(context, e.message);
                  }
                  if (mounted) setState(() => _busy = false);
                },
          child: const Text('ОК', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

/// Решение по моята почивка – стои, докато не натисна „ОК“.
class LeaveDecisionCard extends StatelessWidget {
  final LeaveRequest leave;
  const LeaveDecisionCard({super.key, required this.leave});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = leave;
    final (color, icon, title, by, note) = l.status == LeaveStatus.ended
        ? (const Color(0xFFC0392B), Icons.event_busy_rounded, 'Почивката ви е отменена', l.endedBy, l.endNote)
        : l.cutShort
            ? (const Color(0xFFD35400), Icons.timelapse_rounded, 'Почивката ви е прекратена', l.endedBy, l.endNote)
            : l.status == LeaveStatus.approved
                ? (const Color(0xFF2E7D4F), Icons.check_circle_rounded, 'Почивката ви е одобрена', l.decidedBy, l.decisionNote)
                : (const Color(0xFFC0392B), Icons.cancel_rounded, 'Почивката ви не е одобрена', l.decidedBy, l.decisionNote);
    final dm = DateFormat('d.MM');
    return _AckFrame(
      color: color,
      icon: icon,
      title: title,
      onOk: () => s.ackLeave(l),
      children: [
        Text(
            l.cutShort
                ? '${dm.format(l.start)} – ${dm.format(l.plannedEnd!)} · последен ден ${dm.format(l.end)}'
                : '${fmtLeavePeriod(l)} · ${l.days == 1 ? '1 ден' : '${l.days} дни'}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        if (by != null) Text('Председател: ${s.priestName(by)}', style: const TextStyle(fontSize: 15.5)),
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('„$note“', style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
}

/// Мой запис в касата, върнат от другия – стои, докато не натисна „ОК“.
class CashReturnedCard extends StatelessWidget {
  final CashEntry entry;
  const CashReturnedCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final e = entry;
    return _AckFrame(
      color: const Color(0xFFC0392B),
      icon: Icons.undo_rounded,
      title: 'Записът ви в касата е върнат',
      onOk: () => s.ackCashReturn(e),
      children: [
        Text('${e.kindLabel} · ${fmtEur(e.amount.abs())}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text('${e.categoryLabel} · ${DateFormat('d.MM.y').format(e.date)}', style: const TextStyle(fontSize: 15.5)),
        if (e.decidedBy != null) Text('Върна: ${s.priestName(e.decidedBy!)}', style: const TextStyle(fontSize: 15.5)),
        if (e.returnReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Причина: „${e.returnReason}“', style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
          ),
        const SizedBox(height: 4),
        const Text('Записът не влиза в книгите. Ако е нужно, въведете го отново поправен.',
            style: TextStyle(fontSize: 14)),
      ],
    );
  }
}
