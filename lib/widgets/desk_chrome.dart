import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Кайрос за компютър: горна лента (лого, храм/епархия, търсачка, камбанка,
/// потребител) и тясно меню отляво. Цветовете идват от темата – в
/// митрополитския изглед всичко е в пурпур и злато, иначе в цветовете на Кайрос.

class DeskNavItem {
  final String id;
  final IconData icon;
  final String label;
  final int badge;
  final String? section; // заглавие над елемента (напр. „Храм“)
  const DeskNavItem(this.id, this.icon, this.label, {this.badge = 0, this.section});
}

class SearchHit {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback open;
  const SearchHit(this.icon, this.title, this.subtitle, this.open);
}

class DeskMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const DeskMenuAction(this.icon, this.label, this.onTap);
}

class DeskFrame extends StatelessWidget {
  final Color logoColor;
  final String? logoSuffix; // „Митрополия“
  final VoidCallback onLogo;
  final String chipIcon;
  final String chipTitle;
  final String chipSubtitle;
  final List<DeskMenuAction> chipMenu; // напр. смяна на храма
  final String searchHint;
  final List<SearchHit> Function(String q) search;
  final int bell;
  final String bellTooltip;
  final VoidCallback? onBell;
  final String userInitials;
  final String userName;
  final List<DeskMenuAction> userMenu;
  final List<DeskNavItem> items;
  final String current;
  final ValueChanged<String> onSelect;
  final String footer;
  final Widget? banner;
  final Widget body;

  const DeskFrame({
    super.key,
    required this.logoColor,
    this.logoSuffix,
    required this.onLogo,
    required this.chipIcon,
    required this.chipTitle,
    required this.chipSubtitle,
    this.chipMenu = const [],
    required this.searchHint,
    required this.search,
    this.bell = 0,
    this.bellTooltip = 'Чака вас',
    this.onBell,
    required this.userInitials,
    required this.userName,
    required this.userMenu,
    required this.items,
    required this.current,
    required this.onSelect,
    required this.footer,
    this.banner,
    required this.body,
  });

  void _openSearch(BuildContext context) => showDeskSearch(context, searchHint, search);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyK, control: !mac, meta: mac): () => _openSearch(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(children: [
            _topBar(context, p, mac),
            if (banner != null) banner!,
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _sidebar(context, p),
                Expanded(child: body),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, Palette p, bool mac) {
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: p.chipBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: logoColor.withValues(alpha: .35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: logoColor, borderRadius: BorderRadius.circular(8)),
          child: Center(
              child: Text(chipIcon,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _on(logoColor)))),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(chipTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
            Text(chipSubtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.textMuted)),
          ]),
        ),
        if (chipMenu.isNotEmpty) ...[
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 20, color: p.textMuted),
        ],
      ]),
    );
    return Material(
      color: p.surface,
      child: Container(
        height: 64,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          SizedBox(
            width: 200,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: 'Начало и обновяване',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onLogo,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic, children: [
                      Text('Кайрос', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: logoColor)),
                      if (logoSuffix != null) ...[
                        const SizedBox(width: 6),
                        Text(logoSuffix!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textMuted)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
          chipMenu.isEmpty
              ? chip
              : PopupMenuButton<int>(
                  tooltip: '',
                  position: PopupMenuPosition.under,
                  onSelected: (i) => chipMenu[i].onTap(),
                  itemBuilder: (_) => [
                    for (var i = 0; i < chipMenu.length; i++)
                      PopupMenuItem(
                        value: i,
                        child: Row(children: [
                          Icon(chipMenu[i].icon, size: 20),
                          const SizedBox(width: 10),
                          Flexible(child: Text(chipMenu[i].label)),
                        ]),
                      ),
                  ],
                  child: chip,
                ),
          const SizedBox(width: 16),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: p.bg,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.border)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openSearch(context),
                    child: SizedBox(
                      height: 40,
                      child: Row(children: [
                        const SizedBox(width: 12),
                        Icon(Icons.search_rounded, color: p.textMuted, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(searchHint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.textMuted, fontSize: 14)),
                        ),
                        Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              border: Border.all(color: p.border), borderRadius: BorderRadius.circular(5)),
                          child: Text(mac ? '⌘ K' : 'Ctrl K', style: TextStyle(fontSize: 11, color: p.textMuted)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (onBell != null)
            IconButton(
              tooltip: bell > 0 ? '$bellTooltip: $bell' : bellTooltip,
              onPressed: onBell,
              icon: Badge(
                isLabelVisible: bell > 0,
                label: Text(bell > 99 ? '99+' : '$bell'),
                child: Icon(bell > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                    color: bell > 0 ? logoColor : p.textMuted),
              ),
            ),
          const SizedBox(width: 6),
          PopupMenuButton<int>(
            tooltip: '',
            position: PopupMenuPosition.under,
            onSelected: (i) => userMenu[i].onTap(),
            itemBuilder: (_) => [
              for (var i = 0; i < userMenu.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Row(children: [
                    Icon(userMenu[i].icon, size: 20),
                    const SizedBox(width: 10),
                    Text(userMenu[i].label),
                  ]),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: p.primary,
                  child: Text(userInitials,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.onPrimary)),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                ),
                Icon(Icons.expand_more_rounded, size: 20, color: p.textMuted),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sidebar(BuildContext context, Palette p) {
    final children = <Widget>[];
    for (final it in items) {
      if (it.section != null) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 12, 6),
          child: Text(it.section!.toUpperCase(),
              style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700, color: p.textMuted)),
        ));
      }
      final on = it.id == current;
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: on ? p.primary.withValues(alpha: .14) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelect(it.id),
            child: Container(
              decoration: on ? BoxDecoration(border: Border(left: BorderSide(color: p.primary, width: 3))) : null,
              padding: EdgeInsets.fromLTRB(on ? 11 : 14, 10, 12, 10),
              child: Row(children: [
                Badge(
                  isLabelVisible: it.badge > 0,
                  label: Text(it.badge > 99 ? '99+' : '${it.badge}'),
                  child: Icon(it.icon, size: 21, color: on ? p.primary : p.textMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(it.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on ? p.text : p.textMuted)),
                ),
              ]),
            ),
          ),
        ),
      ));
    }
    return Container(
      width: 216,
      decoration: BoxDecoration(color: p.surfaceAlt, border: Border(right: BorderSide(color: p.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(10, 12, 10, 12), children: children)),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 12, 14),
          child: Text(footer, style: TextStyle(fontSize: 11.5, color: p.textMuted)),
        ),
      ]),
    );
  }
}

