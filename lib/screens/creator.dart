import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/church_banner.dart';
import '../widgets/common.dart';
import '../widgets/whats_new.dart' show buildNumber;
import 'priest_profile.dart' show showTempPassword;

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
      Map<String, dynamic> extra = {};
      try {
        extra = Map<String, dynamic>.from(await Supabase.instance.client.rpc('creator_extra') as Map);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _d = {...Map<String, dynamic>.from(r as Map), 'extra': extra};
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
      length: 6,
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
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Обобщение'),
            Tab(text: 'Хора'),
            Tab(text: 'Храмове'),
            Tab(text: 'Грешки'),
            Tab(text: 'Отзиви'),
            Tab(text: 'Съобщения'),
          ]),
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
                      _Errors(d, onRefresh: _load),
                      _FeedbackList(d, onRefresh: _load),
                      _Announce(d, onRefresh: _load),
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
    final ex = Map<String, dynamic>.from((d['extra'] as Map?) ?? const {});
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
          const _Section('Грешки и версия'),
          _grid([
            _Stat('${_n(ex, 'errors_24')}', 'Грешки · 24 ч', Icons.bug_report_rounded,
                color: _n(ex, 'errors_24') > 0 ? red : green, sub: '${_n(ex, 'errors_7')} за 7 дни · раздел „Грешки“'),
            _Stat(_n(ex, 'min_build') == 0 ? '—' : '${_n(ex, 'min_build')}', 'Минимална версия', Icons.system_update_rounded,
                sub: 'по-старите виждат „обновете“'),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: buildNumber <= 0
                  ? null
                  : () async {
                      try {
                        await AppScope.read(context).creatorSetMinBuild(buildNumber);
                        await onRefresh();
                      } on AppError catch (e) {
                        if (context.mounted) showMessage(context, e.message);
                      }
                    },
              child: Text('Искай версия $buildNumber'),
            ),
            if (_n(ex, 'min_build') > 0)
              TextButton(
                onPressed: () async {
                  await AppScope.read(context).creatorSetMinBuild(0);
                  await onRefresh();
                },
                child: const Text('Без напомняне'),
              ),
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
            _PersonCard(u, name(u), onRefresh: widget.onRefresh),
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
  final Future<void> Function()? onRefresh;
  const _PersonCard(this.u, this.name, {this.onRefresh});

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
          if (u['id'] != AppScope.of(context).currentUser?.id)
            PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (v) async {
                final s = AppScope.read(context);
                if (v == 'pass') {
                  await showTempPassword(context, '', u['id'] as String, name, username: u['username'] as String?);
                } else if (v == 'delete') {
                  final ok = await confirm(
                      context,
                      'Изтриване на профила',
                      '$name ще бъде изтрит окончателно. Събитията, записани от него за колеги, минават към '
                          'председателя; записите в касата остават. Това не може да се върне.',
                      'Изтрий');
                  if (!ok || !context.mounted) return;
                  try {
                    await s.creatorDeleteUser(u['id'] as String);
                    if (context.mounted) showMessage(context, 'Профилът е изтрит.');
                    await onRefresh?.call();
                  } on AppError catch (e) {
                    if (context.mounted) showMessage(context, e.message);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pass', child: Text('Временна парола')),
                PopupMenuItem(value: 'delete', child: Text('Изтрий профила')),
              ],
            ),
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
                _ChurchControls(church: c, settings: Map<String, dynamic>.from(
                    ((d['extra'] as Map?)?['church_settings'] as Map?)?[c['id']] as Map? ?? const {}),
                    onRefresh: onRefresh),
              ]),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}


// ------------------------------------------------------------ настройки по храм

class _ChurchControls extends StatefulWidget {
  final Map<String, dynamic> church;
  final Map<String, dynamic> settings;
  final Future<void> Function() onRefresh;
  const _ChurchControls({required this.church, required this.settings, required this.onRefresh});

  @override
  State<_ChurchControls> createState() => _ChurchControlsState();
}

class _ChurchControlsState extends State<_ChurchControls> {
  bool _busy = false;

