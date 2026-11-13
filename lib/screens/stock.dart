import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/church_banner.dart';
import 'cash.dart' show fmtEur, parseAmount;

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
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const StockAuditsScreen())),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text('Ревизии${s.stockAudits(church).isEmpty ? '' : ' (${s.stockAudits(church).length})'}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const StockOrderScreen())),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Поръчка'),
                  ),
                ),
              ]),
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
                if (s.stockPrice(church, item) case final pr?)
                  Text('Покупна: ${fmtEur(pr)} за ${item.section == StockSection.candles ? 'кг' : 'брой'}',
                      style: TextStyle(fontSize: 13.5, color: p.textMuted)),
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
            tooltip: 'Покупна цена',
            onPressed: () => _setPrice(context, s, church),
            icon: const Icon(Icons.sell_outlined),
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
    final known = s.stockPrice(church, item);
    final priceC = TextEditingController(text: known == null ? '' : known.toStringAsFixed(2).replaceAll('.', ','));
    var toCash = true;
    final perUnit = item.section == StockSection.candles ? 'кг' : 'брой';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final q0 = int.tryParse(qtyC.text.trim()) ?? 0;
        final pr0 = parseAmount(priceC.text);
        final total = pr0 == null ? null : q0 * pr0;
        return AlertDialog(
        title: Text('${load ? 'Зареди' : 'Изпиши'}: ${item.label}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qtyC,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(hintText: 'Количество', suffixText: item.unit),
            onChanged: (_) => set(() {}),
          ),
          if (load) ...[
            const SizedBox(height: 10),
            TextField(
              controller: priceC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                  labelText: 'Покупна цена за $perUnit (без ДДС)', suffixText: '€', hintText: 'по желание'),
              onChanged: (_) => set(() {}),
            ),
            if (total != null && q0 > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Общо: ${fmtEur(total)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            if (total != null && q0 > 0)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: toCash,
                onChanged: (v) => set(() => toCash = v ?? false),
                title: Text('Запиши и разход в касата (${fmtEur(total)})', style: const TextStyle(fontSize: 15)),
                subtitle: Text(item.section == StockSection.candles ? 'Свещи (доставка)' : 'Ценни книжа (доставка)'),
              ),
          ],
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
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(load ? 'Зареди' : 'Изпиши')),
        ],
      );
      }),
    );
    final q = int.tryParse(qtyC.text.trim());
    final note = noteC.text.trim();
    final price = priceC.text.trim().isEmpty ? null : parseAmount(priceC.text);
    qtyC.dispose();
    noteC.dispose();
    priceC.dispose();
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
        if (price != null && price < 0) {
          showMessage(context, 'Цената не може да е отрицателна.');
          return;
        }
        await s.loadStock(church, item, q, note, price: price);
        var msg = 'Заредено: ${item.qty(q)} ${item.label.toLowerCase()}.';
        if (price != null && price > 0 && toCash) {
          final e = await s.addCash(
            book: CashBook.expense,
            amount: (q * price * 100).roundToDouble() / 100,
            category: item.section == StockSection.candles ? 'Свещи (доставка)' : 'Ценни книжа (доставка)',
            note: '${item.label}: ${item.qty(q)} × ${fmtEur(price)}${note.isEmpty ? '' : ' · $note'}',
          );
          msg += e.isPending ? ' Разходът в касата чака одобрение.' : ' Разходът е записан в касата.';
        }
        if (context.mounted) showMessage(context, msg);
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

  Future<void> _setPrice(BuildContext context, AppState s, String church) async {
    final cur = s.stockPrice(church, item);
    final c = TextEditingController(text: cur == null ? '' : cur.toStringAsFixed(2).replaceAll('.', ','));
    final perUnit = item.section == StockSection.candles ? 'кг' : 'брой';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Покупна цена: ${item.label}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Цена за $perUnit, без ДДС. Излиза в поръчката и при зареждане.'),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(suffixText: '€', hintText: 'празно = без цена'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Запази')),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    if (ok != true || !context.mounted) return;
    final v = text.isEmpty ? null : parseAmount(text);
    if (text.isNotEmpty && (v == null || v < 0)) {
      showMessage(context, 'Въведете цена, напр. 12,50.');
      return;
    }
    try {
      await s.setStockPrice(church, item, v);
      if (context.mounted) showMessage(context, v == null ? 'Цената е премахната.' : 'Цената е запазена.');
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
                              if (m.unitPrice != null) 'по ${fmtEur(m.unitPrice!)}',
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
  StockSection? _section; // null = и двата раздела
  StockItem? _item; // null = всички видове
  String? _kind; // null = всички, 'in' = влизания, 'out' = излизания
  bool _audits = false; // раздел „Ревизии“
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final moves = s
        .stockMoves(church, item: _item)
        .where((m) => _section == null || m.item.section == _section)
        .where((m) => _kind == null || (_kind == 'in' ? m.qty > 0 : m.qty < 0))
        .where((m) {
          final q = _q.trim().toLowerCase();
          if (q.isEmpty) return true;
          final ev = m.eventId == null ? null : s.eventById(m.eventId!);
          return [m.note, m.kindLabel, m.item.label, s.priestName(m.createdBy), ev?.forWhom ?? '']
              .any((x) => x.toLowerCase().contains(q));
        })
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
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Движения'), icon: Icon(Icons.swap_vert_rounded)),
                  ButtonSegment(value: true, label: Text('Ревизии'), icon: Icon(Icons.fact_check_outlined)),
                ],
                selected: {_audits},
                onSelectionChanged: (v) => setState(() => _audits = v.first),
              ),
              const SizedBox(height: 14),
              if (_audits) ...auditArchive(context, s, church) else ...[
              TextField(
                decoration: const InputDecoration(
                    hintText: 'Търсене: причина, събитие, име', prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 10),
              SegmentedButton<StockSection?>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: null, label: Text('Всичко')),
                  ButtonSegment(value: StockSection.candles, label: Text('Свещи')),
                  ButtonSegment(value: StockSection.papers, label: Text('Ценни книжа')),
                ],
                selected: {_section},
                onSelectionChanged: (v) => setState(() {
                  _section = v.first;
                  if (_item != null && _section != null && _item!.section != _section) _item = null;
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<StockItem?>(
                key: ValueKey(_section),
                initialValue: _item,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Вид'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Всички видове')),
                  for (final i in StockItem.values.where((i) => _section == null || i.section == _section))
                    DropdownMenuItem(value: i, child: Text(i.label)),
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
            ],
          ),
        ),
      ),
    );
  }

}

