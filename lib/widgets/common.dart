import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../theme.dart';

final _fmtTime = DateFormat('HH:mm', 'bg');
final _fmtDayLong = DateFormat('EEEE, d MMMM', 'bg');
final _fmtDayMonth = DateFormat('d MMMM', 'bg');

String fmtTime(DateTime d) => _fmtTime.format(d);

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// „Четвъртък, 12 ноември“
String fmtDayLong(DateTime d) => capitalize(_fmtDayLong.format(d));

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// „Днес, четвъртък 12 ноември“ / „Утре, …“ / „Петък, 13 ноември“
String fmtDayHeading(DateTime d) {
  final now = DateTime.now();
  final weekday = DateFormat('EEEE', 'bg').format(d);
  final dm = _fmtDayMonth.format(d);
  if (sameDay(d, now)) return 'Днес, $weekday $dm';
  if (sameDay(d, now.add(const Duration(days: 1)))) return 'Утре, $weekday $dm';
  return capitalize('$weekday, $dm');
}

/// Етикет „след 2 часа“, „утре“, „след 3 дни“ или null, ако е минало.
String? timeUntil(DateTime t) {
  final now = DateTime.now();
  final diff = t.difference(now);
  if (diff.isNegative) return null;
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return 'след $m мин';
  }
  if (sameDay(t, now)) {
    final h = (diff.inMinutes / 60).round();
    return h == 1 ? 'след 1 час' : 'след $h часа';
  }
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(t.year, t.month, t.day).difference(today).inDays;
  if (days == 1) return 'утре';
  return 'след $days дни';
}

String eventsCount(int n) => n == 1 ? '1 събитие' : '$n събития';

class KindChip extends StatelessWidget {
  final EventKind kind;
  final double fontSize;
  const KindChip(this.kind, {super.key, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = Palette.of(context).kind(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(kind.label,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// „11:00 – 11:30“
String fmtRange(ChurchEvent e) => '${fmtTime(e.startsAt)} – ${fmtTime(e.endsAt)}';

/// Кратко описание на събитие за предупрежденията: „11:00 – 11:30 Кръщене, Иван Петров“
String eventShortLabel(ChurchEvent e) {
  final who = e.forWhom.isEmpty ? '' : ', ${e.forWhom}';
  final day = sameDay(e.startsAt, DateTime.now()) ? '' : '${fmtDayLong(e.startsAt)}, ';
  return '$day${fmtRange(e)} ${e.kind.label}$who';
}

/// Предупреждение, че събитието се застъпва с други събития.
class OverlapNotice extends StatelessWidget {
  final List<ChurchEvent> overlaps;
  /// Име на храм за събитията от друг храм (по желание).
  final String Function(ChurchEvent)? otherChurch;
  const OverlapNotice(this.overlaps, {super.key, this.otherChurch});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bg = p.dark ? const Color(0xFF3F3420) : const Color(0xFFFFF1CC);
    final fg = p.dark ? const Color(0xFFEBCF9C) : const Color(0xFF5C3F08);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: fg, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    overlaps.length == 1
                        ? 'Застъпва се с друго събитие'
                        : 'Застъпва се с ${overlaps.length} събития',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
                const SizedBox(height: 4),
                for (final o in overlaps)
                  Text(
                      eventShortLabel(o) +
                          (otherChurch == null || otherChurch!(o).isEmpty
                              ? ''
                              : ' (${otherChurch!(o)})'),
                      style: TextStyle(fontSize: 15, color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class YellowTag extends StatelessWidget {
  final String text;
  const YellowTag(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
            color: Palette.yellow, borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: Palette.onYellow)),
      );
}

/// Бяла карта с рамка, както в макетите.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const SurfaceCard(
      {super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.border),
      ),
      child: child,
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Palette.of(context).textMuted)),
      );
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 16)),
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirm(BuildContext context, String title, String body, String action) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(fontSize: 17)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

/// Инициали на свещеника („Отец Иван Петров“ → „ИП“).
String priestInitials(String fullName) {
  final words = fullName
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !{'отец', 'о.', 'свещеник', 'протойерей', 'иерей'}.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) return fullName.isEmpty ? '?' : fullName[0].toUpperCase();
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}

/// Кръг с инициалите на свещеника в неговия цвят.
class PriestBadge extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const PriestBadge({super.key, required this.name, required this.color, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(priestInitials(name),
            style: TextStyle(
                fontSize: size * 0.4, fontWeight: FontWeight.w800, color: p.onPriest())),
      ),
    );
  }
}
