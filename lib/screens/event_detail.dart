import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_form.dart';
import '../widgets/requests.dart';

class EventDetailScreen extends StatelessWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = s.eventById(eventId);
    if (e == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Събитието е изтрито.')));
    }
    final until = e.status == EventStatus.planned ? timeUntil(e.startsAt) : null;
    final canEdit = s.canEdit(e);

    Widget row(String label, String value, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 14, color: p.textMuted)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Събитие')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: p.heroBg,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: p.heroBorder),
              ),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      KindChip(e.kind, fontSize: 14),
                      const Spacer(),
                      if (until != null) YellowTag(until),
                      if (e.status != EventStatus.planned) _StatusTag(e.status),
                    ]),
                    const SizedBox(height: 12),
                    Text(fmtDayLong(e.startsAt),
                        style: TextStyle(fontSize: 16, color: p.heroMuted)),
                    Text(fmtTime(e.startsAt),
                        style: const TextStyle(
                            fontSize: 56, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -2)),
                    Text('до ${fmtTime(e.endsAt)} · ${fmtDuration(e.durationMinutes)}',
                        style: TextStyle(fontSize: 16, color: p.heroMuted)),
                    const SizedBox(height: 6),
                    Text(e.forWhom.isEmpty ? e.kind.label : e.forWhom,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            if (canEdit && s.overlapsFor(e).isNotEmpty) ...[
              const SizedBox(height: 14),
              OverlapNotice(
                s.overlapsFor(e),
                otherChurch: (o) => o.churchId == e.churchId ? '' : s.churchName(o.churchId),
              ),
            ],
            // Моля, потвърдете / решение на председателя – направо тук.
            if (e.awaitsConfirmation && e.assigneeId == s.currentUser?.id) ...[
              const SizedBox(height: 14),
              AwaitingCard(event: e),
            ],
            if (e.isDeclined && s.isManagerOf(e.churchId)) ...[
              const SizedBox(height: 14),
              DeclinedReviewCard(event: e),
            ],
            if (s.placeOverlapsFor(e).isNotEmpty) ...[
              const SizedBox(height: 14),
              OverlapNotice(
                s.placeOverlapsFor(e),
                title: 'Храмът е зает по това време',
                suffix: (o) => s.priestName(o.assigneeId),
              ),
            ],
            const SizedBox(height: 14),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  if (e.phone.isNotEmpty) ...[
                    row('Телефон', e.phone),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ContactButtons(e.phone),
                    ),
                  ],
                  row('Свещеник',
                      s.isMine(e) ? '${s.priestName(e.assigneeId)} (аз)' : s.priestName(e.assigneeId),
                      trailing: PriestBadge(
                          name: s.priestName(e.assigneeId),
                          color: p.priest(s.priestIndex(e.churchId, e.assigneeId)),
                          size: 40,
                          userId: e.assigneeId)),
                  row('Къде', e.outsideChurch ? 'Извън храма' : 'В храма'),
                  if (e.outsideChurch && e.fullAddress.isNotEmpty)
                    row('Адрес', e.fullAddress,
                        trailing: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                          onPressed: () => openInMaps(context, e.mapsQuery(s.churchSettlement(e.churchId))),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Карта'),
                        )),
                  row('Напомняне', (reminderOptions[e.remindMinutes] ?? 'Без напомняне') + (e.alarm && e.remindMinutes != null ? ' · аларма' : '')),
                  row('Кой го вижда', e.shared ? 'Споделено с храма' : 'Само аз'),
                  // Кой е записал – вижда се от всички.
                  row('Записа', e.ownerId == s.currentUser?.id ? '${s.ownerName(e)} (аз)' : s.ownerName(e)),
                  if (e.ownerId != e.assigneeId)
                    row(
                        'Потвърждение',
                        e.awaitsConfirmation
                            ? 'Чака ${s.priestName(e.assigneeId)} · ${seenLabel(e)}'
                            : e.isDeclined
                                ? 'Отказано${e.declineReason.isEmpty ? '' : ': ${e.declineReason}'} – решава председателят'
                                : 'Прието'),
                  if (e.note.isNotEmpty) row('Бележка', e.note),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (canEdit) ...[
              FilledButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EventFormScreen(draft: e, editing: true))),
                child: const Text('Редактирай'),
              ),
              const SizedBox(height: 10),
              _StatusButtons(event: e),
              const SizedBox(height: 10),
              if (e.assigneeId != e.ownerId)
                const SizedBox.shrink()
              else if (!e.shared)
                OutlinedButton(
                  onPressed: () async {
                    e.shared = true;
                    try {
                      await s.saveEvent(e);
                      if (context.mounted) showMessage(context, 'Събитието е споделено с храма.');
                    } on AppError catch (err) {
                      if (context.mounted) showMessage(context, err.message);
                    }
                  },
                  child: const Text('Сподели с храма'),
                )
              else
                OutlinedButton(
                  onPressed: () async {
                    final ok = await confirm(
                        context,
                        'Направи го лично?',
                        'Събитието ще изчезне от общия календар на храма и колегите няма да го '
                            'виждат. Така може да се запише друго събитие по същото време.',
                        'Направи го лично');
                    if (!ok) return;
                    e.shared = false;
                    try {
                      await s.saveEvent(e);
                      if (context.mounted) showMessage(context, 'Събитието вече е само лично.');
                    } on AppError catch (err) {
                      if (context.mounted) showMessage(context, err.message);
                    }
                  },
                  child: const Text('Направи го лично'),
                ),
              const SizedBox(height: 10),
            ],
            // Копие за друга дата – всеки, който вижда събитието.
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          EventFormScreen(draft: s.copyDraft(e), copying: true))),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Копирай за друга дата'),
            ),
            const SizedBox(height: 10),
            if (s.canDelete(e))
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final ok = await confirm(
                      context, 'Изтриване', 'Събитието ще бъде изтрито.', 'Изтрий');
                  if (!ok || !context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await s.deleteEvent(e.id);
                    nav.pop();
                  } on AppError catch (err) {
                    messenger.showSnackBar(SnackBar(content: Text(err.message)));
                  }
                },
                child: const Text('Изтрий'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Етикет „Проведено“ / „Отменено“ в главната карта.
class _StatusTag extends StatelessWidget {
  final EventStatus status;
  const _StatusTag(this.status);

  @override
  Widget build(BuildContext context) {
    final cancelled = status == EventStatus.cancelled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: cancelled ? const Color(0xFFF4E0E4) : const Color(0xFFDDF0EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status.label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cancelled ? const Color(0xFF7A2438) : const Color(0xFF14584D))),
    );
  }
}

