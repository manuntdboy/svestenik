import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/desk_chrome.dart';
import 'metro_cabinet.dart';

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

  void _openChurch(Map<String, dynamic> c) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Theme(
              data: Theme.of(context),
              child: DioceseChurchScreen(churchId: '${c['id']}', title: '${c['name']}'))));

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

  Future<void> _addEmployee() async {
    final d = (data?['diocese'] as Map?)?['id'] as String?;
    if (d == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => _AddStaffDialog(dioceseId: d));
    if (ok != true || !mounted) return;
    await _load();
    if (mounted) showMessage(context, 'Добавен в администрацията.');
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

  String? _section; // избраният раздел в изгледа на компютър

  /// Компютър: отляво обобщението и разделите, отдясно таблица със
  /// свещениците на избрания раздел.
  Widget _wideBody(List<Map<String, dynamic>> sections, List<Map<String, dynamic>> staff, List<Widget> head,
      Widget searchField) {
    final p = Palette.of(context);
    final s = AppScope.read(context);
    if (sections.isEmpty) return Center(child: Text('Още няма раздели.', style: TextStyle(color: p.textMuted)));
    final sel = sections.where((x) => x['id'] == _section).firstOrNull ?? sections.first;
    Map<String, dynamic>? headOf(Map<String, dynamic> sec) => sec['is_center'] == true
        ? staff.where((x) => x['role'] == 'protosyngel').firstOrNull
        : staff.where((x) => x['role'] == 'vicar' && x['vicariate_id'] == sec['id']).firstOrNull;
    final cs = _list(sel['churches']);
    final rows = <List<Widget>>[];
    final taps = <VoidCallback?>[];
    for (final c in cs) {
      final prs = _list(c['priests']);
      for (final pr in prs.isEmpty ? [<String, dynamic>{}] : prs) {
        final phone = '${pr['phone'] ?? ''}'.trim();
        final badge = pr['user_id'] == null ? null : s.staffBadge(pr['user_id'] as String);
        rows.add([
          Text(pr.isEmpty ? '—' : _person(pr), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${c['name']}'),
          Text('${c['settlement']}'),
          Text([if (pr['chair'] == true) 'председател', if (pr['cashier'] == true) 'касиер'].join(', ')),
          badge == null
              ? const SizedBox.shrink()
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(7)),
                  child: Text(badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.primary)),
                ),
          phone.isEmpty
              ? Text('—', style: TextStyle(color: p.textMuted))
              : SelectableText(phone, style: TextStyle(fontWeight: FontWeight.w700, color: p.primary)),
        ]);
        taps.add(() => _openChurch(c));
      }
    }
    final h = headOf(sel);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 380,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 10, 32), children: [
            searchField,
            const SizedBox(height: 14),
            ...head,
            for (final sec in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: p.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: sec == sel ? p.primary : p.border, width: sec == sel ? 2 : 1)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() => _section = sec['id'] as String?),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${sec['name']}', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                        Text(
                            [
                              if (headOf(sec) != null)
                                '${sec['is_center'] == true ? 'протосингел' : 'наместник'}: ${_person(headOf(sec)!)}',
                              '${_list(sec['churches']).length} храма',
                            ].join(' · '),
                            style: TextStyle(fontSize: 12.5, color: p.textMuted)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(10, 16, 20, 32), children: [
          Text('${sel['name']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(
              [
                if (h != null) '${sel['is_center'] == true ? 'Протосингел' : 'Наместник'}: ${_person(h)}',
                '${cs.length} храма',
                '${rows.where((r) => (r.first as Text).data != '—').length} свещеници',
              ].join(' · '),
              style: TextStyle(color: p.textMuted)),
          const SizedBox(height: 14),
          if (cs.isEmpty)
            Text('Още няма храмове в Кайрос.', style: TextStyle(color: p.textMuted))
          else
            DeskTable(
              columns: const [
                ('Свещеник', 3),
                ('Храм', 3),
                ('Населено място', 2),
                ('В храма', 2),
                ('Митрополия', 2),
                ('Телефон', 2),
              ],
              rows: rows,
              onTap: taps,
            ),
          const SizedBox(height: 10),
          Text('Ред → дежурствата, адресът и пътят до храма. Касата, складът и почивките не се виждат.',
              style: TextStyle(fontSize: 12.5, color: p.textMuted)),
        ]),
      ),
    ]);
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
      var headCount = -1; // докъде е обобщението (за изгледа на компютър)
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
                        StaffRole.fromCode(st['role']) == StaffRole.employee
                            ? (AppScope.read(context)
                                    .staffOf(st['user_id'] as String)
                                    .where((e) => e.role == StaffRole.employee)
                                    .firstOrNull
                                    ?.title ??
                                'Служител')
                            : StaffRole.fromCode(st['role'])?.label ?? '',
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
              if (_canAssign)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                    label: const Text('Добави човек в администрацията (секретар, служител…)'),
                    onPressed: _addEmployee,
                  ),
                ),
            ]),
          ));
          children.add(const SizedBox(height: 14));
        }
        headCount = children.length;
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
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 24, right: 16),
                        leading: Icon(Icons.shield_outlined, color: p.primary),
                        title: const Text('Дежурства, адрес и път до храма'),
                        subtitle: (c['address'] as String? ?? '').trim().isEmpty
                            ? null
                            : Text('${c['address']}', style: TextStyle(color: p.textMuted)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openChurch(c),
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
                onTap: () => _openChurch(c),
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
      final searchField = TextField(
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
      );
      final wide = MediaQuery.sizeOf(context).width >= 1200;
      body = wide && headCount >= 0
          ? _wideBody(sections, staff, children.sublist(0, headCount), searchField)
          : RefreshIndicator(
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


/// „Човек в администрацията“: длъжност, търсене по име или телефон сред
/// регистрираните в епархията, и (за служител) какво работи.
class _AddStaffDialog extends StatefulWidget {
  final String dioceseId;
  const _AddStaffDialog({required this.dioceseId});

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  var role = StaffRole.employee;
  final title = TextEditingController();
  List<Map<String, dynamic>> hits = [];
  Map<String, dynamic>? picked;
  String q = '';
  bool loading = false;
  bool busy = false;
  int _seq = 0;

  static const _roleNames = {
    'metropolitan': 'митрополит',
    'secretary': 'секретар',
    'protosyngel': 'протосингел',
    'vicar': 'наместник',
    'employee': 'служител',
  };

  Future<void> _search(String v) async {
    q = v;
    final my = ++_seq;
    if (v.trim().length < 2) {
      setState(() => hits = []);
      return;
    }
    setState(() => loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (my != _seq || !mounted) return;
    try {
      final r = await AppScope.read(context).staffCandidates(widget.dioceseId, v);
      if (my == _seq && mounted) setState(() => hits = r);
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
    if (my == _seq && mounted) setState(() => loading = false);
  }

  Future<void> _add() async {
    final x = picked;
    if (x == null) return;
    setState(() => busy = true);
    try {
      await AppScope.read(context).staffAddByUsername(widget.dioceseId, '${x['username']}', role,
          title: role == StaffRole.employee ? title.text : null);
      if (mounted) Navigator.pop(context, true);
    } on AppError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showMessage(context, e.message);
      }
    }
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AlertDialog(
      title: const Text('Човек в администрацията'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<StaffRole>(
              initialValue: role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Длъжност'),
              items: const [
                DropdownMenuItem(value: StaffRole.secretary, child: Text('Секретар')),
                DropdownMenuItem(value: StaffRole.protosyngel, child: Text('Протосингел')),
                DropdownMenuItem(
                    value: StaffRole.employee,
                    child: Text('Служител (шофьор, счетоводител…)', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => role = v ?? StaffRole.employee),
            ),
            const SizedBox(height: 12),
            if (picked == null) ...[
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Търсене: име или телефон',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : null,
                ),
                onChanged: _search,
              ),
              const SizedBox(height: 8),
              if (q.trim().length >= 2 && !loading && hits.isEmpty)
                Text('Няма намерени. Човекът трябва да е регистриран в Кайрос с тази епархия.',
                    style: TextStyle(color: p.textMuted)),
              if (q.trim().length < 2)
                Text('Пишете поне 2 букви от името или 3 цифри от телефона.', style: TextStyle(color: p.textMuted)),
              for (final x in hits)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: p.chipBg,
                    child: Text('${x['name'] ?? '?'}'.characters.first, style: TextStyle(color: p.primary)),
                  ),
                  title: Text(withRank(ClergyRank.fromCode(x['rank']), '${x['name'] ?? ''}'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      [
                        if ((x['church'] ?? '').toString().isNotEmpty) '${x['church']}',
                        if ((x['phone'] ?? '').toString().isNotEmpty) '${x['phone']}',
                        if ((x['staff'] ?? '').toString().isNotEmpty)
                          'вече: ${'${x['staff']}'.split(',').map((r) => _roleNames[r] ?? r).join(', ')}',
                      ].join(' · '),
                      style: TextStyle(color: p.textMuted)),
                  onTap: () => setState(() => picked = x),
                ),
            ] else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.primary, width: 2)),
                child: Row(children: [
                  Icon(Icons.check_circle_rounded, color: p.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(withRank(ClergyRank.fromCode(picked!['rank']), '${picked!['name'] ?? ''}'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if ((picked!['church'] ?? '').toString().isNotEmpty)
                        Text('${picked!['church']}', style: TextStyle(color: p.textMuted)),
                    ]),
                  ),
                  TextButton(onPressed: () => setState(() => picked = null), child: const Text('Друг')),
                ]),
              ),
            if (role == StaffRole.employee) ...[
              const SizedBox(height: 12),
              TextField(
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Какво работи', hintText: 'Шофьор'),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отказ')),
        FilledButton(onPressed: picked == null || busy ? null : _add, child: const Text('Добави')),
      ],
    );
  }
}
