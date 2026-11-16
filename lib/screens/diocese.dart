import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Обвива екран в митрополитската тема (пурпур и злато).
Widget metroTheme(Widget child) => Theme(data: buildTheme(Palette.metro), child: child);

/// Изглед „Епархия“: разделите (градът и духовните околии) → храмовете →
/// свещениците (сан, длъжност, телефон) и търсачка. Без каса, склад,
/// почивки и служби. Какво се вижда решава сървърът според длъжността.
class DioceseScreen extends StatefulWidget {
  final String? dioceseId; // null – моята епархия; създателят подава коя
  final bool embedded; // в митрополитското меню (без собствена горна лента за връщане)
  const DioceseScreen({super.key, this.dioceseId, this.embedded = false});

  @override
  State<DioceseScreen> createState() => _DioceseScreenState();
}

class _DioceseScreenState extends State<DioceseScreen> {
  Map<String, dynamic>? data;
  String? error;
  final _q = TextEditingController();
  String query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await AppScope.read(context).dioceseOverview(widget.dioceseId);
      if (mounted) setState(() => data = d);
    } on AppError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  List<Map<String, dynamic>> _list(Object? v) =>
      (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  String _person(Map<String, dynamic> p) => withRank(ClergyRank.fromCode(p['rank']), '${p['name'] ?? ''}');

  bool get _canAssign {
    final s = AppScope.read(context);
    final id = (data?['diocese'] as Map?)?['id'] as String?;
    return s.isCreator || s.isMetropolitanOf(id);
  }

  Future<void> _assign(Map<String, dynamic> priest, Map<String, dynamic> section) async {
    final s = AppScope.read(context);
    final options = <(StaffRole, String?, String)>[
      (StaffRole.secretary, null, 'Секретар на митрополията'),
      (StaffRole.protosyngel, null, 'Протосингел'),
      if (section['is_center'] != true) (StaffRole.vicar, section['id'] as String, 'Наместник – ${section['name']}'),
    ];
    final pick = await showDialog<(StaffRole, String?, String)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_person(priest)),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(o.$3, style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    try {
      await s.staffSet(priest['user_id'] as String, pick.$1, vicariateId: pick.$2);
      await _load();
      if (mounted) showMessage(context, 'Назначен: ${pick.$3}.');
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _release(Map<String, dynamic> st) async {
    final s = AppScope.read(context);
    final role = StaffRole.fromCode(st['role']);
    if (role == null) return;
    final ok = await confirm(context, 'Освобождаване', '${_person(st)} се освобождава като ${role.label.toLowerCase()}.',
        'Освободи');
    if (!ok || !mounted) return;
    try {
      await s.staffRemove(st['user_id'] as String, role, vicariateId: st['vicariate_id'] as String?);
      await _load();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Widget _priestTile(Map<String, dynamic> pr, Map<String, dynamic> church, Map<String, dynamic> section,
      {bool showChurch = false}) {
    final p = Palette.of(context);
    final phone = (pr['phone'] as String? ?? '').trim();
    final tags = [if (pr['chair'] == true) 'председател', if (pr['cashier'] == true) 'касиер'];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(_person(pr), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text(
          [
            ...tags,
            if (showChurch) '${church['name']} – ${church['settlement']}',
            if (showChurch) '${section['name']}',
          ].join(' · '),
          style: TextStyle(color: p.textMuted)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (phone.isNotEmpty)
          IconButton(
            tooltip: 'Обади се · $phone',
            icon: Icon(Icons.call_rounded, color: p.primary),
            onPressed: () => ContactButtons.call(context, phone),
          ),
        if (_canAssign)
          IconButton(
            tooltip: 'Назначи в митрополията',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _assign(pr, section),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final d = data;
    Widget body;
    if (error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!)));
    } else if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final sections = _list(d['sections']);
      final staff = _list(d['staff']);
      final churches = [for (final s in sections) ..._list(s['churches'])];
      final priestIds = <String>{
        for (final c in churches)
          for (final pr in _list(c['priests'])) pr['user_id'] as String
      };
      final q = query.trim().toLowerCase();
      final children = <Widget>[];
      if (q.isEmpty) {
        // Обобщение
        children.add(Row(children: [
          for (final n in [
            ('${sections.length}', 'раздела'),
            ('${churches.length}', 'храма'),
            ('${priestIds.length}', 'свещеници'),
          ])
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Text(n.$1, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: p.primary)),
                  Text(n.$2, style: TextStyle(fontSize: 13, color: p.textMuted)),
                ]),
              ),
            ),
        ]));
        children.add(const SizedBox(height: 14));
        // Длъжностите
        if (staff.isNotEmpty) {
          children.add(SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('МИТРОПОЛИЯТА',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: p.primary)),
              const SizedBox(height: 6),
              for (final st in staff..sort((a, b) =>
                  (StaffRole.fromCode(a['role'])?.index ?? 9).compareTo(StaffRole.fromCode(b['role'])?.index ?? 9)))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_person(st), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      [
                        StaffRole.fromCode(st['role'])?.label ?? '',
                        if (st['vicariate_id'] != null)
                          sections.where((x) => x['id'] == st['vicariate_id']).firstOrNull?['name'] ??
                              AppScope.read(context).vicariateName(st['vicariate_id'] as String?) ??
                              '',
                      ].where((x) => '$x'.isNotEmpty).join(' · '),
                      style: TextStyle(color: p.textMuted)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if ((st['phone'] as String? ?? '').trim().isNotEmpty)
                      IconButton(
                        tooltip: 'Обади се',
                        icon: Icon(Icons.call_rounded, color: p.primary),
                        onPressed: () => ContactButtons.call(context, st['phone'] as String),
                      ),
                    if (_canAssign && st['role'] != 'metropolitan')
                      IconButton(
                        tooltip: 'Освободи',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => _release(st),
                      ),
                  ]),
                ),
            ]),
          ));
          children.add(const SizedBox(height: 14));
        }
        // Разделите
        for (final sec in sections) {
          final cs = _list(sec['churches']);
          final vicar = staff.where((x) => x['role'] == 'vicar' && x['vicariate_id'] == sec['id']).firstOrNull;
          final head = sec['is_center'] == true
              ? staff.where((x) => x['role'] == 'protosyngel').firstOrNull
              : vicar;
          children.add(Card(
            color: p.surface,
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              shape: const Border(),
              title: Text('${sec['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              subtitle: Text(
                  [
                    '${cs.length} ${cs.length == 1 ? 'храм' : 'храма'}',
                    if (head != null)
                      '${sec['is_center'] == true ? 'протосингел' : 'наместник'}: ${_person(head)}',
                  ].join(' · '),
                  style: TextStyle(color: p.textMuted)),
              children: [
                if (cs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text('Още няма храмове в Кайрос.', style: TextStyle(color: p.textMuted)),
                  ),
                for (final c in cs)
                  ExpansionTile(
                    shape: const Border(),
                    tilePadding: const EdgeInsets.only(left: 24, right: 16),
                    leading: Icon(Icons.church_outlined, color: p.primary),
                    title: Text('${c['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        [
                          '${c['settlement']}',
                          '${_list(c['priests']).length} свещ.',
                        ].join(' · '),
                        style: TextStyle(color: p.textMuted)),
                    children: [
                      for (final pr in _list(c['priests'])) _priestTile(pr, c, sec),
                      if ((c['address'] as String? ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
                          child: Text('${c['address']}', style: TextStyle(color: p.textMuted)),
                        ),
                    ],
                  ),
              ],
            ),
          ));
        }
      } else {
        // Търсене: хора и храмове
        final hits = <Widget>[];
        for (final sec in sections) {
          for (final c in _list(sec['churches'])) {
            final cText = '${c['name']} ${c['settlement']} ${sec['name']}'.toLowerCase();
            if (cText.contains(q)) {
              hits.add(ListTile(
                leading: Icon(Icons.church_outlined, color: p.primary),
                title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${c['settlement']} · ${sec['name']}', style: TextStyle(color: p.textMuted)),
              ));
            }
            for (final pr in _list(c['priests'])) {
              final role = [if (pr['chair'] == true) 'председател', if (pr['cashier'] == true) 'касиер'].join(' ');
              final pText = '${_person(pr)} $role ${pr['phone'] ?? ''}'.toLowerCase();
              if (pText.contains(q) || cText.contains(q)) hits.add(_priestTile(pr, c, sec, showChurch: true));
            }
          }
        }
        for (final st in staff) {
          final t = '${_person(st)} ${StaffRole.fromCode(st['role'])?.label ?? ''}'.toLowerCase();
          if (t.contains(q)) {
            hits.insert(
                0,
                ListTile(
                  leading: Icon(Icons.account_balance_outlined, color: p.primary),
                  title: Text(_person(st), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(StaffRole.fromCode(st['role'])?.label ?? '', style: TextStyle(color: p.textMuted)),
                ));
          }
        }
        children.add(Text(hits.isEmpty ? 'Няма намерени.' : '${hits.length} намерени',
            style: TextStyle(color: p.textMuted)));
        children.addAll(hits);
      }
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          TextField(
            controller: _q,
            decoration: InputDecoration(
              hintText: 'Търсене: име, сан, длъжност, храм, село, околия…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _q.clear();
                        query = '';
                      })),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 14),
          ...children,
        ]),
      );
    }
    final title = (d?['diocese'] as Map?)?['name'] as String? ?? 'Епархия';
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: !widget.embedded),
      body: body,
    );
  }
}
