import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cash.dart';

final _month = DateFormat('LLLL y', 'bg');
final _monthOnly = DateFormat('LLLL', 'bg');
final _dShort = DateFormat('d.MM.y', 'bg');

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String monthLabel(DateTime m) => _cap(_month.format(m));

// =====================================================================
// Филтър в книгите
// =====================================================================
class CashFilter {
  final DateTime? from; // включително
  final DateTime? to; // включително
  final String? category;
  final String? who;
  final double? min;
  final double? max;
  final String text; // търсене в бележка, вид, дарител
  const CashFilter({this.from, this.to, this.category, this.who, this.min, this.max, this.text = ''});

  bool get isActive => count > 0;
  int get count => [
        from != null || to != null,
        category != null,
        who != null,
        min != null || max != null,
        text.trim().isNotEmpty
      ]
      .where((x) => x)
      .length;

  bool matches(CashEntry e) {
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    if (from != null && d.isBefore(from!)) return false;
    if (to != null && d.isAfter(to!)) return false;
    if (category != null && e.categoryLabel != category && e.category != category) return false;
    if (who != null && e.createdBy != who) return false;
    final a = e.amount.abs();
    if (min != null && a < min!) return false;
    if (max != null && a > max!) return false;
    final q = text.trim().toLowerCase();
    if (q.isNotEmpty &&
        ![e.note, e.categoryLabel, e.donor].any((x) => x.toLowerCase().contains(q))) {
      return false;
    }
    return true;
  }

  List<String> describe(AppState s) => [
        if (from != null || to != null)
          '${from == null ? '…' : _dShort.format(from!)} – ${to == null ? '…' : _dShort.format(to!)}',
        if (category != null) category!,
        if (who != null) s.priestName(who!),
        if (min != null || max != null)
          '${min == null ? '' : 'от ${fmtEur(min!)} '}${max == null ? '' : 'до ${fmtEur(max!)}'}'.trim(),
        if (text.trim().isNotEmpty) '„${text.trim()}“',
      ];
}

Future<CashFilter?> showCashFilter(BuildContext context, CashFilter current, String churchId) {
  final s = AppScope.read(context);
  var from = current.from, to = current.to;
  String? cat = current.category, who = current.who;
  final textC = TextEditingController(text: current.text);
  final minC = TextEditingController(text: current.min?.toStringAsFixed(2) ?? '');
  final maxC = TextEditingController(text: current.max?.toStringAsFixed(2) ?? '');
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 1);
  final cats = {...incomeCategories, ...expenseCategories}.where((c) => c != 'Друго').toList()..add('Друго');
  return showModalBottomSheet<CashFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final p = Palette.of(ctx);
      Widget quick(String label, DateTime f, DateTime t) => ChoiceChip(
            label: Text(label),
            selected: from == f && to == t,
            onSelected: (_) => set(() {
              from = f;
              to = t;
            }),
          );
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Филтър', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const FieldLabel('Търсене в бележката'),
            TextField(
              controller: textC,
              decoration: const InputDecoration(
                  hintText: 'например покрив, ток, име на дарител', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Период'),
            Wrap(spacing: 8, runSpacing: 6, children: [
              quick('Този месец', thisMonth, DateTime(now.year, now.month + 1, 0)),
              quick('Миналия месец', DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 0)),
              quick('Тази година', DateTime(now.year, 1, 1), DateTime(now.year, 12, 31)),
              ActionChip(
                avatar: const Icon(Icons.date_range_rounded, size: 18),
                label: const Text('Избери…'),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: ctx,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 1),
                    initialDateRange: from != null && to != null ? DateTimeRange(start: from!, end: to!) : null,
                  );
                  if (r != null) {
                    set(() {
                      from = r.start;
                      to = r.end;
                    });
                  }
                },
              ),
              if (from != null || to != null)
                ActionChip(
                    label: const Text('Всички дати'),
                    onPressed: () => set(() {
                          from = null;
                          to = null;
                        })),
            ]),
            if (from != null || to != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${from == null ? '…' : _dShort.format(from!)} – ${to == null ? '…' : _dShort.format(to!)}',
                    style: TextStyle(fontSize: 15, color: p.textMuted)),
              ),
            const SizedBox(height: 16),
            const FieldLabel('Вид'),
            DropdownButtonFormField<String?>(
              initialValue: cat,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('Всички видове')),
                for (final c in cats) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => set(() => cat = v),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Въвел'),
            DropdownButtonFormField<String?>(
              initialValue: who,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('Всички')),
                for (final (u, _) in s.priestsOf(churchId)) DropdownMenuItem(value: u.id, child: Text(u.fullName)),
              ],
              onChanged: (v) => set(() => who = v),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Сума (€)'),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: minC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'от'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: maxC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'до'),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, const CashFilter()),
                  child: const Text('Изчисти'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.pop(
                      ctx,
                      CashFilter(
                        from: from,
                        to: to,
                        category: cat,
                        who: who,
                        min: parseAmount(minC.text),
                        max: parseAmount(maxC.text),
                        text: textC.text,
                      )),
                  child: const Text('Покажи'),
                ),
              ),
            ]),
          ]),
        ),
      );
    }),
  ).whenComplete(() {
    textC.dispose();
    minC.dispose();
    maxC.dispose();
  });
}