  Future<void> _set({bool? cash, bool? stock, bool? off}) async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context)
          .creatorChurchSettings(widget.church['id'] as String, cash: cash, stock: stock, approvalsOff: off);
      await widget.onRefresh();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _chair() async {
    final s = AppScope.read(context);
    final id = widget.church['id'] as String;
    List<Map<String, dynamic>> members;
    try {
      members = (await s.creatorChurchMembers(id)).where((m) => m['status'] == 'active').toList();
    } catch (_) {
      if (mounted) showMessage(context, 'Свещениците не можаха да се заредят.');
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text('Нов председател на ${widget.church['name']}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          for (final m in members)
            ListTile(
              title: Text(withRank(ClergyRank.fromCode(m['rank']), '${m['name']}')),
              trailing: m['role'] == 'manager' ? const Text('председател') : null,
              onTap: m['role'] == 'manager' ? null : () => Navigator.pop(ctx, m),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await confirm(context, 'Смяна на председателя',
        '${picked['name']} става председател веднага, без да чака съгласие. Сегашният става редови свещеник.', 'Смени');
    if (!ok || !mounted) return;
    try {
      await s.creatorSetChair(id, picked['id'] as String);
      if (mounted) showMessage(context, 'Председателят е сменен.');
      await widget.onRefresh();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.settings;
    bool v(String k, bool def) => (st[k] as bool?) ?? def;
    Widget sw(String label, bool value, ValueChanged<bool> on) => SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: const TextStyle(fontSize: 15)),
          value: value,
          onChanged: _busy ? null : on,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 20),
      sw('Каса', v('cash', true), (x) => _set(cash: x)),
      sw('Склад', v('stock', true), (x) => _set(stock: x)),
      sw('Тестов режим без второ одобрение', v('approvals_allowed', false), (x) => _set(off: x)),
      Text(
          v('approvals_allowed', false)
              ? 'Разрешено – председателят сам го пуска и спира (сега: ${v('approvals_off', false) ? 'пуснат' : 'спрян'}).'
              : 'Заключено – второто одобрение е задължително.',
          style: TextStyle(fontSize: 13, color: Palette.of(context).textMuted)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _chair,
          icon: const Icon(Icons.workspace_premium_outlined),
          label: const Text('Смени председателя'),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------ грешки

class _Errors extends StatelessWidget {
  final Map<String, dynamic> d;
  final Future<void> Function() onRefresh;
  const _Errors(this.d, {required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final list = (((d['extra'] as Map?)?['errors'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text('Грешки от телефоните (последните 40). Без лични данни – само екран, версия и описание.',
              style: TextStyle(color: p.textMuted, fontSize: 13.5)),
          const SizedBox(height: 8),
          if (list.isEmpty) const Text('Няма грешки. 🙂', style: TextStyle(fontSize: 16)),
          for (final e in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('${e['message']}',
                        maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                    subtitle: Text(
                        '${_ago(_dt(e['at']))} · ${e['user']} · версия ${e['build'] ?? '?'}'
                        '${(e['screen'] as String?)?.isNotEmpty == true ? ' · ${e['screen']}' : ''}',
                        style: TextStyle(fontSize: 13, color: p.textMuted)),
                    children: [
                      SelectableText('${e['message']}\n\n${e['stack'] ?? ''}',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ обратна връзка

class _FeedbackList extends StatelessWidget {
  final Map<String, dynamic> d;
  final Future<void> Function() onRefresh;
  const _FeedbackList(this.d, {required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final list = (((d['extra'] as Map?)?['feedback'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(children: [
            Expanded(
              child: Text('${list.where((f) => f['done'] != true).length} нови · ${list.length} общо',
                  style: TextStyle(color: p.textMuted, fontSize: 13.5)),
            ),
            if (list.any((f) => f['done'] == true))
              TextButton.icon(
                onPressed: () async {
                  final done = list.where((f) => f['done'] == true).toList();
                  final ok = await confirm(context, 'Изтриване на свършените',
                      '${done.length} отзива и снимките им ще бъдат изтрити окончателно.', 'Изтрий');
                  if (!ok || !context.mounted) return;
                  try {
                    await s.creatorDeleteFeedback([for (final f in done) (f['id'] as String, f['photo'] as String?)]);
                    if (context.mounted) showMessage(context, 'Изтрити: ${done.length}.');
                    await onRefresh();
                  } on AppError catch (e) {
                    if (context.mounted) showMessage(context, e.message);
                  }
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Изтрий свършените'),
              ),
          ]),
          const SizedBox(height: 8),
          if (list.isEmpty) const Text('Още няма отзиви.', style: TextStyle(fontSize: 16)),
          for (final f in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: f['done'] == true ? .55 : 1,
                child: SurfaceCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: Text(withRank(ClergyRank.fromCode(f['rank']), '${f['user']}'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      Checkbox(
                        value: f['done'] == true,
                        onChanged: (v) async {
                          await s.creatorFeedbackDone(f['id'] as String, v ?? false);
                          await onRefresh();
                        },
                      ),
                      IconButton(
                        tooltip: 'Изтрий',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          final ok = await confirm(context, 'Изтриване на отзива',
                              'Отзивът${f['photo'] != null ? ' и снимката му' : ''} ще бъдат изтрити окончателно.', 'Изтрий');
                          if (!ok || !context.mounted) return;
                          try {
                            await s.creatorDeleteFeedback([(f['id'] as String, f['photo'] as String?)]);
                            await onRefresh();
                          } on AppError catch (e) {
                            if (context.mounted) showMessage(context, e.message);
                          }
                        },
                      ),
                    ]),
                    Text('${_ago(_dt(f['at']))} · версия ${f['build'] ?? '?'}${f['church'] == null ? '' : ' · ${f['church']}'}',
                        style: TextStyle(fontSize: 13, color: p.textMuted)),
                    const SizedBox(height: 6),
                    SelectableText('${f['body']}', style: const TextStyle(fontSize: 15.5)),
                    if (f['photo'] != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final bytes = await s.feedbackPhoto(f['photo'] as String);
                            if (!context.mounted) return;
                            if (bytes == null) {
                              showMessage(context, 'Снимката не можа да се зареди.');
                              return;
                            }
                            await showDialog<void>(
                              context: context,
                              builder: (ctx) => Dialog(
                                child: InteractiveViewer(child: Image.memory(bytes)),
                              ),
                            );
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Снимка на екрана'),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ съобщения

class _Announce extends StatefulWidget {
  final Map<String, dynamic> d;
  final Future<void> Function() onRefresh;
  const _Announce(this.d, {required this.onRefresh});

  @override
  State<_Announce> createState() => _AnnounceState();
}

class _AnnounceState extends State<_Announce> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _church; // null = всички
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) {
      showMessage(context, 'Напишете заглавие.');
      return;
    }
    final churches = (widget.d['churches'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final target = _church == null ? 'всички' : '${churches.firstWhere((c) => c['id'] == _church)['name']}';
    final ok = await confirm(context, 'Изпращане', 'Съобщението отива до: $target. Всеки ще получи известие.', 'Изпрати');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).creatorAnnounce(_title.text.trim(), _body.text.trim(), _church);
      _title.clear();
      _body.clear();
      if (mounted) showMessage(context, 'Съобщението е изпратено.');
      await widget.onRefresh();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final churches = (widget.d['churches'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final sent = (((widget.d['extra'] as Map?)?['announcements'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text('Излиза като известие и като карта с „ОК“ в приложението.',
              style: TextStyle(color: p.textMuted, fontSize: 13.5)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _church,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'До'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Всички')),
              for (final c in churches)
                DropdownMenuItem<String?>(value: c['id'] as String, child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _church = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Заглавие', hintText: 'напр. Има нова версия'),
          ),
          TextField(
            controller: _body,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Текст (по желание)'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.campaign_rounded),
            label: const Text('Изпрати съобщението'),
          ),
          if (sent.isNotEmpty) ...[
            const _Section('Изпратени'),
            for (final a in sent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a['title']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if ((a['body'] as String?)?.isNotEmpty == true) Text('${a['body']}', style: const TextStyle(fontSize: 14.5)),
                    Text('${_ago(_dt(a['at']))} · до ${a['church'] ?? 'всички'} · видели: ${a['seen']}',
                        style: TextStyle(fontSize: 13, color: p.textMuted)),
                  ]),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
