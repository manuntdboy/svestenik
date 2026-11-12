import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

final _eur = NumberFormat.currency(locale: 'bg', symbol: '€', decimalDigits: 2);
final _day = DateFormat('d MMMM y', 'bg');
final _dayShort = DateFormat('d MMM', 'bg');
final _stamp = DateFormat('d MMMM, HH:mm', 'bg');

String fmtEur(double v) => _eur.format(v);

const _green = Color(0xFF2E7D4F);
const _red = Color(0xFFB23A3A);
const _negativeBg = Color(0xFF8E2323);

/// Цвят на книгата: приходна – зелено, разходна – червено, банка – синьо, чакащи – жълто.
Color bookColor(BuildContext context, CashBook? b) => switch (b) {
      CashBook.income || CashBook.opening => _green,
      CashBook.expense => _red,
      CashBook.transfer => Palette.of(context).primary,
      null => Palette.yellow,
    };

/// Каса: Приходна и Разходна книга (и банка, ако е включена).
/// Председателят и касиерът виждат всичко; свещеникът – само своите приходи.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  CashBook? _tab = CashBook.income; // null = чакащи и върнати

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final holder = s.canSeeCash(church);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каса'),
        actions: [
          if (s.isManagerOf(church))
            IconButton(
              tooltip: 'Настройки на касата',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _settings(context),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CashEntryForm(
                    holder: holder,
                    startWith: holder && (_tab == CashBook.expense || _tab == CashBook.transfer)
                        ? _tab!
                        : CashBook.income))),
        icon: const Icon(Icons.add_rounded),
        label: Text(holder ? 'Нов запис' : 'Предай приход'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: holder ? _holderView(context, s, church) : _priestView(context, s, church),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- касиер / председател
  Widget _holderView(BuildContext context, AppState s, String church) {
    final p = Palette.of(context);
    final st = s.cashSettings(church);
    final all = s.cashEntries(church);
    final (cash, bank) = cashBalance(all);
    final toDecide = s.cashToDecide(church);
    final waiting = all.where((e) => e.isPending && !s.canDecideCash(e)).toList();
    final returned = all.where((e) => e.isReturned).toList();
    final tabs = [CashBook.income, CashBook.expense, if (st.hasBank) CashBook.transfer, null];
    if (!tabs.contains(_tab)) _tab = CashBook.income;
    final shown = _tab == null
        ? [...waiting, ...returned]
        : all.where((e) => e.isApproved && e.book == _tab).toList();
    final pendingCount = all.where((e) => e.isPending).length;
    final monthIn = _sumMonth(all, CashBook.income);
    final monthOut = _sumMonth(all, CashBook.expense);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        // Баланс
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cash + bank < 0 ? _negativeBg : p.heroBg,
            borderRadius: BorderRadius.circular(24),
            border: pendingCount > 0 ? Border.all(color: Palette.yellow, width: 4) : null,
            boxShadow: pendingCount > 0
                ? [BoxShadow(color: Palette.yellow.withValues(alpha: .45), blurRadius: 18, spreadRadius: 1)]
                : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (pendingCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => setState(() => _tab = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Palette.yellow, borderRadius: BorderRadius.circular(12)),
                    child: Text('$pendingCount ${pendingCount == 1 ? 'запис чака' : 'записа чакат'} одобрение',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.onYellow)),
                  ),
                ),
              ),
            Text(cash + bank < 0 ? 'Касата е на минус' : 'В касата на храма',
                style: TextStyle(
                    fontSize: 15,
                    color: cash + bank < 0 ? Colors.white : p.heroMuted,
                    fontWeight: cash + bank < 0 ? FontWeight.w800 : FontWeight.w400)),
            const SizedBox(height: 4),
            Text(fmtEur(cash + bank),
                style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            if (st.hasBank) ...[
              const SizedBox(height: 6),
              Text('Брой ${fmtEur(cash)}  ·  Банка ${fmtEur(bank)}',
                  style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _heroStat(p, 'Приходи този месец', monthIn, Colors.greenAccent.shade100)),
              const SizedBox(width: 12),
              Expanded(child: _heroStat(p, 'Разходи този месец', monthOut, Palette.yellow)),
            ]),
          ]),
        ),
        for (final o in all.where((e) => e.book == CashBook.opening && e.isApproved))
          Padding(padding: const EdgeInsets.only(top: 10), child: CashRow(entry: o)),
        if (s.openingAccountsLeft(church).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CashEntryForm(holder: true, startWith: CashBook.opening))),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Въведи началното салдо'),
            ),
          ),
        const SizedBox(height: 10),
        Text(
            s.cashierOf(church) == null
                ? 'Няма назначен касиер: председателят води касата сам и разходите влизат направо.'
                : 'Разход до ${fmtEur(st.limitEur)} на ден влиза направо; над това чака другия от двамата.',
            style: TextStyle(fontSize: 14, color: p.textMuted)),
        if (toDecide.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Чакат вашето решение', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final e in toDecide)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: CashReviewCard(entry: e)),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final perRow = tabs.length <= 3 ? tabs.length : 2;
          final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final t in tabs)
              SizedBox(
                width: w,
                child: _BookTile(
                  book: t,
                  selected: _tab == t,
                  count: t == null
                      ? waiting.length + returned.length
                      : all.where((e) => e.isApproved && e.book == t).length,
                  onTap: () => setState(() => _tab = t),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(left: 12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: bookColor(context, _tab), width: 5))),
          child: Text(_tab == null ? 'Чакащи и върнати' : _tab!.bookName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
                _tab == null ? 'Няма чакащи или върнати записи.' : 'Още няма записи в тази книга.',
                style: TextStyle(fontSize: 16, color: p.textMuted)),
          ),
        for (final e in shown) CashRow(entry: e),
      ],
    );
  }

  Widget _heroStat(Palette p, String label, double v, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: p.heroMuted)),
          Text(fmtEur(v), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
        ],
      );

  double _sumMonth(List<CashEntry> all, CashBook b) {
    final now = DateTime.now();
    return all
        .where((e) => e.isApproved && e.book == b && e.date.year == now.year && e.date.month == now.month)
        .fold(0.0, (a, e) => a + e.amount);
  }

  // ---------------------------------------------------------------- свещеник
  Widget _priestView(BuildContext context, AppState s, String church) {
    final p = Palette.of(context);
    final mine = s.myCashEntries(church);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        SurfaceCard(
          child: Text(
              'Касата на храма водят председателят и касиерът. Тук предавате приход '
              '(кръщене, венчавка, свещи…) – той влиза в Приходната книга, щом касиерът го приеме.',
              style: TextStyle(fontSize: 16, color: p.textMuted, height: 1.4)),
        ),
        const SizedBox(height: 16),
        const Text('Моите предадени приходи', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (mine.isEmpty)
          Text('Още няма предадени приходи.', style: TextStyle(fontSize: 16, color: p.textMuted)),
        for (final e in mine) CashRow(entry: e),
      ],
    );
  }

  Future<void> _settings(BuildContext context) async {
    final s = AppScope.read(context);
    final church = s.currentChurchId!;
    final st = s.cashSettings(church);
    var bank = st.hasBank;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Настройки на касата'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Разход до 100 € на ден влиза без одобрение. Лимитът е еднакъв за всички храмове и не се променя.',
                style: TextStyle(fontSize: 14, color: Palette.of(ctx).textMuted)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: bank,
              onChanged: (v) => set(() => bank = v),
              title: const Text('Храмът има банкова сметка'),
              subtitle: const Text('Брой и банка се водят отделно; внасяне и теглене минават през двамата.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Запази')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await s.saveCashSettings(church, 100, bank);
      if (context.mounted) showMessage(context, 'Настройките на касата са запазени.');
    } on AppError catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }
}

