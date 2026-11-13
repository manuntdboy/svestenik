import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';

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
void pickChurch(BuildContext context) {
  final s = AppScope.read(context);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Изберете храм', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          for (final c in s.myChurches)
            ListTile(
              minTileHeight: 64,
              title: Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  RoleBadge(roleIn(s, c.id), small: true),
                  Text(c.place),
                ]),
              ),
              trailing: c.id == s.currentChurchId ? const Icon(Icons.check_circle_rounded) : null,
              onTap: () {
                Navigator.pop(ctx);
                if (c.id != s.currentChurchId) s.selectChurch(c.id);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
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
                const Icon(Icons.unfold_more_rounded),
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