// =====================================================================
// Справки: месец или година, по видове, със сравнения
// =====================================================================
class CashReportScreen extends StatefulWidget {
  const CashReportScreen({super.key});

  @override
  State<CashReportScreen> createState() => _CashReportScreenState();
}

class _CashReportScreenState extends State<CashReportScreen> {
  bool _year = false;
  DateTime _at = DateTime(DateTime.now().year, DateTime.now().month, 1);

  (DateTime, DateTime) _range(DateTime at) =>
      _year ? (DateTime(at.year, 1, 1), DateTime(at.year + 1, 1, 1)) : (at, DateTime(at.year, at.month + 1, 1));

  DateTime get _prev => _year ? DateTime(_at.year - 1, 1, 1) : DateTime(_at.year, _at.month - 1, 1);
  DateTime get _lastYear => DateTime(_at.year - 1, _at.month, 1);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final all = s.cashEntries(church);
    final (f, t) = _range(_at);
    final (pf, pt) = _range(_prev);
    final (lf, lt) = _range(_lastYear);
    final inc = cashByCategory(all, CashBook.income, f, t);
    final exp = cashByCategory(all, CashBook.expense, f, t);
    final incT = inc.values.fold(0.0, (a, b) => a + b);
    final expT = exp.values.fold(0.0, (a, b) => a + b);
    final title = _year ? '${_at.year} г.' : monthLabel(_at);
    final now = DateTime.now();
    final canNext = _year ? _at.year < now.year : DateTime(_at.year, _at.month + 1, 1).isBefore(DateTime(now.year, now.month + 1, 1));
    final closed = !_year && s.isMonthClosed(church, _at);