class _BookTile extends StatelessWidget {
  final CashBook? book;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  const _BookTile({required this.book, required this.selected, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = bookColor(context, book);
    final onC = book == null ? Palette.onYellow : Colors.white;
    final (icon, label) = switch (book) {
      CashBook.income => (Icons.south_west_rounded, 'Приходна'),
      CashBook.expense => (Icons.north_east_rounded, 'Разходна'),
      CashBook.transfer => (Icons.account_balance_outlined, 'Банка'),
      _ => (Icons.hourglass_top_rounded, 'Чакащи'),
    };
    final alert = book == null && count > 0;
    return Material(
      color: selected ? c : c.withValues(alpha: p.dark ? .18 : .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: alert || selected ? c : c.withValues(alpha: .45), width: alert ? 3 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 24, color: selected ? onC : (book == null ? p.text : c)),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: selected ? onC : p.text)),
            Text(book == null ? (count == 0 ? 'няма' : '$count чакат') : '$count записа',
                style: TextStyle(fontSize: 13, color: selected ? onC.withValues(alpha: .85) : p.textMuted)),
          ]),
        ),
      ),
    );
  }
}

/// „12,50“ или „12.50“ → 12.5; празно/грешно → null.
double? parseAmount(String t) {
  final v = double.tryParse(t.trim().replaceAll(' ', '').replaceAll(',', '.'));
  return v == null ? null : (v * 100).roundToDouble() / 100;
}

