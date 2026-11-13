import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../theme.dart';
import '../widgets/church_banner.dart';
import '../widgets/common.dart';

/// „Кайрос в числа“ – общ преглед за създателя. Данните идват от
/// creator_stats(), която отговаря само на профила на създателя.
class CreatorScreen extends StatefulWidget {
  const CreatorScreen({super.key});

  @override
  State<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends State<CreatorScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Supabase.instance.client.rpc('creator_stats');
      if (!mounted) return;
      setState(() {
        _d = Map<String, dynamic>.from(r as Map);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _error = msg.contains('forbidden')
            ? 'Този профил не е записан като създател.'
            : 'Данните не можаха да се заредят.\n$msg';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Кайрос в числа'),
          actions: [
            IconButton(
              tooltip: 'Обнови',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Обобщение'), Tab(text: 'Хора'), Tab(text: 'Храмове')]),
        ),
        body: SafeArea(
          child: _loading && d == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null && d == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                      ),
                    )
                  : TabBarView(children: [
                      _Overview(d!, onRefresh: _load),
                      _People(d, onRefresh: _load),
                      _Churches(d, onRefresh: _load),
                    ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ помощни

int _n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

String _ago(DateTime? t) {
  if (t == null) return 'никога';
  final now = DateTime.now();
  final diff = now.difference(t);
  final hm = DateFormat('HH:mm').format(t);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (diff.inMinutes < 2) return 'току-що';
  if (diff.inMinutes < 60) return 'преди ${diff.inMinutes} мин';
  if (day == today) return 'днес $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'вчера $hm';
  if (diff.inDays < 30) return 'преди ${today.difference(day).inDays} дни';
  return DateFormat('dd.MM.yyyy').format(t);
}

String _date(DateTime? t) => t == null ? '—' : DateFormat('dd.MM.yyyy').format(t);

ChurchRole _role(String? r) => switch (r) {
      'chair' => ChurchRole.chair,
      'cashier' => ChurchRole.cashier,
      _ => ChurchRole.priest,
    };

const _notifyNames = {
  'event': 'Ново събитие',
  'church_event': 'Събитие за храма',
  'event_confirmed': 'Потвърдена Архиерейска',
  'assignment_accepted': 'Прието събитие',
  'assignment_declined': 'Отказано събитие',
  'assignment_kept': 'Събитие остава',
  'join_request': 'Заявка за влизане',
  'member_approved': 'Одобрен свещеник',
  'chair_proposed': 'Предложен председател',
  'chair_responded': 'Отговор за председател',
  'leave_request': 'Заявка за почивка',
  'leave_decided': 'Решение за почивка',
  'leave_ended': 'Прекратена почивка',
  'duty': 'Дежурство',
  'duty_swap': 'Размяна на дежурства',
  'cash_pending': 'Каса – чака',
  'cash_decided': 'Каса – решено',
  'cash_close_pending': 'Затваряне – чака',
  'cash_close_decided': 'Затваряне – решено',
  'stock_loaded': 'Склад – заредено',
  'stock_pending': 'Склад – чака',
  'stock_decided': 'Склад – решено',
};

String _errorText(Map f) {
  final fcm = f['fcm'];
  return switch (f['error']) {
    'fcm_not_configured' => 'липсва ключ на Firebase на сървъра',
    'server_config' => 'липсва настройка на сървъра',
    'not_found' => 'записът вече го няма',
    'bad_request' => 'непълна заявка от приложението',
    'method_not_allowed' => 'грешен вид заявка',
    'fcm' => 'Firebase отказа${fcm is List && fcm.isNotEmpty ? ' (код ${fcm.join(', ')})' : ''}',
    _ => 'код ${f['status']} · ${f['error']}',
  };
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final String? sub;
  final IconData icon;
  final Color? color;
  const _Stat(this.value, this.label, this.icon, {this.sub, this.color});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: c),
          const Spacer(),
          FittedBox(
            child: Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: c)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        if (sub != null) Text(sub!, style: TextStyle(fontSize: 13, color: p.textMuted)),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Palette.of(context).textMuted)),
      );
}

Widget _grid(List<Widget> items) => LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 560 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final i in items) SizedBox(width: w, child: i)]);
    });

