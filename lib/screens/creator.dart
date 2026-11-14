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
      try {
        extra['chat'] = Map<String, dynamic>.from(await Supabase.instance.client.rpc('creator_chat_stats') as Map);
      } catch (_) {}
      Map<String, dynamic> flags = {};
      try {
        flags = Map<String, dynamic>.from(await Supabase.instance.client.rpc('creator_people_flags') as Map);
      } catch (_) {}
      final base = Map<String, dynamic>.from(r as Map);
      base['users'] = [
        for (final u in (base['users'] as List? ?? const []))
          {...Map<String, dynamic>.from(u as Map), 'suspended': flags.containsKey('${(u as Map)['id']}')},
      ];
      if (!mounted) return;
      setState(() {
        _d = {...base, 'extra': extra};
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
          const _Section('Чат'),
          SurfaceCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Чат за всички', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              subtitle: const Text('Изключено – чатът се вижда само при вас. Включено – раздел „Чат“ за всички.'),
              value: AppScope.of(context).chatEnabledGlobal,
              onChanged: (v) async {
                try {
                  await AppScope.read(context).creatorSetChat(v);
                } on AppError catch (e) {
                  if (context.mounted) showMessage(context, e.message);
                }
              },
            ),
          ),
          Builder(builder: (context) {
            final ch = Map<String, dynamic>.from((ex['chat'] as Map?) ?? const {});
            final cp = Map<String, dynamic>.from((ch['push_7'] as Map?) ?? const {});
            if (ch.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _grid([
                _Stat('${_n(ch, 'sent_24')}', 'Съобщения · 24 ч', Icons.chat_rounded,
                    sub: '${_n(ch, 'sent_7')} за 7 дни (${_n(ch, 'private_7')} лични) · ${_n(ch, 'sent_all')} общо'),
                _Stat('${_n(ch, 'stored')}', 'Пазят се сега', Icons.inventory_rounded,
                    sub: 'изтекли (над 6 месеца): ${_n(ch, 'expired_all')}'),
                _Stat('${_n(ch, 'deleted_7')}', 'Изтрити · 7 дни', Icons.delete_outline_rounded,
                    sub: '${_n(ch, 'deleted_all')} общо · заглушени: ${_n(ch, 'mutes')}'),
                _Stat('${_n(cp, 'delivered')}', 'Известия за чата · 7 дни', Icons.mark_email_read_rounded,
                    color: _n(cp, 'errors') > 0 ? red : green,
                    sub: 'грешки: ${_n(cp, 'errors')} · стари телефони: ${_n(cp, 'stale')} · '
                        'без получател: ${_n(cp, 'no_recipient')}'),
              ]),
            );
          }),
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
          if (u['suspended'] == true)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error, borderRadius: BorderRadius.circular(20)),
              child: Text('СПРЯН',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onError)),
            ),
          Icon(u['push'] == true ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              size: 20, color: u['push'] == true ? p.primary : p.textMuted),
          if (u['id'] != AppScope.of(context).currentUser?.id)
            PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (v) async {
                final s = AppScope.read(context);
                if (v == 'view') {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _ViewAsScreen(userId: u['id'] as String, name: name)));
                } else if (v == 'log') {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _ActivityScreen(title: name, userId: u['id'] as String)));
                } else if (v == 'test') {
                  try {
                    final m = await s.creatorTestPush(u['id'] as String);
                    if (context.mounted) await info(context, 'Пробно известие', m);
                  } on AppError catch (e) {
                    if (context.mounted) showMessage(context, e.message);
                  }
                } else if (v == 'suspend' || v == 'unsuspend') {
                  final on = v == 'suspend';
                  final ok = await confirm(
                      context,
                      on ? 'Временно спиране' : 'Пускане на профила',
                      on
                          ? '$name няма да може да влиза и няма да получава известия, докато не го пуснете. '
                              'Нищо не се трие – данните и записите му остават.'
                          : '$name отново ще може да влиза в Кайрос.',
                      on ? 'Спри' : 'Пусни');
                  if (!ok || !context.mounted) return;
                  try {
                    await s.creatorSuspend(u['id'] as String, on);
                    if (context.mounted) showMessage(context, on ? 'Профилът е спрян.' : 'Профилът е пуснат.');
                    await onRefresh?.call();
                  } on AppError catch (e) {
                    if (context.mounted) showMessage(context, e.message);
                  }
                } else if (v == 'roles') {
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => _RolesSheet(userId: u['id'] as String, name: name),
                  );
                  await onRefresh?.call();
                } else if (v == 'pass') {
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
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'view', child: Text('Какво вижда')),
                const PopupMenuItem(value: 'test', child: Text('Пробно известие')),
                const PopupMenuItem(value: 'log', child: Text('Дневник на действията')),
                const PopupMenuItem(value: 'roles', child: Text('Роли в храмовете')),
                const PopupMenuItem(value: 'pass', child: Text('Временна парола')),
                PopupMenuItem(
                    value: u['suspended'] == true ? 'unsuspend' : 'suspend',
                    child: Text(u['suspended'] == true ? 'Пусни профила' : 'Спри временно')),
                const PopupMenuItem(value: 'delete', child: Text('Изтрий профила')),
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

