import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/church_banner.dart';

final _stamp = DateFormat('d MMM y, HH:mm', 'bg');
const _red = Color(0xFFB23A3A);

/// Цвят на наличността: червено при 0 и по-малко, жълто под границата.
Color? stockAlert(int qty, int min) => qty <= 0 ? _red : (qty <= min ? Palette.yellow : null);

/// Склад: „Свещи“ (кг) и „Ценни книжа“ (бр.). Само председателят и касиерът.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  StockSection _section = StockSection.candles;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    if (!s.canSeeCash(church)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Склад')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Складът се води от председателя и касиера.',
              style: TextStyle(fontSize: 17, color: p.textMuted)),
        ),
      );
    }
    final bal = s.stockOf(church);
    final toDecide = s.stockToDecide(church);
    final low = s.lowStock(church);
    final items = StockItem.values.where((i) => i.section == _section).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Склад')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const ChurchBanner(title: 'Склад на храма'),
              const SizedBox(height: 12),
              if (low.isNotEmpty) ...[
                LowStockCard(items: low),
                const SizedBox(height: 12),
              ],
              for (final mv in toDecide)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: StockReviewCard(move: mv)),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockBookScreen())),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Складова книга'),
              ),
              const SizedBox(height: 14),
              Row(children: [
                for (final sec in StockSection.values) ...[
                  Expanded(
                    child: _SectionTile(
                      section: sec,
                      selected: _section == sec,
                      alert: StockItem.values
                          .where((i) => i.section == sec)
                          .map((i) => stockAlert(bal[i]!, s.stockMin(church, i)))
                          .fold<Color?>(null, (a, c) => a == _red || c == _red ? _red : (a ?? c)),
                      onTap: () => setState(() => _section = sec),
                    ),
                  ),
                  if (sec != StockSection.values.last) const SizedBox(width: 10),
                ],
              ]),
              const SizedBox(height: 16),
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ItemCard(item: i, qty: bal[i]!, min: s.stockMin(church, i)),
                ),
              const SizedBox(height: 4),
              Text(
                  _section == StockSection.candles
                      ? 'Свещите се водят в цели килограми (пакети по 1 кг).'
                      : 'Проведено кръщене изписва 1 кръщелно, проведена венчавка – 2 венчални и 1 грамота. '
                          'При връщане или отмяна на събитието бланките се връщат.',
                  style: TextStyle(fontSize: 14, color: p.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final StockSection section;
  final bool selected;
  final Color? alert;
  final VoidCallback onTap;
  const _SectionTile({required this.section, required this.selected, required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = section == StockSection.candles ? const Color(0xFFC8862A) : p.primary;
    return Material(
      color: selected ? c : c.withValues(alpha: p.dark ? .18 : .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: alert ?? (selected ? c : c.withValues(alpha: .45)), width: alert != null ? 3 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(section == StockSection.candles ? Icons.local_fire_department_outlined : Icons.description_outlined,
                color: selected ? Colors.white : c),
            const SizedBox(height: 6),
            Text(section == StockSection.candles ? 'Свещи' : 'Ценни книжа',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: selected ? Colors.white : p.text)),
            Text(section == StockSection.candles ? 'в килограми' : 'на брой',
                style: TextStyle(fontSize: 13, color: selected ? Colors.white70 : p.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final StockItem item;
  final int qty;
  final int min;
  const _ItemCard({required this.item, required this.qty, required this.min});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final alert = stockAlert(qty, min);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alert == _red ? _red.withValues(alpha: p.dark ? .25 : .10) : p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: alert ?? p.border, width: alert != null ? 2.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => showStockHistory(context, item),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(
                    alert == _red
                        ? 'Свърши – заредете'
                        : alert != null
                            ? 'Под границата (${item.qty(min)}) – заредете'
                            : 'Предупреждение при ${item.qty(min)}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: alert != null ? FontWeight.w700 : FontWeight.w400,
                        color: alert == _red ? _red : p.textMuted)),
              ]),
            ),
            Text(item.qty(qty),
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: alert == _red ? _red : p.text,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => _move(context, s, church, load: true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Зареди'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => _move(context, s, church, load: false),
              icon: const Icon(Icons.remove_rounded),
              label: const Text('Изпиши'),
            ),
          ),
          IconButton(
            tooltip: 'Граница за предупреждение',
            onPressed: () => _setMin(context, s, church),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
        ]),
      ]),
    );
  }

  Future<void> _move(BuildContext context, AppState s, String church, {required bool load}) async {
    final qtyC = TextEditingController();
    // Изписване на свещи – по подразбиране „За храма“ (може да се смени).
    final noteC = TextEditingController(
        text: !load && item.section == StockSection.candles ? 'За храма' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${load ? 'Зареди' : 'Изпиши'}: ${item.label}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qtyC,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(hintText: 'Количество', suffixText: item.unit),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: noteC,
            maxLength: 200,
            decoration: InputDecoration(
                hintText: load ? 'Бележка (по желание), напр. доставка от митрополията' : 'Причина, напр. повредени'),
          ),
          const SizedBox(height: 4),
          const ChurchConfirmLine(),
          const SizedBox(height: 6),
          if (!load)
            Text(
                s.cashSettings(church).approvalsOff || s.cashierOf(church) == null
                    ? 'Изписването влиза веднага.'
                    : 'Изписването чака одобрение от другия от двамата.',
                style: TextStyle(fontSize: 13.5, color: Palette.of(ctx).textMuted)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(load ? 'Зареди' : 'Изпиши')),
        ],
      ),
    );
    final q = int.tryParse(qtyC.text.trim());
    final note = noteC.text.trim();
    qtyC.dispose();
    noteC.dispose();
    if (ok != true || !context.mounted) return;
    if (q == null || q <= 0) {
      showMessage(context, 'Въведете цяло число, по-голямо от нула.');
      return;
    }
    if (!load && note.isEmpty) {
      showMessage(context, 'Напишете причина за изписването.');
      return;
    }
    try {
      if (load) {
        await s.loadStock(church, item, q, note);
        if (context.mounted) showMessage(context, 'Заредено: ${item.qty(q)} ${item.label.toLowerCase()}.');
      } else {
        final mv = await s.writeOffStock(church, item, q, note);
        if (context.mounted) {
          showMessage(context, mv.isPending ? 'Изписването чака одобрение.' : 'Изписано: ${item.qty(q)}.');
        }
      }
    } on AppError catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  Future<void> _setMin(BuildContext context, AppState s, String church) async {
    final c = TextEditingController(text: '$min');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Предупреждение: ${item.label}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Предупреди, когато наличността падне до:'),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(suffixText: item.unit),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Запази')),
        ],
      ),
    );
    final v = int.tryParse(c.text.trim());
    c.dispose();
    if (ok != true || !context.mounted) return;
    if (v == null || v < 0) {
      showMessage(context, 'Въведете цяло число.');
      return;
    }
    try {
      await s.setStockMin(church, item, v);
      if (context.mounted) showMessage(context, 'Предупреждение при ${item.qty(v)}.');
    } on AppError catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }
}