/// Архив на ревизиите – само за сведение, не влияе на склада и касата.
/// Председателят може да изтрие ревизия.
List<Widget> auditArchive(BuildContext context, AppState s, String church) {
  final p = Palette.of(context);
  final batches = s.stockAudits(church);
  final manager = s.isManagerOf(church);
  String summary(List<StockAudit> b) {
    final less = b.where((a) => a.diff < 0).toList();
    final more = b.where((a) => a.diff > 0).toList();
    if (less.isEmpty && more.isEmpty) return 'Всичко съвпада с книгата (${b.length} вида).';
    return [
      if (less.isNotEmpty) 'Липсват: ${less.map((a) => '${a.item.label} ${a.item.qty(-a.diff)}').join(', ')}',
      if (more.isNotEmpty) 'Излишък: ${more.map((a) => '${a.item.label} ${a.item.qty(a.diff)}').join(', ')}',
    ].join('. ');
  }

  return [
    Text('Ревизията е само за сведение: пази преброеното и разликата с книгата. '
        'Не променя склада и не влиза в касата.',
        style: TextStyle(fontSize: 14, color: p.textMuted)),
    const SizedBox(height: 10),
    if (batches.isEmpty) Text('Още няма ревизии.', style: TextStyle(fontSize: 16, color: p.textMuted)),
    for (final b in batches)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('Ревизия · ${_stamp.format(b.first.createdAt)}',
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              ),
              if (manager)
                IconButton(
                  tooltip: 'Изтрий ревизията',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    final ok = await confirm(context, 'Изтриване на ревизията?',
                        'Ревизия от ${_stamp.format(b.first.createdAt)}. Складът и касата не се променят.', 'Изтрий');
                    if (!ok || !context.mounted) return;
                    try {
                      await s.deleteAudit(church, b.first.batch);
                      if (context.mounted) showMessage(context, 'Ревизията е изтрита.');
                    } on AppError catch (e) {
                      if (context.mounted) showMessage(context, e.message);
                    }
                  },
                ),
            ]),
            Text('Извърши: ${s.priestName(b.first.createdBy)}', style: const TextStyle(fontSize: 15)),
            if (b.first.note.isNotEmpty)
              Text(b.first.note, style: TextStyle(fontSize: 14, color: p.textMuted)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (b.every((a) => a.diff == 0) ? Colors.green : Colors.orange).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Резултат: ${summary(b)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            for (final a in b) _AuditLine(audit: a),
          ]),
        ),
      ),
  ];
}