Future<void> info(BuildContext context, String title, String body) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Добре'))],
      ),
    );

final _when = DateFormat('dd.MM HH:mm');
final _day = DateFormat('EEE dd.MM', 'bg');

// ------------------------------------------------------------ „Какво вижда“

class _ViewAsScreen extends StatefulWidget {
  final String userId;
  final String name;
  const _ViewAsScreen({required this.userId, required this.name});

  @override
  State<_ViewAsScreen> createState() => _ViewAsScreenState();
}

class _ViewAsScreenState extends State<_ViewAsScreen> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AppScope.read(context).creatorViewAs(widget.userId);
      if (mounted) setState(() => _d = d);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final d = _d;
    final muted = TextStyle(fontSize: 14, color: p.textMuted);
    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
          child: Text(t.toUpperCase(),
              style: TextStyle(fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: p.textMuted)),
        );
    Widget row(IconData i, String t, {String? sub, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 20, color: color ?? p.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: color)),
                if (sub != null && sub.isNotEmpty) Text(sub, style: muted),
              ]),
            ),
          ]),
        );
    final warn = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text('Какво вижда ${widget.name}')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                    Text('Само за гледане – нищо не се променя от негово име.', style: muted),
                    head('Телефон и профил'),
                    SurfaceCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (d['suspended_at'] != null) row(Icons.pause_circle_rounded, 'Профилът е спрян', color: warn),
                        row(Icons.phone_android_rounded,
                            d['build'] == null ? 'Версия: още няма данни' : 'Версия ${d['build']} (последна: $buildNumber)',
                            sub: d['seen_at'] == null ? null : 'Последно отваряне: ${_ago(_dt(d['seen_at']))}',
                            color: d['build'] != null && (d['build'] as num) < buildNumber ? warn : null),
                        row(
                            (d['tokens'] as num) > 0 ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                            (d['tokens'] as num) > 0
                                ? 'Известия: записан${(d['tokens'] as num) > 1 ? 'и ${d['tokens']} телефона' : ' телефон'}'
                                : 'Известия: няма записан телефон',
                            color: (d['tokens'] as num) > 0 ? null : warn),
                        if (d['must_change_password'] == true)
                          row(Icons.key_rounded, 'Чака да смени временната парола', color: warn),
                        if (d['privacy_ok'] != true)
                          row(Icons.privacy_tip_rounded, 'Още не е приел текста за личните данни', color: warn),
                      ]),
                    ),
                    head('Храмове'),
                    for (final c in (d['churches'] as List).cast<Map>())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SurfaceCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${c['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                            Text(c['status'] == 'active' ? '${c['role']}' : 'чака одобрение за влизане', style: muted),
                            if ((c['chat_unread'] as num? ?? 0) > 0)
                              row(Icons.chat_rounded, 'Непрочетени в чата: ${c['chat_unread']}'),
                            if ((c['join_pending'] as num? ?? 0) > 0)
                              row(Icons.person_add_rounded, 'Чакат го за влизане в храма: ${c['join_pending']}', color: warn),
                            if ((c['leaves_pending'] as num? ?? 0) > 0)
                              row(Icons.beach_access_rounded, 'Почивки за решаване: ${c['leaves_pending']}', color: warn),
                            if ((c['swaps_pending'] as num? ?? 0) > 0)
                              row(Icons.swap_horiz_rounded, 'Размени за одобрение: ${c['swaps_pending']}', color: warn),
                            if ((c['cash_pending'] as num? ?? 0) > 0)
                              row(Icons.payments_rounded, 'Записи в касата за одобрение: ${c['cash_pending']}', color: warn),
                          ]),
                        ),
                      ),
                    if ((d['churches'] as List).isEmpty) Text('Не е в храм.', style: muted),
                    head('Карти на началния екран'),
                    SurfaceCard(
                      child: Builder(builder: (_) {
                        final cards = Map<String, dynamic>.from(d['cards'] as Map);
                        final ann = (cards['announcements'] as List).cast<String>();
                        final items = <Widget>[
                          for (final t in ann) row(Icons.campaign_rounded, t, sub: 'съобщение – чака „ОК“'),
                          for (final l in (d['leaves'] as List).cast<Map>().where((l) => l['unseen'] == true))
                            row(Icons.beach_access_rounded, 'Решение за почивка ${_range(l)}', sub: 'чака „ОК“'),
                          if ((cards['cash_returned'] as num) > 0)
                            row(Icons.undo_rounded, 'Върнати записи в касата: ${cards['cash_returned']}', sub: 'чакат „ОК“'),
                          if ((cards['to_confirm'] as num) > 0)
                            row(Icons.event_available_rounded, 'Събития за потвърждаване: ${cards['to_confirm']}',
                                color: warn),
                        ];
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: items.isEmpty ? [Text('Няма карти – началният екран е чист.', style: muted)] : items);
                      }),
                    ),
                    head('Събития – следващите 14 дни'),
                    SurfaceCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final e in (d['events'] as List).cast<Map>())
                          row(Icons.event_rounded, '${_day.format(_dt(e['at'])!)} ${DateFormat('HH:mm').format(_dt(e['at'])!)} · ${e['kind']}',
                              sub: [
                                if ((e['for_whom'] as String?)?.isNotEmpty == true) '${e['for_whom']}',
                                '${e['church']}',
                                if (e['mine'] == true) 'записал за колега',
                                if (e['assignment'] == 'pending') 'чака потвърждение',
                                if (e['assignment'] == 'declined') 'отказано',
                              ].join(' · ')),
                        if ((d['events'] as List).isEmpty) Text('Няма предстоящи събития.', style: muted),
                      ]),
                    ),
                    head('Почивки и дежурства'),
                    SurfaceCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final l in (d['leaves'] as List).cast<Map>())
                          row(Icons.beach_access_rounded, 'Почивка ${_range(l)}', sub: switch (l['status']) {
                            'pending' => 'чака решение',
                            'approved' => 'одобрена',
                            'rejected' => 'отказана',
                            'ended' => 'прекратена',
                            _ => '${l['status']}',
                          }),
                        for (final x in (d['duties'] as List).cast<Map>())
                          row(Icons.shield_rounded, 'Дежурство ${_range(x)}', sub: '${x['church']}'),
                        if ((d['leaves'] as List).isEmpty && (d['duties'] as List).isEmpty)
                          Text('Няма почивки и предстоящи дежурства.', style: muted),
                      ]),
                    ),
                  ]),
                ),
    );
  }

  String _range(Map l) {
    final a = DateTime.parse('${l['from']}');
    final b = DateTime.parse('${l['to']}');
    final f = DateFormat('dd.MM');
    return a == b ? f.format(a) : '${f.format(a)} – ${f.format(b)}';
  }
}

