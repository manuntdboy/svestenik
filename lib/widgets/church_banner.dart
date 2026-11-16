import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import 'common.dart';

/// Моята роля в храма – председател, касиер или свещеник.
enum ChurchRole {
  chair('Председател', Icons.workspace_premium_rounded, Color(0xFFE3AE17), Color(0xFF3B2A00)),
  cashier('Касиер', Icons.payments_rounded, Color(0xFF2E7D4F), Colors.white),
  priest('Свещеник', Icons.person_rounded, Color(0xFF2F5D8C), Colors.white);

  final String label;
  final IconData icon;
  final Color color;
  final Color onColor;
  const ChurchRole(this.label, this.icon, this.color, this.onColor);
}

ChurchRole roleIn(AppState s, String churchId) {
  if (s.isManagerOf(churchId)) return ChurchRole.chair;
  if (s.cashierOf(churchId) == s.currentUser?.id) return ChurchRole.cashier;
  return ChurchRole.priest;
}

class RoleBadge extends StatelessWidget {
  final ChurchRole role;
  final bool small;
  const RoleBadge(this.role, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 2 : 4),
        decoration: BoxDecoration(color: role.color, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(role.icon, size: small ? 14 : 16, color: role.onColor),
          const SizedBox(width: 4),
          Text(role.label,
              style: TextStyle(fontSize: small ? 12.5 : 14, fontWeight: FontWeight.w800, color: role.onColor)),
        ]),
      );
}

/// Избор на храм (падащо меню отдолу), с ролята ми във всеки.
/// Звездичката отбелязва основния храм; числата показват какво чака в
/// другите храмове (златисто – за решение, синьо – чат).
void pickChurch(BuildContext context) {
  final s = AppScope.read(context);
  showAppSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: s,
        builder: (ctx, _) {
          final p = Palette.of(ctx);
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 2),
                  child: Text('Изберете храм', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('★ – основен храм: най-отгоре и с него се отваря Кайрос.',
                      style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                ),
                for (final c in s.myChurches)
                  _ChurchPickTile(church: c, onPick: () {
                    Navigator.pop(ctx);
                    if (c.id != s.currentChurchId) s.selectChurch(c.id);
                  }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _ChurchPickTile extends StatelessWidget {
  final Church church;
  final VoidCallback onPick;
  const _ChurchPickTile({required this.church, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    final p = Palette.of(context);
    final c = church;
    final current = c.id == s.currentChurchId;
    final primary = s.isPrimary(c.id);
    final waiting = current ? 0 : s.waitingIn(c.id);
    final unread = s.chatOn && !current ? s.chatUnreadTotal(c.id) : 0;
    Widget count(int n, Color bg, Color fg, IconData icon, String tip) => Tooltip(
          message: tip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 4),
              Text(n > 99 ? '99+' : '$n',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
            ]),
          ),
        );
    return ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsets.only(left: 6, right: 16),
      leading: IconButton(
        tooltip: primary ? 'Основен храм (натиснете, за да махнете)' : 'Направи основен',
        icon: Icon(primary ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 30, color: primary ? Palette.yellow : p.textMuted),
        onPressed: () async {
          try {
            await s.setPrimaryChurch(primary ? null : c.id);
            if (context.mounted) {
              showMessage(context, primary ? 'Няма основен храм.' : 'Основен храм: ${c.name}');
            }
          } on AppError catch (e) {
            if (context.mounted) showMessage(context, e.message);
          }
        },
      ),
      title: Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          RoleBadge(roleIn(s, c.id), small: true),
          Text(c.place),
        ]),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (waiting > 0)
          count(waiting, Palette.yellow, const Color(0xFF3B2A00), Icons.pending_actions_rounded,
              'Чака ви: $waiting'),
        if (waiting > 0 && unread > 0) const SizedBox(width: 6),
        if (unread > 0)
          count(unread, const Color(0xFF2F5D8C), Colors.white, Icons.chat_bubble_rounded,
              'Непрочетени съобщения: $unread'),
        if (current) const Icon(Icons.check_circle_rounded),
      ]),
      onTap: onPick,
    );
  }
}

/// Лента „в кой храм съм и с каква роля“. Цветът следва ролята:
/// председател – златно, касиер – зелено, свещеник – синьо.
/// При повече храмове е падащо меню за смяна.
class ChurchBanner extends StatelessWidget {
  final String? title; // напр. „Каса на храма“
  const ChurchBanner({super.key, this.title});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final c = s.currentChurch;
    if (c == null) return const SizedBox.shrink();
    final role = roleIn(s, c.id);
    final many = s.myChurches.length > 1;
    return Material(
      color: role.color.withValues(alpha: p.dark ? .20 : .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: role.color, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: many ? () => pickChurch(context) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: role.color, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.church_rounded, color: role.onColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (title != null)
                  Text(title!, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.textMuted)),
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  RoleBadge(role, small: true),
                  Text(c.settlement, style: TextStyle(fontSize: 13, color: p.textMuted)),
                ]),
              ]),
            ),
            if (many)
              Column(mainAxisSize: MainAxisSize.min, children: [
                // Червена точка – нови съобщения или нещо чакащо в друг мой храм.
                Badge(
                  isLabelVisible: (s.chatOn && s.chatUnreadOther().isNotEmpty) || s.waitingElsewhere,
                  smallSize: 10,
                  child: const Icon(Icons.unfold_more_rounded),
                ),
                Text('смени', style: TextStyle(fontSize: 11.5, color: p.textMuted)),
              ]),
          ]),
        ),
      ),
    );
  }
}

/// Ред „Храм: …“ над бутона за запис – да не се запише в друг храм по грешка.
class ChurchConfirmLine extends StatelessWidget {
  const ChurchConfirmLine({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.currentChurch;
    if (c == null) return const SizedBox.shrink();
    final role = roleIn(s, c.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: role.color.withValues(alpha: .6)),
      ),
      child: Row(children: [
        Icon(Icons.church_rounded, color: role.color),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Записва се в: '),
            TextSpan(text: c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]), style: const TextStyle(fontSize: 15.5)),
        ),
      ]),
    );
  }
}