/// История на вида: кой какво зареди, изписа, кога.
Future<void> showStockHistory(BuildContext context, StockItem item) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final p = Palette.of(ctx);
      final s = AppScope.of(ctx);
      final moves = s.stockMoves(s.currentChurchId!, item: item);
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * .7,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(item.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (moves.isEmpty) Text('Още няма движения.', style: TextStyle(fontSize: 16, color: p.textMuted)),
              for (final m in moves)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(m.qty > 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                        size: 20, color: m.qty > 0 ? Colors.green.shade700 : _red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            [
                              m.kindLabel,
                              if (m.kind.startsWith('event') && m.eventId != null && s.eventById(m.eventId!) != null)
                                s.eventById(m.eventId!)!.forWhom,
                              if (m.note.isNotEmpty) m.note,
                            ].where((x) => x.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                        Text(
                            [
                              s.priestName(m.createdBy),
                              _stamp.format(m.createdAt),
                              if (m.isPending) 'чака одобрение',
                              if (m.isReturned) 'върнато${m.returnReason.isEmpty ? '' : ': ${m.returnReason}'}',
                              if (m.isApproved && m.kind == 'writeoff' && m.autoReason == null && m.decidedBy != null)
                                'одобри ${s.priestName(m.decidedBy!)}',
                              if (m.autoReason == 'single') 'без второ одобрение',
                              if (m.autoReason == 'off') 'одобрението е изключено',
                            ].join(' · '),
                            style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                      ]),
                    ),
                    Text('${m.qty > 0 ? '+' : '−'}${item.qty(m.qty.abs())}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: m.isApproved ? (m.qty > 0 ? Colors.green.shade700 : _red) : p.textMuted,
                            decoration: m.isReturned ? TextDecoration.lineThrough : null)),
                  ]),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Жълта (или червена) карта: заредете склада.