/// Раздел „Ревизии“ – архив.
class StockAuditsScreen extends StatelessWidget {
  const StockAuditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    return Scaffold(
      appBar: AppBar(title: const Text('Ревизии')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockAuditScreen())),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Нова ревизия'),
              ),
              const SizedBox(height: 16),
              ...auditArchive(context, s, church),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditLine extends StatelessWidget {
  final StockAudit audit;
  const _AuditLine({required this.audit});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final a = audit;
    final d = a.diff;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(a.item.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
        Text('книга ${a.bookQty} · преброено ${a.counted}', style: TextStyle(fontSize: 13.5, color: p.textMuted)),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(
              d == 0 ? 'точно' : '${d > 0 ? '+' : '−'}${a.item.qty(d.abs())}',
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: d == 0 ? Colors.green.shade700 : (d < 0 ? _red : Colors.orange.shade700))),
        ),
      ]),
    );
  }
}

/// Ревизия: преброявате, Кайрос показва разликата. Само проверка.
class StockAuditScreen extends StatefulWidget {
  const StockAuditScreen({super.key});

  @override
  State<StockAuditScreen> createState() => _StockAuditScreenState();
}

class _StockAuditScreenState extends State<StockAuditScreen> {
  final _c = {for (final i in StockItem.values) i: TextEditingController()};
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final bal = s.stockOf(church);
    Widget line(StockItem i) {
      final n = int.tryParse(_c[i]!.text.trim());
      final d = n == null ? null : n - bal[i]!;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('по книга ${i.qty(bal[i]!)}', style: TextStyle(fontSize: 13.5, color: p.textMuted)),
              if (d != null)
                Text(d == 0 ? 'съвпада' : (d < 0 ? 'липсват ${i.qty(-d)}' : 'в повече ${i.qty(d)}'),
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: d == 0 ? Colors.green.shade700 : (d < 0 ? _red : Colors.orange.shade700))),
            ]),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _c[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              decoration: InputDecoration(hintText: 'преброено', suffixText: i.unit),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ревизия')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
                'Преброете и въведете колко има реално. Попълнете само видовете, които сте броили. '
                'Ревизията е проверка – не променя наличността и не влиза в складовата книга.',
                style: TextStyle(fontSize: 14.5, color: p.textMuted, height: 1.4)),
            const SizedBox(height: 14),
            const Text('Свещи', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final i in StockItem.values.where((i) => i.section == StockSection.candles)) line(i),
            const SizedBox(height: 8),
            const Text('Ценни книжа', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final i in StockItem.values.where((i) => i.section == StockSection.papers)) line(i),
            TextField(controller: _note, decoration: const InputDecoration(hintText: 'Бележка (по желание)')),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _saving
                  ? null
                  : () async {
                      final counted = <StockItem, int>{
                        for (final e in _c.entries)
                          if (int.tryParse(e.value.text.trim()) != null) e.key: int.parse(e.value.text.trim()),
                      };
                      if (counted.isEmpty) {
                        showMessage(context, 'Въведете поне едно преброено количество.');
                        return;
                      }
                      if (counted.values.any((v) => v < 0)) {
                        showMessage(context, 'Количествата не могат да са отрицателни.');
                        return;
                      }
                      setState(() => _saving = true);
                      final nav = Navigator.of(context);
                      final m = ScaffoldMessenger.of(context);
                      try {
                        await s.saveAudit(church, counted, _note.text.trim());
                        nav.pop();
                        m.showSnackBar(const SnackBar(content: Text('Ревизията е записана в раздел „Ревизии“.')));
                      } on AppError catch (e) {
                        if (!mounted) return;
                        setState(() => _saving = false);
                        m.showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
              child: const Text('Запиши ревизията'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Поръчка: всички видове с наличностите; въвеждате колко да се поръча
/// и пращате списъка (Viber, WhatsApp или копиране).
class StockOrderScreen extends StatefulWidget {
  const StockOrderScreen({super.key});

  @override
  State<StockOrderScreen> createState() => _StockOrderScreenState();
}

class _StockOrderScreenState extends State<StockOrderScreen> {
  final _c = {for (final i in StockItem.values) i: TextEditingController()};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(AppState s) {
    final church = s.currentChurch!;
    var total = 0.0;
    var anyPrice = false;
    final lines = <String>[];
    for (final e in _c.entries) {
      final n = int.tryParse(e.value.text.trim()) ?? 0;
      if (n <= 0) continue;
      final pr = s.stockPrice(church.id, e.key);
      if (pr == null) {
        lines.add('• ${e.key.label}: ${e.key.qty(n)}');
      } else {
        anyPrice = true;
        total += n * pr;
        lines.add('• ${e.key.label}: ${e.key.qty(n)} × ${fmtEur(pr)} = ${fmtEur(n * pr)}');
      }
    }
    return 'Поръчка за склада – ${church.name}, ${church.settlement}\n'
        '${DateFormat('d MMMM y', 'bg').format(DateTime.now())}\n\n${lines.join('\n')}'
        '${anyPrice ? '\n\nОбщо: ${fmtEur(total)}' : ''}\n\n– ${s.currentUser?.fullName ?? ''}';
  }

  Future<void> _send(BuildContext context, AppState s, String how) async {
    if (!_c.values.any((c) => (int.tryParse(c.text.trim()) ?? 0) > 0)) {
      showMessage(context, 'Въведете какво да се поръча.');
      return;
    }
    final text = _text(s);
    if (how == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) showMessage(context, 'Списъкът е копиран.');
      return;
    }
    final uri = how == 'viber'
        ? Uri.parse('viber://forward?text=${Uri.encodeComponent(text)}')
        : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        showMessage(context, '${how == 'viber' ? 'Viber' : 'WhatsApp'} не се отвори – списъкът е копиран.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final bal = s.stockOf(church);
    final items = [...StockItem.values]
      ..sort((a, b) {
        final la = bal[a]! <= s.stockMin(church, a) ? 0 : 1;
        final lb = bal[b]! <= s.stockMin(church, b) ? 0 : 1;
        return la != lb ? la - lb : a.index - b.index;
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Поръчка')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('Видовете под границата са най-отгоре. Попълнете колко да се поръча и изпратете списъка.',
                style: TextStyle(fontSize: 14.5, color: p.textMuted, height: 1.4)),
            const SizedBox(height: 14),
            for (final i in items)
              Builder(builder: (context) {
                final alert = stockAlert(bal[i]!, s.stockMin(church, i));
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: alert ?? p.border, width: alert != null ? 2 : 1),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text('налично ${i.qty(bal[i]!)}${alert != null ? ' · под границата' : ''}'
                            '${s.stockPrice(church, i) == null ? '' : ' · ${fmtEur(s.stockPrice(church, i)!)}/${i.section == StockSection.candles ? 'кг' : 'бр.'}'}',
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: alert != null ? FontWeight.w700 : FontWeight.w400,
                                color: alert == _red ? _red : p.textMuted)),
                      ]),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _c[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(hintText: '0', suffixText: i.unit),
                      ),
                    ),
                  ]),
                );
              }),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: const Color(0xFF7360F2),
                foregroundColor: Colors.white,
              ),
              onPressed: () => _send(context, s, 'viber'),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Изпрати по Viber'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: const Color(0xFF1FA855),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _send(context, s, 'whatsapp'),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _send(context, s, 'copy'),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Копирай'),
                ),
              ),
            ]),
          ],
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
      if (m.unitPrice != null) 'по ${fmtEur(m.unitPrice!)}',
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
