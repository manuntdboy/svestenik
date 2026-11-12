import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_detail.dart';
import 'my_profile.dart';

/// Профил на свещеник в храма: име, роля, цвят и предстоящите му събития.
/// По-късно тук идват рожден ден, имен ден, ръкоположение и снимка.
class PriestProfileScreen extends StatelessWidget {
  final String churchId;
  final String userId;
  const PriestProfileScreen({super.key, required this.churchId, required this.userId});

  Future<void> _editName(BuildContext context, String current) async {
    final s = AppScope.read(context);
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Име'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(hintText: 'например Отец Георги'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отказ')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Запази')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.trim() == current) return;
    try {
      await s.updateFullName(name);
      if (context.mounted) showMessage(context, 'Името е сменено.');
    } on AppError catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final entry = s.priestsOf(churchId).where((x) => x.$1.id == userId).firstOrNull;
    if (entry == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Свещеникът не е намерен.')));
    }
    final (u, m) = entry;
    final me = u.id == s.currentUser?.id;
    // Своя профил показваме по макета „Моят профил“.
    if (me) return const MyProfileScreen();
    final canRemove = s.isManagerOf(churchId);
    final color = p.priest(s.priestIndex(churchId, u.id));
    final now = DateTime.now();
    final upcoming = s.visibleEvents
        .where((e) => e.churchId == churchId && e.assigneeId == u.id && e.startsAt.isAfter(now))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(me ? 'Моят профил' : 'Профил на свещеника')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(child: PriestBadge(name: u.fullName, color: color, size: 96)),
            const SizedBox(height: 12),
            Text(u.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            Text(
                [m.isManager ? 'Председател' : (m.isCashier ? 'Свещеник · касиер' : 'Свещеник'), s.churchName(churchId)].join(' · '),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: p.textMuted)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(me ? 'Вашият цвят в календара' : 'Цвят в календара',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
            ]),
            if (me) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _editName(context, u.fullName),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Промени името'),
              ),
            ],
            const SizedBox(height: 20),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Лични дати',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final label in ['Рожден ден', 'Имен ден', 'Ръкоположение', 'Снимка'])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
                        Text('Скоро', style: TextStyle(fontSize: 15, color: p.textMuted)),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  Text('Ще се попълват тук, за да напомня Кайрос за рождени дни и годишнини.',
                      style: TextStyle(fontSize: 14, color: p.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(me ? 'Моите предстоящи събития' : 'Предстоящи събития',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (upcoming.isEmpty)
              Text('Няма предстоящи събития, които виждате.',
                  style: TextStyle(fontSize: 16, color: p.textMuted)),
            for (final e in upcoming.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: p.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18), side: BorderSide(color: p.border)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: e.id))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${fmtDayLong(e.startsAt)}, ${fmtTime(e.startsAt)}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              Text(e.forWhom.isEmpty ? e.placeLabel : '${e.forWhom} · ${e.placeLabel}',
                                  style: TextStyle(fontSize: 14, color: p.textMuted)),
                            ],
                          ),
                        ),
                        KindChip(e.kind),
                      ]),
                    ),
                  ),
                ),
              ),
            if (!me && upcoming.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Личните му събития не се виждат – само споделените с храма.',
                    style: TextStyle(fontSize: 14, color: p.textMuted)),
              ),
            if (canRemove && !m.isManager) ...[
              const SizedBox(height: 20),
              const Text('Права', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.border),
                ),
                child: SwitchListTile(
                  value: m.isCashier,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('Касиер',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  subtitle: Text('Вижда и води касата на храма. Останалите свещеници нямат достъп.',
                      style: TextStyle(fontSize: 15, color: p.textMuted)),
                  onChanged: (v) async {
                    try {
                      await s.setPermission(churchId, u.id, 'cash', v);
                      if (context.mounted) {
                        showMessage(context,
                            v ? '${u.fullName} вече е касиер.' : '${u.fullName} вече не е касиер.');
                      }
                    } on AppError catch (e) {
                      if (context.mounted) showMessage(context, e.message);
                    }
                  },
                ),
              ),
            ],
            if (canRemove) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final ok = await confirm(
                      context,
                      'Премахване от храма',
                      '${u.fullName} няма да вижда споделените събития на храма. '
                          'Събитията, записани за него, остават в календара.',
                      'Премахни');
                  if (!ok) return;
                  try {
                    await s.removeMember(churchId, u.id);
                    nav.pop();
                  } on AppError catch (e) {
                    if (context.mounted) showMessage(context, e.message);
                  }
                },
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Премахни от храма'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