/// Ред в книгата.
class CashRow extends StatelessWidget {
  final CashEntry entry;
  const CashRow({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = entry;
    final sign = e.book == CashBook.expense ? -1 : 1;
    final shownAmount = e.book == CashBook.transfer ? e.amount : e.amount * sign;
    final status = e.isPending
        ? 'чака одобрение'
        : e.isReturned
            ? 'върнат'
            : e.reversedBy != null
                ? 'сторниран'
                : e.autoReason == 'single'
                    ? 'без второ одобрение'
                    : e.autoReason == 'under_limit'
                        ? 'под лимита'
                        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18), side: BorderSide(color: p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showCashEntry(context, e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              SizedBox(
                width: 54,
                child: Text(e.ref.isEmpty ? '—' : e.ref,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.primary)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e.isReversal ? 'Сторно · ' : ''}${e.book == CashBook.transfer ? e.kindLabel : e.categoryLabel}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(
                      [
                        _dayShort.format(e.date),
                        s.priestName(e.createdBy),
                        if (e.account == 'bank' && e.book != CashBook.transfer) 'банка',
                        if (status.isNotEmpty) status,
                      ].join(' · '),
                      style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                ]),
              ),
              Text(fmtEur(shownAmount),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: e.isReturned || e.reversedBy != null
                        ? p.textMuted
                        : shownAmount < 0
                            ? Theme.of(context).colorScheme.error
                            : Colors.green.shade700,
                    decoration: e.isReturned || e.reversedBy != null ? TextDecoration.lineThrough : null,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Подробности за запис; оттук – сторно.
Future<void> showCashEntry(BuildContext context, CashEntry e) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final p = Palette.of(ctx);
      final s = AppScope.of(ctx);
      Widget row(String a, String b) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: Text(a, style: TextStyle(fontSize: 15, color: p.textMuted))),
              Expanded(child: Text(b, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            ]),
          );
      final canReverse = s.canSeeCash(e.churchId) &&
          e.isApproved &&
          !e.isReversal &&
          e.reversedBy == null &&
          e.book != CashBook.opening;
      final ev = e.eventId == null ? null : s.eventById(e.eventId!);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${e.kindLabel}${e.ref.isEmpty ? '' : ' · ${e.ref}'}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(fmtEur(e.amount.abs()), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (e.book != CashBook.transfer) row('Вид', e.categoryLabel),
            row('Дата', _day.format(e.date)),
            if (e.book != CashBook.transfer) row('Сметка', e.account == 'bank' ? 'Банка' : 'Брой'),
            if (e.note.isNotEmpty) row('Бележка', e.note),
            if (ev != null) row('Събитие', '${ev.kind.label} · ${fmtDayLong(ev.startsAt)}'),
            row('Въведе', '${s.priestName(e.createdBy)} · ${_stamp.format(e.createdAt)}'),
            row(
                'Състояние',
                e.isPending
                    ? 'Чака одобрение'
                    : e.isReturned
                        ? 'Върнат${e.returnReason.isEmpty ? '' : ': ${e.returnReason}'}'
                        : e.autoReason == 'holder'
                            ? 'В книгата (въведен от касата)'
                            : e.autoReason == 'single'
                                ? 'В книгата, без второ одобрение'
                                : e.autoReason == 'under_limit'
                                    ? 'В книгата, под лимита'
                                    : 'Одобрен от ${s.priestName(e.decidedBy ?? '')}'),
            if (e.reversedBy != null) row('Сторно', 'Записът е сторниран'),
            if (canReverse) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Сторнирай (грешен запис)'),
                onPressed: () async {
                  final reason = await _askReason(ctx, 'Причина за сторното', 'например грешна сума');
                  if (reason == null || !ctx.mounted) return;
                  try {
                    final r = await s.reverseCash(e, reason);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      showMessage(context,
                          r.isPending ? 'Сторното чака одобрение от другия.' : 'Сторното е записано.');
                    }
                  } on AppError catch (err) {
                    if (ctx.mounted) showMessage(ctx, err.message);
                  }
                },
              ),
              const SizedBox(height: 6),
              Text('Записите не се изтриват. Сторното е обратен запис със същата сума и причина.',
                  style: TextStyle(fontSize: 13.5, color: p.textMuted)),
            ],
          ]),
        ),
      );
    },
  );
}