// ------------------------------------------------------------ дневник

class _ActivityScreen extends StatefulWidget {
  final String title;
  final String? userId;
  final String? churchId;
  const _ActivityScreen({required this.title, this.userId, this.churchId});

  @override
  State<_ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<_ActivityScreen> {
  List<Map<String, dynamic>>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await AppScope.read(context).creatorActivity(userId: widget.userId, churchId: widget.churchId);
      if (mounted) setState(() => _list = l);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final muted = TextStyle(fontSize: 13.5, color: p.textMuted);
    final l = _list;
    String? lastDay;
    return Scaffold(
      appBar: AppBar(title: Text('Дневник · ${widget.title}')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : l == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                    Text('Пазят се последните 180 дни. Съдържанието на чата не се записва.', style: muted),
                    if (l.isEmpty)
                      const Padding(padding: EdgeInsets.only(top: 24), child: Text('Още няма записани действия.')),
                    for (final a in l) ...(() {
                      final t = _dt(a['at'])!;
                      final day = DateFormat('EEEE, d MMMM', 'bg').format(t);
                      final out = <Widget>[];
                      if (day != lastDay) {
                        lastDay = day;
                        out.add(Padding(
                          padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
                          child: Text(day, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ));
                      }
                      out.add(Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 48, child: Text(DateFormat('HH:mm').format(t), style: muted)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text.rich(TextSpan(children: [
                                TextSpan(
                                    text: a['by_creator'] == true ? 'Вие' : '${a['actor']}',
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                TextSpan(text: ' · ${a['action']}'),
                                if (a['target'] != null) TextSpan(text: ' → ${a['target']}'),
                              ]), style: const TextStyle(fontSize: 15)),
                              Text(
                                  [
                                    if ((a['details'] as String?)?.isNotEmpty == true) '${a['details']}',
                                    if (widget.churchId == null && a['church'] != null) '${a['church']}',
                                  ].join(' · '),
                                  style: muted),
                            ]),
                          ),
                        ]),
                      ));
                      return out;
                    })(),
                  ]),
                ),
    );
  }
}

