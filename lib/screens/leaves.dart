import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/requests.dart';

/// Почивки: заявка (само дати), моите заявки, а председателят – одобрение
/// и всички одобрени. Одобрените виждат всички в храма и в календара.
class LeavesScreen extends StatelessWidget {
  const LeavesScreen({super.key});

  Future<void> _request(BuildContext context) async {
    final s = AppScope.read(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Изберете дните на почивката',
      saveText: 'Избери',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (range == null || !context.mounted) return;
    final note = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заявка за почивка'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              fmtLeavePeriod(LeaveRequest(
                  id: '', churchId: '', userId: '', start: range.start, end: range.end)),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(hintText: 'Бележка (по желание)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Изпрати')),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (send != true || !context.mounted) return;
    try {
      await s.requestLeave(range.start, range.end, text);
      if (context.mounted) {
        showMessage(context, s.isManagerOf(s.currentChurchId!)
            ? 'Заявката е създадена – одобрете я по-долу.'
            : 'Заявката е изпратена на председателя.');
      }
    } on AppError catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final manager = s.isManagerOf(church);
    final mine = s.myLeaves(church);
    final pending = s.pendingLeaves(church);
    final approved = s.approvedLeaves(church);

    Widget leaveRow(LeaveRequest l, {bool showName = false, bool canCancel = false}) {
      final st = l.status;
      final (bg, fg) = switch (st) {
        LeaveStatus.approved => (const Color(0xFFDDF0EC), const Color(0xFF14584D)),
        LeaveStatus.rejected => (const Color(0xFFF4E0E4), const Color(0xFF7A2438)),
        LeaveStatus.pending => (Palette.yellow, Palette.onYellow),
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SurfaceCard(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            if (showName) ...[
              PriestBadge(name: s.priestName(l.userId), color: p.priest(s.priestIndex(church, l.userId)), size: 32, userId: l.userId),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showName)
                  Text(s.priestName(l.userId), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${fmtLeavePeriod(l)} · ${l.days == 1 ? '1 ден' : '${l.days} дни'}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                if (l.note.isNotEmpty) Text(l.note, style: TextStyle(fontSize: 14, color: p.textMuted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Text(st.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            ),
            if (canCancel)
              IconButton(
                tooltip: st == LeaveStatus.pending ? 'Оттегли заявката' : 'Отмени почивката',
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  final ok = await confirm(
                      context,
                      st == LeaveStatus.pending ? 'Оттегли заявката?' : 'Отмени почивката?',
                      fmtLeavePeriod(l),
                      st == LeaveStatus.pending ? 'Оттегли' : 'Отмени');
                  if (!ok || !context.mounted) return;
                  try {
                    await s.cancelLeave(l);
                  } on AppError catch (e) {
                    if (context.mounted) showMessage(context, e.message);
                  }
                },
              ),
          ]),
        ),
      );
    }

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Почивки')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text('Почивката е за цели дни. Одобрените виждат всички в храма в календара, '
                  'а в тези дни свещеникът не излиза за избор при записване на събитие.',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _request(context),
                icon: const Icon(Icons.beach_access_outlined),
                label: const Text('Заяви почивка'),
              ),
              if (manager && pending.isNotEmpty) ...[
                heading('Чакат одобрение'),
                for (final l in pending)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: LeaveReviewCard(leave: l)),
              ],
              heading('Моите заявки'),
              if (mine.isEmpty)
                Text('Нямате заявки.', style: TextStyle(fontSize: 16, color: p.textMuted)),
              for (final l in mine)
                leaveRow(l, canCancel: l.status == LeaveStatus.pending || (manager && l.status == LeaveStatus.approved)),
              heading('Одобрени почивки в храма'),
              if (approved.isEmpty)
                Text('Няма предстоящи почивки.', style: TextStyle(fontSize: 16, color: p.textMuted)),
              for (final l in approved) leaveRow(l, showName: true, canCancel: manager),
            ],
          ),
        ),
      ),
    );
  }
}


/// Една заявка за почивка – отваря се от известието.
/// Председателят решава тук („Одобри“ / „Откажи“); заявилият вижда решението.
class LeaveRequestScreen extends StatelessWidget {
  final String requestId;
  const LeaveRequestScreen({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final l = s.leaveById(requestId);
    Widget body;
    if (l == null) {
      body = Text('Заявката е оттеглена или отменена.',
          style: TextStyle(fontSize: 17, color: p.textMuted));
    } else if (l.status == LeaveStatus.pending && s.isManagerOf(l.churchId)) {
      body = LeaveReviewCard(leave: l);
    } else {
      final approved = l.status == LeaveStatus.approved;
      final rejected = l.status == LeaveStatus.rejected;
      body = SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            PriestBadge(
                name: s.priestName(l.userId),
                color: p.priest(s.priestIndex(l.churchId, l.userId)),
                size: 40,
                userId: l.userId),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.priestName(l.userId),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 10),
          Text('${fmtLeavePeriod(l)} · ${l.days == 1 ? '1 ден' : '${l.days} дни'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (l.note.isNotEmpty) Text(l.note, style: TextStyle(fontSize: 15, color: p.textMuted)),
          const SizedBox(height: 14),
          Row(children: [
            Icon(
                approved
                    ? Icons.check_circle_rounded
                    : rejected
                        ? Icons.cancel_rounded
                        : Icons.hourglass_top_rounded,
                color: approved
                    ? Colors.green.shade600
                    : rejected
                        ? Theme.of(context).colorScheme.error
                        : p.textMuted),
            const SizedBox(width: 8),
            Text(
                approved
                    ? 'Одобрена'
                    : rejected
                        ? 'Не е одобрена'
                        : 'Чака одобрение от председателя',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Заявка за почивка')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              body,
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LeavesScreen())),
                child: const Text('Всички почивки'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
