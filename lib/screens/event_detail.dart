import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_form.dart';

class EventDetailScreen extends StatelessWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) showMessage(context, 'Не може да се отвори телефонът.');
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = s.eventById(eventId);
    if (e == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Събитието е изтрито.')));
    }
    final until = timeUntil(e.startsAt);
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
            const SizedBox(height: 14),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  if (e.phone.isNotEmpty)
                    row('Телефон', e.phone,
                        trailing: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                          onPressed: () => _call(context, e.phone),
                          icon: const Icon(Icons.call_rounded),
                          label: const Text('Обади се'),
                        )),
                  row('Свещеник',
                      s.isMine(e) ? '${s.priestName(e.assigneeId)} (аз)' : s.priestName(e.assigneeId),
                      trailing: PriestBadge(
                          name: s.priestName(e.assigneeId),
                          color: p.priest(s.priestIndex(e.churchId, e.assigneeId)))),
                  row('Къде', e.outsideChurch ? 'Извън храма' : 'В храма'),
                  if (e.outsideChurch && e.address.isNotEmpty) row('Адрес', e.address),
                  row('Напомняне', (reminderOptions[e.remindMinutes] ?? 'Без напомняне') + (e.alarm && e.remindMinutes != null ? ' · аларма' : '')),
                  row('Кой го вижда', e.shared ? 'Споделено с храма' : 'Само аз'),
                  if (e.ownerId != s.currentUser?.id) row('Записа', s.ownerName(e)),
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
            if (s.canDelete(e))
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final ok = await confirm(
                      context, 'Изтриване', 'Събитието ще бъде изтрито.', 'Изтрий');
                  if (!ok) return;
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