/// Бутони за състоянието: „Проведено“ / „Отменено“ / „Върни като предстоящо“.
class _StatusButtons extends StatelessWidget {
  final ChurchEvent event;
  const _StatusButtons({required this.event});

  Future<void> _set(BuildContext context, EventStatus st) async {
    final s = AppScope.read(context);
    if (st == EventStatus.cancelled) {
      final ok = await confirm(
          context,
          'Отмени събитието?',
          'Събитието остава в календара като „Отменено“, без напомняне. '
              'Часът се освобождава за други събития.',
          'Отмени събитието');
      if (!ok || !context.mounted) return;
    }
    try {
      await s.setStatus(event, st);
      if (context.mounted) {
        showMessage(
            context,
            switch (st) {
              EventStatus.done => 'Отбелязано като проведено.',
              EventStatus.cancelled => 'Събитието е отменено.',
              EventStatus.planned => 'Събитието пак е предстоящо.',
            });
      }
    } on AppError catch (err) {
      if (context.mounted) showMessage(context, err.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (event.status != EventStatus.planned) {
      return OutlinedButton.icon(
        onPressed: () => _set(context, EventStatus.planned),
        icon: const Icon(Icons.undo_rounded),
        label: const Text('Върни като предстоящо'),
      );
    }
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _set(context, EventStatus.done),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Проведено'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _set(context, EventStatus.cancelled),
          icon: const Icon(Icons.event_busy_outlined),
          label: const Text('Отменено'),
        ),
      ),
    ]);
  }
}