Color _on(Color c) => c.computeLuminance() > .45 ? const Color(0xFF1F1A10) : Colors.white;

/// Търсачката (Ctrl K): пишете и избирате с мишката или Enter.
Future<void> showDeskSearch(BuildContext context, String hint, List<SearchHit> Function(String q) search) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _SearchDialog(hint: hint, search: search),
  );
}

class _SearchDialog extends StatefulWidget {
  final String hint;
  final List<SearchHit> Function(String q) search;
  const _SearchDialog({required this.hint, required this.search});

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  String q = '';
  int sel = 0;

  void _open(SearchHit h) {
    Navigator.pop(context);
    h.open();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hits = widget.search(q).take(40).toList();
    if (sel >= hits.length) sel = hits.isEmpty ? 0 : hits.length - 1;
    return Align(
      alignment: const Alignment(0, -.7),
      child: Material(
        color: p.surface,
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Focus(
              onKeyEvent: (_, e) {
                if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setState(() => sel = hits.isEmpty ? 0 : (sel + 1) % hits.length);
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() => sel = hits.isEmpty ? 0 : (sel - 1 + hits.length) % hits.length);
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.enter && hits.isNotEmpty) {
                  _open(hits[sel]);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                ),
                onChanged: (v) => setState(() {
                  q = v;
                  sel = 0;
                }),
              ),
            ),
            Divider(height: 1, color: p.border),
            Flexible(
              child: hits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(q.trim().isEmpty ? 'Започнете да пишете…' : 'Няма намерени.',
                          style: TextStyle(color: p.textMuted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: hits.length,
                      itemBuilder: (_, i) {
                        final h = hits[i];
                        return ListTile(
                          selected: i == sel,
                          selectedTileColor: p.primary.withValues(alpha: .12),
                          leading: Icon(h.icon, color: p.primary),
                          title: Text(h.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: h.subtitle.isEmpty ? null : Text(h.subtitle, style: TextStyle(color: p.textMuted)),
                          onTap: () => _open(h),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(children: [
                Text('↑ ↓ избор · Enter отваря · Esc затваря', style: TextStyle(fontSize: 12, color: p.textMuted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Таблица за компютър: заглавен ред, редове със светване под мишката.
class DeskTable extends StatelessWidget {
  final List<(String, int)> columns; // заглавие и тежест (flex)
  final List<int> numeric; // кои колони са числа (подравнени вдясно)
  final List<List<Widget>> rows;
  final List<VoidCallback?>? onTap;
  final List<bool>? dim; // приглушени (върнати/сторнирани)
  const DeskTable({super.key, required this.columns, this.numeric = const [], required this.rows, this.onTap, this.dim});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget cell(int i, Widget w) => Expanded(
          flex: columns[i].$2,
          child: Align(alignment: numeric.contains(i) ? Alignment.centerRight : Alignment.centerLeft, child: w),
        );
    return Container(
      decoration: BoxDecoration(
          color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: p.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            for (var i = 0; i < columns.length; i++)
              cell(
                  i,
                  Text(columns[i].$1.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11.5, letterSpacing: .8, fontWeight: FontWeight.w700, color: p.textMuted))),
          ]),
        ),
        for (var r = 0; r < rows.length; r++)
          Material(
            color: Colors.transparent,
            child: InkWell(
              hoverColor: p.primary.withValues(alpha: .08),
              onTap: onTap?[r],
              child: Opacity(
                opacity: (dim?[r] ?? false) ? .6 : 1,
                child: Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border.withValues(alpha: .6)))),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    for (var i = 0; i < columns.length && i < rows[r].length; i++)
                      cell(i, Padding(padding: const EdgeInsets.only(right: 8), child: rows[r][i])),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