    return Scaffold(
      appBar: AppBar(title: const Text('Справки')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Месец')),
                ButtonSegment(value: true, label: Text('Година')),
              ],
              selected: {_year},
              onSelectionChanged: (v) => setState(() => _year = v.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              IconButton.outlined(
                tooltip: 'Назад',
                onPressed: () => setState(() => _at = _prev),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(children: [
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  if (closed)
                    Text('приключен', style: TextStyle(fontSize: 14, color: Colors.green.shade700, fontWeight: FontWeight.w700)),
                ]),
              ),
              IconButton.outlined(
                tooltip: 'Напред',
                onPressed: canNext
                    ? () => setState(() => _at = _year ? DateTime(_at.year + 1, 1, 1) : DateTime(_at.year, _at.month + 1, 1))
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _total(context, 'Приходи', incT, bookColor(context, CashBook.income))),
              const SizedBox(width: 10),
              Expanded(child: _total(context, 'Разходи', expT, bookColor(context, CashBook.expense))),
            ]),
            const SizedBox(height: 10),
            _total(context, 'Разлика (приходи − разходи)', incT - expT,
                incT - expT < 0 ? bookColor(context, CashBook.expense) : p.primary),
            const SizedBox(height: 18),
            const Text('Сравнение', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(children: [
                _compareHeader(context, _year ? '${_prev.year} г.' : _cap(_monthOnly.format(_prev)),
                    _year ? null : '${_cap(_monthOnly.format(_lastYear))} ${_lastYear.year}'),
                _compareRow(context, 'Приходи', incT, cashTotal(all, CashBook.income, pf, pt),
                    _year ? null : cashTotal(all, CashBook.income, lf, lt), good: true),
                _compareRow(context, 'Разходи', expT, cashTotal(all, CashBook.expense, pf, pt),
                    _year ? null : cashTotal(all, CashBook.expense, lf, lt), good: false),
              ]),
            ),
            const SizedBox(height: 18),
            _breakdown(context, 'Приходи по видове', inc, incT, bookColor(context, CashBook.income)),
            const SizedBox(height: 18),
            _breakdown(context, 'Разходи по видове', exp, expT, bookColor(context, CashBook.expense)),
            ..._donors(context, all, f, t),
            ..._openings(context, all),
            const SizedBox(height: 14),
            Text('Справката е по влезлите в книгите записи (със сторната). Началното салдо и движенията с банката не се броят.',
                style: TextStyle(fontSize: 13.5, color: p.textMuted)),
          ],
        ),
      ),
    );
  }

  List<Widget> _donors(BuildContext context, List<CashEntry> all, DateTime f, DateTime t) {
    final p = Palette.of(context);
    final gifts = all
        .where((e) =>
            e.isApproved &&
            e.book == CashBook.income &&
            e.category == 'Дарение' &&
            !e.date.isBefore(f) &&
            e.date.isBefore(t))
        .toList();
    if (gifts.isEmpty) return [];
    final by = <String, double>{};
    for (final g in gifts) {
      final k = g.donor.isEmpty ? 'Без име' : g.donor;
      by[k] = (by[k] ?? 0) + g.amount;
    }
    final rows = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      const SizedBox(height: 18),
      const Text('Дарители', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(Icons.volunteer_activism_outlined, size: 20, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(r.key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Text(fmtEur(r.value), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
    ];
  }

  List<Widget> _openings(BuildContext context, List<CashEntry> all) {
    final p = Palette.of(context);
    final ops = all.where((e) => e.book == CashBook.opening && e.isApproved).toList();
    if (ops.isEmpty) return [];
    return [
      const SizedBox(height: 18),
      const Text('Начално салдо', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final o in ops)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
              child: Text('${o.account == 'bank' ? 'Банка' : 'Брой'} · ${o.ref} · ${_dShort.format(o.date)}',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
            ),
            Text(fmtEur(o.amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
    ];
  }

  Widget _total(BuildContext context, String label, double v, Color c) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.dark ? .18 : .10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: .5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 14, color: p.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(fmtEur(v),
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: c, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _compareHeader(BuildContext context, String prev, String? lastYear) {
    final p = Palette.of(context);
    final st = TextStyle(fontSize: 13, color: p.textMuted, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(flex: 4, child: Text('спрямо $prev', style: st, textAlign: TextAlign.end)),
        if (lastYear != null) Expanded(flex: 4, child: Text('спрямо $lastYear', style: st, textAlign: TextAlign.end)),
      ]),
    );
  }

  Widget _compareRow(BuildContext context, String label, double now, double prev, double? lastYear,
      {required bool good}) {
    Widget delta(double base) {
      final d = now - base;
      final pct = base.abs() < 0.005 ? null : d / base.abs() * 100;
      final up = d > 0.004, down = d < -0.004;
      final c = !up && !down
          ? Palette.of(context).textMuted
          : (up == good ? Colors.green.shade700 : Theme.of(context).colorScheme.error);
      return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${up ? '▲' : down ? '▼' : '='} ${fmtEur(d.abs())}',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
        Text(pct == null ? 'преди: ${fmtEur(base)}' : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(0)}% · преди ${fmtEur(base)}',
            style: TextStyle(fontSize: 12, color: Palette.of(context).textMuted)),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        Expanded(flex: 4, child: delta(prev)),
        if (lastYear != null) Expanded(flex: 4, child: delta(lastYear)),
      ]),
    );
  }

  Widget _breakdown(BuildContext context, String title, Map<String, double> m, double total, Color c) {
    final p = Palette.of(context);
    final rows = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxV = rows.isEmpty ? 1.0 : rows.map((e) => e.value.abs()).reduce((a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      if (rows.isEmpty) Text('Няма записи за периода.', style: TextStyle(fontSize: 15, color: p.textMuted)),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(r.key, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600))),
              Text(fmtEur(r.value), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              SizedBox(
                width: 48,
                child: Text(total.abs() < 0.005 ? '' : '${(r.value / total * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: p.textMuted)),
              ),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (r.value.abs() / maxV).clamp(0.0, 1.0),
                minHeight: 10,
                color: c,
                backgroundColor: c.withValues(alpha: .12),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// =====================================================================
// Месеци: приключване (касиерът иска, председателят одобрява)
// =====================================================================
class CashMonthsScreen extends StatelessWidget {
  const CashMonthsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final now = DateTime.now();
    final all = s.cashEntries(church);
    final months = [for (var i = 1; i <= 12; i++) DateTime(now.year, now.month - i, 1)];
    final canRequest = s.canRequestClose(church);
    final cashier = s.cashierOf(church);
    return Scaffold(
      appBar: AppBar(title: const Text('Приключване на месеци')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                  cashier == null
                      ? 'Няма касиер: председателят приключва месеца сам. След приключване запис с дата в месеца може да се добави само със задна дата.'
                      : 'Касиерът приключва месеца, председателят одобрява. След това запис с дата в месеца се добавя само със задна дата и с одобрение от другия.',
                  style: TextStyle(fontSize: 15, color: p.textMuted, height: 1.4)),
              const SizedBox(height: 14),
              for (final per in s.closesToApprove(church))
                Padding(padding: const EdgeInsets.only(bottom: 12), child: CloseMonthCard(period: per)),
              for (final m in months) _monthRow(context, s, church, m, all, canRequest),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthRow(BuildContext context, AppState s, String church, DateTime m, List<CashEntry> all, bool canRequest) {
    final p = Palette.of(context);
    final per = s.periodOf(church, m);
    final next = DateTime(m.year, m.month + 1, 1);
    final inc = cashTotal(all, CashBook.income, m, next);
    final exp = cashTotal(all, CashBook.expense, m, next);
    final pending = all.where((e) => e.isPending && e.date.year == m.year && e.date.month == m.month).length;
    final (label, color) = per == null
        ? ('открит', p.textMuted)
        : per.isClosed
            ? (per.single ? 'приключен (без второ одобрение)' : 'приключен', Colors.green.shade700)
            : ('чака председателя', Palette.onYellow);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: per != null && !per.isClosed ? Palette.yellow.withValues(alpha: .22) : p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: per?.isClosed == true ? Colors.green.shade600 : p.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(per?.isClosed == true ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: per?.isClosed == true ? Colors.green.shade700 : p.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(monthLabel(m), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('приходи ${fmtEur(inc)} · разходи ${fmtEur(exp)}',
                    style: TextStyle(fontSize: 13.5, color: p.textMuted)),
                Text(pending > 0 ? '$label · $pending чакащи записа' : label,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
              ]),
            ),
          ]),
          if (per == null && canRequest) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: pending > 0
                  ? () => showMessage(context, 'В ${monthLabel(m)} има чакащи записи – първо ги решете.')
                  : () async {
                      final ok = await confirm(
                          context,
                          'Приключи ${monthLabel(m)}?',
                          s.cashierOf(church) == null
                              ? 'След това записи с дата в месеца се добавят само със задна дата.'
                              : 'Председателят ще получи известие да одобри. След това записи с дата в месеца '
                                  'се добавят само със задна дата и с одобрение.',
                          'Приключи');
                      if (!ok || !context.mounted) return;
                      try {
                        await s.requestClose(church, m);
                        if (context.mounted) {
                          showMessage(context,
                              s.isMonthClosed(church, m) ? '${monthLabel(m)} е приключен.' : 'Изпратено за одобрение.');
                        }
                      } on AppError catch (e) {
                        if (context.mounted) showMessage(context, e.message);
                      }
                    },
              child: Text('Приключи ${monthLabel(m)}'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Карта за председателя: касиерът иска да приключи месеца.
class CloseMonthCard extends StatefulWidget {
  final CashPeriod period;
  const CloseMonthCard({super.key, required this.period});

  @override
  State<CloseMonthCard> createState() => _CloseMonthCardState();
}

class _CloseMonthCardState extends State<CloseMonthCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final per = widget.period;
    Future<void> go(bool approve) async {
      setState(() => _busy = true);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await s.decideClose(per.churchId, per.month, approve);
        messenger.showSnackBar(SnackBar(
            content: Text(approve ? '${monthLabel(per.month)} е приключен.' : 'Приключването е върнато на касиера.')));
      } on AppError catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      if (mounted) setState(() => _busy = false);
    }

    final all = s.cashEntries(per.churchId);
    final next = DateTime(per.month.year, per.month.month + 1, 1);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.yellow, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.lock_clock_outlined, color: p.primary),
          const SizedBox(width: 8),
          Text('Каса: приключване на месец',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textMuted)),
        ]),
        const SizedBox(height: 6),
        Text(monthLabel(per.month), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(
            '${s.priestName(per.requestedBy ?? '')} иска да го приключи · приходи '
            '${fmtEur(cashTotal(all, CashBook.income, per.month, next))} · разходи '
            '${fmtEur(cashTotal(all, CashBook.expense, per.month, next))}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => go(false), child: const Text('Върни'))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => go(true),
              child: const Text('Приключи'),
            ),
          ),
        ]),
      ]),
    );
  }
}