Future<String?> _askReason(BuildContext context, String title, String hint) async {
  final ctrl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 200,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отказ')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Готово')),
      ],
    ),
  );
  ctrl.dispose();
  return (r == null || r.isEmpty) ? null : r;
}

/// Карта за чакащ запис: „Приеми“ / „Одобри“ или „Върни“.
class CashReviewCard extends StatefulWidget {
  final CashEntry entry;
  const CashReviewCard({super.key, required this.entry});

  @override
  State<CashReviewCard> createState() => _CashReviewCardState();
}

class _CashReviewCardState extends State<CashReviewCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final e = widget.entry;
    final isIncome = e.book == CashBook.income && !e.isReversal;
    Future<void> go(bool approve) async {
      String reason = '';
      if (!approve) {
        final r = await _askReason(context, 'Защо го връщате?', 'например грешна сума, двойно въведен');
        if (r == null) return;
        reason = r;
      }
      if (!mounted) return;
      setState(() => _busy = true);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await s.decideCash(e, approve, reason: reason);
        messenger.showSnackBar(SnackBar(
            content: Text(approve ? 'Записано в ${e.book.bookName}.' : 'Върнато на ${s.priestName(e.createdBy)}.')));
      } on AppError catch (err) {
        messenger.showSnackBar(SnackBar(content: Text(err.message)));
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
        Row(children: [
          Icon(Icons.payments_outlined, color: p.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Каса: ${e.kindLabel.toLowerCase()} чака ${isIncome ? 'приемане' : 'одобрение'}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textMuted)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(fmtEur(e.amount.abs()), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        Text(
            [
              if (e.book != CashBook.transfer) e.categoryLabel,
              _dayShort.format(e.date),
              s.priestName(e.createdBy),
            ].join(' · '),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (e.note.isNotEmpty) Text(e.note, style: TextStyle(fontSize: 15, color: p.textMuted)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => go(false), child: const Text('Върни'))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => go(true),
              child: Text(isIncome ? 'Приеми' : 'Одобри'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Нов запис: приход, разход, внасяне/теглене от банката.
class CashEntryForm extends StatefulWidget {
  final bool holder;
  final ChurchEvent? event; // приход от проведено събитие
  final CashBook startWith;
  const CashEntryForm({super.key, required this.holder, this.event, this.startWith = CashBook.income});

  @override
  State<CashEntryForm> createState() => _CashEntryFormState();
}

class _CashEntryFormState extends State<CashEntryForm> {
  late CashBook _book = widget.startWith;
  late String _account = widget.startWith == CashBook.opening
      ? (AppScope.read(context).openingAccountsLeft(AppScope.read(context).currentChurchId!).firstOrNull ?? 'cash')
      : 'cash';
  String _direction = 'to_bank';
  late String _category = widget.event != null
      ? incomeCategoryFor(widget.event!.kind)
      : widget.startWith == CashBook.expense
          ? expenseCategories.first
          : incomeCategories.first;
  final _amount = TextEditingController();
  final _other = TextEditingController();
  late final _note = TextEditingController(
      text: widget.event == null
          ? ''
          : [widget.event!.kind.label, if (widget.event!.forWhom.isNotEmpty) widget.event!.forWhom].join(' · '));
  late DateTime _date = widget.event?.startsAt ?? DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _other.dispose();
    _note.dispose();
    super.dispose();
  }

  List<String> get _cats => _book == CashBook.expense ? expenseCategories : incomeCategories;

  Future<void> _save() async {
    final s = AppScope.read(context);
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      showMessage(context, 'Въведете сума, например 50 или 12,50.');
      return;
    }
    if (_book != CashBook.transfer && _category == 'Друго' && _other.text.trim().isEmpty) {
      showMessage(context, 'Напишете какъв е видът („Друго“).');
      return;
    }
    if (_book == CashBook.opening) {
      final ok = await confirm(
          context,
          'Началното салдо е еднократно',
          '${fmtEur(amount)} ${_account == 'bank' ? 'в банката' : 'в брой'}. След като влезе, не може да се променя.',
          'Запиши');
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final e = await s.addCash(
        book: _book,
        amount: amount,
        category: _book == CashBook.transfer
            ? (_direction == 'to_bank' ? 'Внасяне' : 'Теглене')
            : _book == CashBook.opening
                ? 'Начално салдо'
                : _category,
        categoryOther: _category == 'Друго' && _book != CashBook.opening ? _other.text.trim() : '',
        note: _note.text.trim(),
        account: _account,
        direction: _book == CashBook.transfer ? _direction : null,
        eventId: widget.event?.id,
        date: _date,
      );
      nav.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(e.isPending
              ? (e.book == CashBook.income && !widget.holder
                  ? 'Предадено. Касиерът ще го приеме.'
                  : 'Записът чака одобрение от другия.')
              : 'Записано: ${e.ref}.')));
    } on AppError catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, err.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final st = s.cashSettings(s.currentChurchId!);
    final fieldStyle = const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    final books = widget.holder
        ? [
            CashBook.income,
            CashBook.expense,
            if (st.hasBank) CashBook.transfer,
            if (widget.event == null && s.openingAccountsLeft(s.currentChurchId!).isNotEmpty) CashBook.opening,
          ]
        : [CashBook.income];
    Widget section(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FieldLabel(label), child]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(widget.holder ? 'Нов запис в касата' : 'Предай приход')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (books.length > 1)
              section(
                'Какво',
                SegmentedButton<CashBook>(
                  showSelectedIcon: false,
                  segments: [
                    for (final b in books)
                      ButtonSegment(
                          value: b,
                          label: Text(b == CashBook.transfer
                              ? 'Банка'
                              : b == CashBook.opening
                                  ? 'Начало'
                                  : b.label)),
                  ],
                  selected: {_book},
                  onSelectionChanged: (v) => setState(() {
                    _book = v.first;
                    _category = _cats.first;
                    if (_book == CashBook.opening) {
                      final left = s.openingAccountsLeft(s.currentChurchId!);
                      if (left.isNotEmpty && !left.contains(_account)) _account = left.first;
                    }
                  }),
                ),
              ),
            if (_book == CashBook.transfer)
              section(
                'Посока',
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'to_bank', label: Text('Внасяне в банката')),
                    ButtonSegment(value: 'from_bank', label: Text('Теглене')),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (v) => setState(() => _direction = v.first),
                ),
              ),
            section(
              'Сума (€)',
              TextField(
                controller: _amount,
                autofocus: widget.event != null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(hintText: '0,00', suffixText: '€'),
              ),
            ),
            if (_book == CashBook.opening)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                    'Колко пари има касата в деня, от който започвате да я водите в Кайрос. '
                    'Въвежда се само веднъж${st.hasBank ? ' за брой и веднъж за банката' : ''} и после '
                    'не може да се променя. Не се брои като приход.',
                    style: TextStyle(fontSize: 15, color: p.textMuted)),
              ),
            if (_book != CashBook.transfer && _book != CashBook.opening) ...[
              section(
                'Вид',
                DropdownButtonFormField<String>(
                  key: ValueKey(_book),
                  initialValue: _cats.contains(_category) ? _category : _cats.first,
                  isExpanded: true,
                  style: fieldStyle.copyWith(color: p.text),
                  items: [for (final c in _cats) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v ?? _cats.first),
                ),
              ),
              if (_category == 'Друго')
                section(
                  'Какъв вид',
                  TextField(
                    controller: _other,
                    textCapitalization: TextCapitalization.sentences,
                    style: fieldStyle,
                    decoration: const InputDecoration(hintText: 'например Хор, Иконопис'),
                  ),
                ),
            ],
            section(
              'Дата',
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(DateTime.now().year - 1),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(_day.format(_date), style: fieldStyle),
              ),
            ),
            if (st.hasBank && _book != CashBook.transfer && widget.holder)
              section(
                'Сметка',
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: 'cash',
                        label: const Text('Брой'),
                        enabled: _book != CashBook.opening ||
                            s.openingAccountsLeft(s.currentChurchId!).contains('cash')),
                    ButtonSegment(
                        value: 'bank',
                        label: const Text('Банка'),
                        enabled: _book != CashBook.opening ||
                            s.openingAccountsLeft(s.currentChurchId!).contains('bank')),
                  ],
                  selected: {_account},
                  onSelectionChanged: (v) => setState(() => _account = v.first),
                ),
              ),
            section(
              'Бележка',
              TextField(
                controller: _note,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: fieldStyle,
              ),
            ),
            Text(
                !widget.holder
                    ? 'Приходът отива при касиера и влиза в Приходната книга, щом го приеме.'
                    : _book == CashBook.income
                        ? 'Приходът влиза направо в Приходната книга.'
                        : _book == CashBook.opening
                            ? (s.cashierOf(s.currentChurchId!) == null
                                ? 'Началното салдо влиза направо.'
                                : 'Началното салдо чака потвърждение от другия от двамата.')
                        : s.cashierOf(s.currentChurchId!) == null
                            ? 'Няма касиер: записът влиза направо, отбелязан „без второ одобрение“.'
                            : _book == CashBook.expense
                                ? 'До ${fmtEur(st.limitEur)} на ден влиза направо; над това чака другия от двамата.'
                                : 'Движението с банката чака одобрение от другия от двамата.',
                style: TextStyle(fontSize: 14.5, color: p.textMuted)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _saving ? null : _save,
              child: Text(widget.holder ? 'Запиши' : 'Предай'),
            ),
          ],
        ),
      ),
    );
  }
}