// ------------------------------------------------------------ каса

class _CashSheet extends StatefulWidget {
  final String churchId;
  final String name;
  const _CashSheet({required this.churchId, required this.name});

  @override
  State<_CashSheet> createState() => _CashSheetState();
}

class _CashSheetState extends State<_CashSheet> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AppScope.read(context).creatorCashOverview(widget.churchId);
      if (mounted) setState(() => _d = d);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _do(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) showMessage(context, done);
      await _load();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _reason() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Връщане на записа'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Причина (по желание)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отказ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Върни')),
        ],
      ),
    );
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final muted = TextStyle(fontSize: 14, color: p.textMuted);
    final d = _d;
    final money = NumberFormat.currency(locale: 'bg', symbol: '€', decimalDigits: 2);
    final monthF = DateFormat('LLLL yyyy', 'bg');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Row(children: [
            Expanded(
              child: Text('Каса – ${widget.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 4),
          Text('Всяко ваше решение остава в историята с бележка „от създателя на Кайрос“. '
              'Председателят и касиерът получават известие.', style: muted),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!)
          else if (d == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else ...[
            const Text('Чакащи записи', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if ((d['pending'] as List).isEmpty) Text('Няма чакащи записи.', style: muted),
            for (final e in (d['pending'] as List).cast<Map>())
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      '${switch (e['book']) { 'income' => 'Приход', 'expense' => 'Разход', _ => 'Движение' }}'
                      '${e['reverses'] == true ? ' (сторно)' : ''} · ${money.format((e['amount'] as num).abs())}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                      [
                        '${e['category']}',
                        if ((e['note'] as String?)?.isNotEmpty == true) '${e['note']}',
                        '${e['by'] ?? '—'} · ${_when.format(_dt(e['at'])!)}',
                      ].join(' · '),
                      style: muted),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final r = await _reason();
                                if (r == null || !mounted) return;
                                final st = AppScope.read(context);
                                await _do(() => st.creatorCashDecide(e['id'] as String, false, r), 'Записът е върнат.');
                              },
                        child: const Text('Върни'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await confirm(context, 'Одобряване',
                                    'Записът влиза в книгата с бележка „одобрен от създателя на Кайрос“.', 'Одобри');
                                if (!ok || !mounted) return;
                                final st = AppScope.read(context);
                                await _do(() => st.creatorCashDecide(e['id'] as String, true, null), 'Записът е одобрен.');
                              },
                        child: const Text('Одобри'),
                      ),
                    ),
                  ]),
                ]),
              ),
            const SizedBox(height: 14),
            const Text('Приключени месеци', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if ((d['periods'] as List).isEmpty) Text('Няма приключени месеци.', style: muted),
            for (final m in (d['periods'] as List).cast<Map>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(monthF.format(DateTime.parse('${m['month']}'))),
                subtitle: Text(m['status'] == 'closed' ? 'приключен' : 'чака одобрение за приключване', style: muted),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await confirm(
                              context,
                              'Отключване на месеца',
                              'Месецът ще може да се поправя. Председателят и касиерът получават известие; '
                                  'след това го приключват отново.',
                              'Отключи');
                          if (!ok || !mounted) return;
                          final st = AppScope.read(context);
                          await _do(() => st.creatorCashReopen(widget.churchId, '${m['month']}'), 'Месецът е отключен.');
                        },
                  child: Text(m['status'] == 'closed' ? 'Отключи' : 'Върни'),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ роли

/// Създателят сменя ролята на човек във всеки негов храм или го изважда от храма.
class _RolesSheet extends StatefulWidget {
  final String userId;
  final String name;
  const _RolesSheet({required this.userId, required this.name});

  @override
  State<_RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<_RolesSheet> {
  List<Map<String, dynamic>>? _list;
  String? _error;
  String? _busy; // church_id, по който се работи

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await AppScope.read(context).creatorUserChurches(widget.userId);
      if (mounted) setState(() => _list = l);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(String church, Future<void> Function() f, String done) async {
    setState(() => _busy = church);
    try {
      await f();
      if (mounted) showMessage(context, done);
      await _load();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setChair(Map<String, dynamic> c) async {
    final other = c['chair_name'] as String?;
    final ok = await confirm(
        context,
        'Нов председател',
        '${widget.name} става председател на „${c['name']}“.'
            '${other != null ? ' $other остава свещеник.' : ''}'
            '${c['cashier'] == true ? ' Председателят не е касиер – правото на касиер се маха.' : ''}'
            ' И двамата получават известие.',
        'Направи председател');
    if (!ok || !mounted) return;
    await _run(c['church_id'] as String,
        () => AppScope.read(context).creatorSetRole(c['church_id'] as String, widget.userId, chair: true, cashier: false),
        'Готово – ${widget.name} е председател.');
  }

  Future<void> _setCashier(Map<String, dynamic> c, bool on) async {
    final other = c['cashier_name'] as String?;
    final ok = await confirm(
        context,
        on ? 'Касиер' : 'Без право на касиер',
        on
            ? '${widget.name} става касиер на „${c['name']}“.${other != null ? ' $other вече няма да е касиер.' : ''}'
                ' Човекът и председателят получават известие.'
            : '${widget.name} вече няма да е касиер на „${c['name']}“. Човекът и председателят получават известие.',
        on ? 'Направи касиер' : 'Махни');
    if (!ok || !mounted) return;
    await _run(
        c['church_id'] as String,
        () => AppScope.read(context).creatorSetRole(c['church_id'] as String, widget.userId, chair: false, cashier: on),
        on ? 'Готово – ${widget.name} е касиер.' : 'Готово – правото на касиер е махнато.');
  }

  Future<void> _remove(Map<String, dynamic> c) async {
    final ok = await confirm(
        context,
        'Изваждане от храма',
        '${widget.name} ще бъде изваден от „${c['name']}“. Вече няма да вижда храма. '
            'Записите му в календара и касата остават. Той и председателят получават известие.',
        'Извади');
    if (!ok || !mounted) return;
    await _run(c['church_id'] as String,
        () => AppScope.read(context).creatorRemoveMember(c['church_id'] as String, widget.userId),
        '${widget.name} е изваден от храма.');
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final muted = TextStyle(fontSize: 14, color: p.textMuted);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text('Роли – ${widget.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Един председател и един касиер на храм. При промяна човекът и председателят получават известие и карта с „ОК“.',
              style: muted),
          const SizedBox(height: 14),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (_list == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_list!.isEmpty)
            Text('Не е в храм.', style: muted)
          else
            for (final c in _list!) ...[
              _churchBox(c, p, muted),
              const SizedBox(height: 12),
            ],
        ]),
      ),
    );
  }

  Widget _churchBox(Map<String, dynamic> c, Palette p, TextStyle muted) {
    final id = c['church_id'] as String;
    final busy = _busy == id;
    final pending = c['status'] != 'active';
    final chair = c['chair'] == true;
    final cashier = c['cashier'] == true;
    final members = (c['members'] as num?)?.toInt() ?? 0;
    final canRemove = !chair || members <= 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${c['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        Text(
            [
              if ((c['settlement'] as String?)?.isNotEmpty == true) '${c['settlement']}',
              if (!chair && c['chair_name'] != null) 'председател: ${c['chair_name']}',
              if (!cashier && c['cashier_name'] != null) 'касиер: ${c['cashier_name']}',
            ].join(' · '),
            style: muted),
        const SizedBox(height: 10),
        if (pending)
          Text('Чака одобрение за влизане – ролята се сменя след това.', style: muted)
        else ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Свещеник')),
              ButtonSegment(value: true, label: Text('Председател')),
            ],
            selected: {chair},
            showSelectedIcon: false,
            onSelectionChanged: busy
                ? null
                : (v) {
                    if (v.first && !chair) {
                      _setChair(c);
                    } else if (!v.first && chair) {
                      showMessage(context, 'Изберете друг човек за председател – тогава този става свещеник.');
                    }
                  },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Касиер'),
            subtitle: Text(chair ? 'Председателят не може да е касиер.' : 'Един касиер на храм.', style: muted),
            value: cashier,
            onChanged: chair || busy ? null : (v) => _setCashier(c, v),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy || !canRemove ? null : () => _remove(c),
            icon: const Icon(Icons.person_remove_rounded),
            label: Text(canRemove ? 'Извади от храма' : 'Извади от храма (първо друг председател)'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          ),
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
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Дневник'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _ActivityScreen(title: '${c['name']}', churchId: c['id'] as String))),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: const Text('Каса – решения'),
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => _CashSheet(churchId: c['id'] as String, name: '${c['name']}'),
                      );
                      await onRefresh();
                    },
                  ),
                ]),
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