class LowStockCard extends StatelessWidget {
  final List<StockItem> items;
  const LowStockCard({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final bal = s.stockOf(church);
    final out = items.any((i) => bal[i]! <= 0);
    return Material(
      color: (out ? _red : Palette.yellow).withValues(alpha: .18),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), side: BorderSide(color: out ? _red : Palette.yellow, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.inventory_2_outlined, color: out ? _red : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Склад: заредете', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                for (final i in items)
                  Text('${i.label}: остават ${i.qty(bal[i]!)}',
                      style: TextStyle(fontSize: 15, fontWeight: bal[i]! <= 0 ? FontWeight.w800 : FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Ръчно изписване, което чака моето одобрение.
class StockReviewCard extends StatefulWidget {
  final StockMove move;
  const StockReviewCard({super.key, required this.move});

  @override
  State<StockReviewCard> createState() => _StockReviewCardState();
}

class _StockReviewCardState extends State<StockReviewCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final m = widget.move;
    Future<void> go(bool approve) async {
      var reason = '';
      if (!approve) {
        final c = TextEditingController();
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Защо го връщате?'),
            content: TextField(controller: c, autofocus: true, maxLength: 200),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отказ')),
              TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Върни')),
            ],
          ),
        );
        c.dispose();
        if (r == null || r.isEmpty) return;
        reason = r;
      }
      if (!mounted) return;
      setState(() => _busy = true);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await s.decideStock(m, approve, reason: reason);
        messenger.showSnackBar(SnackBar(content: Text(approve ? 'Изписването е одобрено.' : 'Върнато.')));
      } on AppError catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      if (mounted) setState(() => _busy = false);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.yellow, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Склад: изписване чака одобрение',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textMuted)),
        const SizedBox(height: 6),
        Text('${m.item.label}: −${m.item.qty(m.qty.abs())}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text('${m.note} · ${s.priestName(m.createdBy)}', style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => go(false), child: const Text('Върни'))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => go(true),
              child: const Text('Одобри'),
            ),
          ),
        ]),
      ]),
    );
  }
}


/// Складова книга: всички зареждания и изписвания, най-новите отгоре.
class StockBookScreen extends StatefulWidget {
  const StockBookScreen({super.key});

  @override
  State<StockBookScreen> createState() => _StockBookScreenState();
}

class _StockBookScreenState extends State<StockBookScreen> {
  StockItem? _item; // null = всички
  String? _kind; // null = всички, 'in' = влизания, 'out' = излизания

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final moves = s
        .stockMoves(church, item: _item)
        .where((m) => _kind == null || (_kind == 'in' ? m.qty > 0 : m.qty < 0))
        .toList();
    final day = DateFormat('d MMMM y', 'bg');
    String? lastDay;
    return Scaffold(
      appBar: AppBar(title: const Text('Складова книга')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              DropdownButtonFormField<StockItem?>(
                initialValue: _item,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Вид'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Всички видове')),
                  for (final i in StockItem.values) DropdownMenuItem(value: i, child: Text(i.label)),
                ],
                onChanged: (v) => setState(() => _item = v),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String?>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: null, label: Text('Всички')),
                  ButtonSegment(value: 'in', label: Text('Влезли')),
                  ButtonSegment(value: 'out', label: Text('Излезли')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              if (_item != null) ...[
                const SizedBox(height: 12),
                Text('Наличност: ${_item!.qty(s.stockOf(church)[_item]!)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
              const SizedBox(height: 12),
              if (moves.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('Няма движения.', style: TextStyle(fontSize: 16, color: p.textMuted)),
                ),
              for (final m in moves) ...[
                if (lastDay != day.format(m.createdAt)) ...[
                  Builder(builder: (_) {
                    lastDay = day.format(m.createdAt);
                    return Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(lastDay!,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.textMuted)),
                    );
                  }),
                ],
                _BookRow(move: m),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  final StockMove move;
  const _BookRow({required this.move});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final m = move;
    final inbound = m.qty > 0;
    final ev = m.eventId == null ? null : s.eventById(m.eventId!);
    final status = [
      if (m.isPending) 'чака одобрение',
      if (m.isReturned) 'върнато${m.returnReason.isEmpty ? '' : ': ${m.returnReason}'}',
      if (m.isApproved && m.kind == 'writeoff' && m.autoReason == null && m.decidedBy != null)
        'одобри ${s.priestName(m.decidedBy!)}',
      if (m.autoReason == 'single') 'без второ одобрение',
      if (m.autoReason == 'off') 'одобрението е изключено',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: inbound ? Colors.green.shade600 : _red, width: 5),
            top: BorderSide(color: p.border),
            right: BorderSide(color: p.border),
            bottom: BorderSide(color: p.border),
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m.kindLabel} · ${m.item.label}',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              Text(
                  [
                    if (ev != null) '${ev.kind.label}${ev.forWhom.isEmpty ? '' : ' – ${ev.forWhom}'}',
                    if (m.note.isNotEmpty) m.note,
                    s.priestName(m.createdBy),
                    DateFormat('HH:mm').format(m.createdAt),
                    ...status,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13.5, color: p.textMuted)),
            ]),
          ),
          const SizedBox(width: 10),
          Text('${inbound ? '+' : '−'}${m.item.qty(m.qty.abs())}',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: m.isApproved ? (inbound ? Colors.green.shade700 : _red) : p.textMuted,
                  decoration: m.isReturned ? TextDecoration.lineThrough : null)),
        ]),
      ),
    );
  }
}