class _Bars extends StatelessWidget {
  final Map<String, int> data;
  const _Bars(this.data);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (data.isEmpty) {
      return Text('Няма данни за периода.', style: TextStyle(color: p.textMuted, fontSize: 15));
    }
    final rows = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = rows.first.value;
    return SurfaceCard(
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 150, child: Text(r.key, style: const TextStyle(fontSize: 14.5))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : r.value / max,
                    minHeight: 12,
                    backgroundColor: p.surfaceAlt,
                    color: p.primary,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('${r.value}',
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ обобщение

class _Overview extends StatelessWidget {
  final Map<String, dynamic> d;
  final Future<void> Function() onRefresh;
  const _Overview(this.d, {required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = Map<String, dynamic>.from(d['totals'] as Map);
    final byKind = <String, int>{
      for (final e in Map<String, dynamic>.from(d['events_by_kind'] as Map).entries)
        EventKind.fromName(e.key).label: (e.value as num).toInt(),
    };
    final byType = <String, int>{
      for (final e in Map<String, dynamic>.from(d['notify_by_type'] as Map).entries)
        (_notifyNames[e.key] ?? e.key): (e.value as num).toInt(),
    };
    final failed = (d['notify_failed'] as List).cast<Map>();
    final nt = Map<String, dynamic>.from((d['notify'] as Map?) ?? const {});
    final n1 = Map<String, dynamic>.from((nt['d1'] as Map?) ?? const {});
    final n7 = Map<String, dynamic>.from((nt['d7'] as Map?) ?? const {});
    final since = _dt(nt['since']);
    final versions = <String, int>{
      for (final e in Map<String, dynamic>.from((d['versions'] as Map?) ?? const {}).entries)
        (e.key == '0' ? 'местна' : 'версия ${e.key}'): (e.value as num).toInt(),
    };
    const red = Color(0xFFC0392B);
    const green = Color(0xFF2E7D4F);
    const gold = Color(0xFFB8860B);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text('Обновено: ${_ago(_dt(d['generated_at']))}', style: TextStyle(color: p.textMuted, fontSize: 13.5)),
          const _Section('Хора'),
          _grid([
            _Stat('${_n(t, 'users')}', 'Регистрирани', Icons.people_alt_rounded,
                sub: '+${_n(t, 'new_7')} за 7 дни · +${_n(t, 'new_30')} за 30'),
            _Stat('${_n(t, 'active_1')}', 'Активни днес', Icons.bolt_rounded, color: green,
                sub: 'последните 24 часа'),
            _Stat('${_n(t, 'active_7')}', 'Активни 7 дни', Icons.calendar_view_week_rounded, color: green,
                sub: '${_n(t, 'active_30')} за 30 дни'),
            _Stat('${_n(t, 'with_push')}', 'С известия', Icons.notifications_active_rounded,
                sub: 'телефонът е записан'),
            _Stat('${_n(t, 'no_church')}', 'Без храм', Icons.person_off_rounded,
                color: _n(t, 'no_church') > 0 ? gold : null, sub: 'регистрирани, но не са влезли в храм'),
            _Stat('${_n(t, 'members_pending')}', 'Чакат одобрение', Icons.hourglass_top_rounded,
                color: _n(t, 'members_pending') > 0 ? gold : null, sub: 'за влизане в храм'),
          ]),
          const _Section('Употреба'),
          _grid([
            _Stat('${_n(t, 'churches')}', 'Храмове', Icons.church_rounded),
            _Stat('${_n(t, 'events')}', 'Събития', Icons.event_rounded,
                sub: '+${_n(t, 'events_7')} за 7 дни · +${_n(t, 'events_30')} за 30'),
            _Stat('${_n(t, 'events_upcoming')}', 'Предстоящи', Icons.upcoming_rounded,
                sub: '${_n(t, 'events_done')} проведени'),
            _Stat('${_n(t, 'cash')}', 'Записи в касата', Icons.payments_rounded, color: green,
                sub: '+${_n(t, 'cash_30')} за 30 дни · ${_n(t, 'cash_pending')} чакат'),
            _Stat('${_n(t, 'stock')}', 'Движения в склада', Icons.inventory_2_rounded,
                sub: '+${_n(t, 'stock_30')} за 30 дни'),
            _Stat('${_n(t, 'leaves')}', 'Почивки', Icons.beach_access_rounded,
                sub: '${_n(t, 'leaves_pending')} чакат решение'),
          ]),
          const _Section('Известия (push)'),
          _grid([
            _Stat('${_n(n1, 'delivered')}', 'Доставени · 24 ч', Icons.mark_email_read_rounded, color: green,
                sub: '${_n(n7, 'delivered')} за 7 дни · до телефони'),
            _Stat('${_n(n1, 'errors')}', 'Грешки · 24 ч', Icons.error_outline_rounded,
                color: _n(n1, 'errors') > 0 ? red : green,
                sub: '${_n(n7, 'errors')} за 7 дни${_n(n7, 'errors') == 0 ? ' · всичко е наред' : ''}'),
            _Stat('${_n(n7, 'no_recipient')}', 'Без получател', Icons.person_search_rounded,
                sub: 'за 7 дни · само до себе си или човек без телефон – не е грешка'),
            _Stat('${_n(n7, 'stale')}', 'Стари телефони', Icons.phonelink_erase_rounded,
                sub: 'за 7 дни · преинсталирано или изтрито приложение; изчистват се сами – не е грешка'),
            _Stat('${_n(n7, 'refused')}', 'Отказани (защита)', Icons.shield_rounded,
                sub: 'за 7 дни · опит без вход; повечето са проверките на сървъра при всяка версия'),
          ]),
          if (since != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Дневникът на известията пази данни от ${_date(since)} (до 14 дни назад).',
                  style: TextStyle(color: p.textMuted, fontSize: 13.5)),
            ),
          const _Section('Кой коя версия ползва'),
          _Bars(versions),
          const _Section('Събития по вид · 30 дни'),
          _Bars(byKind),
          const _Section('Доставени известия по вид · 7 дни'),
          _Bars(byType),
          if (failed.isNotEmpty) ...[
            const _Section('Последни истински грешки'),
            SurfaceCard(
              child: Column(children: [
                for (final f in failed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.error_outline_rounded, color: red),
                    title: Text(_notifyNames[f['type']] ?? '${f['type']}', style: const TextStyle(fontSize: 15)),
                    subtitle: Text('${_ago(_dt(f['at']))} · ${_errorText(f)}'),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ хора

class _People extends StatefulWidget {
  final Map<String, dynamic> d;
  final Future<void> Function() onRefresh;
  const _People(this.d, {required this.onRefresh});

  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  String _q = '';
  bool _bySeen = true;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final all = (widget.d['users'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    String name(Map<String, dynamic> u) => withRank(ClergyRank.fromCode(u['rank']), '${u['name']}');
    final q = _q.trim().toLowerCase();
    final list = all.where((u) {
      if (q.isEmpty) return true;
      return [name(u), u['username'], u['email'], u['phone'], ...(u['churches'] as List).map((c) => c['name'])]
          .any((v) => v != null && '$v'.toLowerCase().contains(q));
    }).toList();
    list.sort((a, b) {
      final k = _bySeen ? 'last_seen' : 'created_at';
      final da = _dt(a[k]) ?? DateTime(2000);
      final db = _dt(b[k]) ?? DateTime(2000);
      return db.compareTo(da);
    });
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Име, потребител, имейл, храм…',
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Последно влизане')),
              ButtonSegment(value: false, label: Text('Регистрация')),
            ],
            selected: {_bySeen},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _bySeen = v.first),
          ),
          const SizedBox(height: 8),
          Text('${list.length} от ${all.length}', style: TextStyle(color: p.textMuted, fontSize: 13.5)),
          const SizedBox(height: 8),
          for (final u in list) ...[
            _PersonCard(u, name(u)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final Map<String, dynamic> u;
  final String name;
  const _PersonCard(this.u, this.name);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final seen = _dt(u['last_seen']);
    final fresh = seen != null && DateTime.now().difference(seen).inDays < 7;
    final churches = (u['churches'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final muted = TextStyle(fontSize: 14, color: p.textMuted);
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: fresh ? const Color(0xFF2E7D4F) : p.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          Icon(u['push'] == true ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              size: 20, color: u['push'] == true ? p.primary : p.textMuted),
        ]),
        const SizedBox(height: 4),
        Text([if (u['username'] != null) '@${u['username']}', if (u['email'] != null) '${u['email']}'].join(' · '),
            style: muted),
        if ((u['phone'] as String?)?.isNotEmpty == true) Text('${u['phone']}', style: muted),
        const SizedBox(height: 6),
        Text('Последно: ${_ago(seen)}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        Text(
            [
              'Регистриран: ${_date(_dt(u['created_at']))}',
              'събития: ${u['events']}',
              u['build'] == null ? 'версия: още няма данни' : 'версия ${u['build']}',
            ].join(' · '),
            style: muted),
        if (churches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Не е в храм', style: TextStyle(fontSize: 14, color: p.textMuted, fontStyle: FontStyle.italic)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              for (final c in churches)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  RoleBadge(_role(c['role'] as String?), small: true),
                  const SizedBox(width: 5),
                  Text('${c['name']}${c['status'] == 'pending' ? ' (чака)' : ''}',
                      style: const TextStyle(fontSize: 14)),
                ]),
            ]),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ храмове

class _Churches extends StatelessWidget {
  final Map<String, dynamic> d;
  final Future<void> Function() onRefresh;
  const _Churches(this.d, {required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final list = (d['churches'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final muted = TextStyle(fontSize: 14, color: p.textMuted);
    Widget line(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Icon(i, size: 18, color: p.textMuted),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: const TextStyle(fontSize: 15))),
          ]),
        );
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text('${list.length} храма', style: TextStyle(color: p.textMuted, fontSize: 13.5)),
          const SizedBox(height: 8),
          for (final c in list) ...[
            SurfaceCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('${c['settlement']} · от ${_date(_dt(c['created_at']))}', style: muted),
                const SizedBox(height: 4),
                line(Icons.people_alt_rounded,
                    '${c['active']} свещеници${(c['pending'] as num) > 0 ? ' · ${c['pending']} чакат' : ''}'),
                line(ChurchRole.chair.icon, 'Председател: ${c['chair'] ?? '—'}'),
                line(ChurchRole.cashier.icon, 'Касиер: ${c['cashier'] ?? 'няма'}'),
                line(Icons.event_rounded, 'Събития: ${c['events']} (+${c['events_30']} за 30 дни)'),
                line(Icons.payments_rounded, 'Каса: ${c['cash']} записа · Склад: ${c['stock']} движения'),
              ]),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
