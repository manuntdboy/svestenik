import 'package:flutter/material.dart';

import '../data/print_page.dart';
import '../data/program_doc.dart';
import '../data/program_memory.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// „Програма (проба)“ – само в компютърната версия, само за създателя.
/// Попълва се програма за архиерейско служение и се отваря като документ
/// за печат във вида на бланката. Нищо не отива в базата: хората и колите
/// се помнят само в този браузър, за да се подсказват следващия път.
class ProgramDraftScreen extends StatefulWidget {
  const ProgramDraftScreen({super.key});

  @override
  State<ProgramDraftScreen> createState() => _ProgramDraftScreenState();
}

class _ProgramDraftScreenState extends State<ProgramDraftScreen> {
  ProgramDoc doc = ProgramDoc.sample();
  final mem = ProgramMemory();
  // Темата прави бутоните широки колкото екрана – тук са по съдържанието.
  static final _btn = OutlinedButton.styleFrom(minimumSize: const Size(0, 44));
  int _rev = 0; // „Нова празна“ – всички полета наново
  final _grev = Expando<int>(); // смяна на кола отвън – полетата на групата наново
  final _tc = Expando<TextEditingController>(); // часовете

  @override
  void initState() {
    super.initState();
    mem.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _print() {
    mem.learn(doc);
    mem.save();
    if (!openPrintPage(programHtml(doc))) {
      showMessage(context, 'Браузърът спря новия раздел – разрешете изскачащите прозорци за Кайрос.');
    }
  }

  /// Групите, които „наследяват“ часа, показват часа на предишната.
  void _syncTimes() {
    final t = doc.times;
    for (var i = 0; i < doc.groups.length; i++) {
      final g = doc.groups[i];
      final c = _tc[g];
      if (c != null && !(i == 0 || g.timeManual) && c.text != t[i]) c.text = t[i];
    }
  }

  void _change(VoidCallback f) {
    setState(f);
    _syncTimes();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: doc.date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => doc.date = d);
  }

  Widget _field(String label, String value, ValueChanged<String> on,
      {double? width, String? hint, int maxLines = 1, Key? key}) {
    final f = TextFormField(
      key: key,
      initialValue: value,
      maxLines: maxLines,
      minLines: 1,
      decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      onChanged: (v) => setState(() => on(v)),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }

  /// Списък с подсказки под поле.
  Widget _options<T extends Object>(
      AutocompleteOnSelected<T> onSelected, Iterable<T> options, Widget Function(T) row) {
    final p = Palette.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300, maxWidth: 420),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final o in options)
                InkWell(
                  onTap: () => onSelected(o),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: row(o)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankBox(ProgramPerson person) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String>(
        key: ValueKey('r${identityHashCode(person)}-${person.rev}'),
        initialValue: programRanks.contains(person.rank) ? person.rank : '',
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Сан', isDense: true),
        items: [
          for (final r in programRanks) DropdownMenuItem(value: r, child: Text(r.isEmpty ? 'без сан' : r)),
        ],
        onChanged: (v) => setState(() => person.rank = v ?? ''),
      ),
    );
  }

  Widget _nameBox(ProgramPerson person, {required bool roles}) {
    final p = Palette.of(context);
    return Autocomplete<KnownPerson>(
      key: ValueKey('n${identityHashCode(person)}-${person.rev}'),
      initialValue: TextEditingValue(text: person.name),
      optionsBuilder: (v) => mem.findPeople(v.text),
      displayStringForOption: (k) => k.name,
      onSelected: (k) => setState(() {
        person.name = k.name;
        person.rank = k.rank;
        if (roles && person.role.trim().isEmpty) person.role = k.role;
        person.rev++;
      }),
      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        decoration: const InputDecoration(labelText: 'Име и фамилия', hintText: 'пишете няколко букви', isDense: true),
        onChanged: (v) => setState(() => person.name = v),
        onSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (ctx, onSel, opts) => _options<KnownPerson>(
        onSel,
        opts,
        (k) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (k.role.isNotEmpty) Text(k.role, style: TextStyle(fontSize: 13, color: p.textMuted)),
        ]),
      ),
    );
  }

  Widget _roleBox(ProgramPerson person) {
    return Autocomplete<String>(
      key: ValueKey('o${identityHashCode(person)}-${person.rev}'),
      initialValue: TextEditingValue(text: person.role),
      optionsBuilder: (v) {
        final t = v.text.trim().toLowerCase();
        return programRoles.where((r) => t.isEmpty || r.contains(t));
      },
      onSelected: (r) => setState(() => person.role = r),
      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        decoration: const InputDecoration(
            labelText: 'Роля (по желание)', isDense: true, suffixIcon: Icon(Icons.arrow_drop_down_rounded)),
        onChanged: (v) => setState(() => person.role = v),
        onSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (ctx, onSel, opts) => _options<String>(onSel, opts, (r) => Text(r)),
    );
  }

  Widget _people(List<ProgramPerson> people, {required bool roles}) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < people.length; i++)
        Padding(
          key: ObjectKey(people[i]),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SizedBox(width: 28, child: Text('${i + 1}.', style: TextStyle(color: p.textMuted))),
            _rankBox(people[i]),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _nameBox(people[i], roles: roles)),
            if (roles) ...[
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _roleBox(people[i])),
            ],
            IconButton(
              tooltip: 'Нагоре',
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              onPressed: i == 0
                  ? null
                  : () => setState(() {
                        final x = people.removeAt(i);
                        people.insert(i - 1, x);
                      }),
            ),
            IconButton(
              tooltip: 'Махни',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => setState(() => people.removeAt(i)),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.person_add_alt_rounded, size: 18),
          label: const Text('Добави човек'),
          onPressed: () => setState(() => people.add(ProgramPerson(''))),
        ),
      ),
    ]);
  }

  Widget _card(String title, Widget child, {List<Widget> actions = const []}) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ...actions,
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  /// Избрана запомнена кола: попълва вида, марката, номера и обичайния шофьор.
  void _pickCar(ProgramGroup g, KnownCar c) {
    _change(() {
      g.vehicle = c.vehicle;
      g.brand = c.brand;
      g.reg = c.reg;
      _grev[g] = (_grev[g] ?? 0) + 1;
      final drv = c.driver.trim();
      if (drv.isNotEmpty) {
        final known = mem.people[drv.toLowerCase()];
        final cur = g.people.where((p) => p.role.trim() == 'шофьор').firstOrNull;
        if (cur != null) {
          cur
            ..name = drv
            ..rank = known?.rank ?? ''
            ..rev += 1;
        } else {
          g.people.removeWhere((p) => p.name.trim().isEmpty);
          g.people.add(ProgramPerson(drv, rank: known?.rank ?? '', role: 'шофьор'));
        }
      }
    });
  }

  Widget _carPicker(ProgramGroup g) {
    final p = Palette.of(context);
    return Autocomplete<KnownCar>(
      key: ValueKey('c${identityHashCode(g)}-${_grev[g] ?? 0}'),
      optionsBuilder: (v) => mem.findCars(v.text),
      displayStringForOption: (c) => c.label,
      onSelected: (c) => _pickCar(g, c),
      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        decoration: InputDecoration(
          labelText: mem.cars.isEmpty ? 'Запомнени коли (още няма)' : 'Избери запомнена кола',
          hintText: 'марка или номер',
          isDense: true,
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        onSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (ctx, onSel, opts) => _options<KnownCar>(
        onSel,
        opts,
        (c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (c.driver.isNotEmpty) Text('шофьор: ${c.driver}', style: TextStyle(fontSize: 13, color: p.textMuted)),
        ]),
      ),
    );
  }

  Widget _group(int i) {
    final g = doc.groups[i];
    final times = doc.times;
    final inherits = i > 0 && !g.timeManual;
    final ctrl = _tc[g] ??= TextEditingController(text: times[i]);
    final rev = _grev[g] ?? 0;
    final regKey = g.reg.trim().toUpperCase().replaceAll(' ', '');
    final dupAt = regKey.isEmpty
        ? -1
        : doc.groups.indexWhere((o) => o != g && o.reg.trim().toUpperCase().replaceAll(' ', '') == regKey);
    return KeyedSubtree(
      key: ObjectKey(g),
      child: _card(
        '${groupOrdinal(i)} група · ${g.count} души',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: 'Час',
                  hintText: '08:30',
                  isDense: true,
                  helperText: inherits ? 'като предишната' : null,
                  suffixIcon: i > 0 && g.timeManual
                      ? IconButton(
                          tooltip: 'Като предишната група',
                          icon: const Icon(Icons.undo_rounded, size: 18),
                          onPressed: () => _change(() => g.timeManual = false),
                        )
                      : null,
                ),
                onChanged: (v) => _change(() {
                  g.time = v;
                  if (i > 0) g.timeManual = true;
                }),
              ),
            ),
            SizedBox(width: 300, child: _carPicker(g)),
            FilterChip(
              label: const Text('Владиката пътува тук'),
              selected: g.withBishop,
              onSelected: (v) => setState(() => g.withBishop = v),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _field('Превозно средство', g.vehicle, (v) => g.vehicle = v,
                width: 200, hint: 'микробус', key: ValueKey('v$rev')),
            _field('Марка', g.brand, (v) => g.brand = v, width: 170, hint: 'Мерцедес', key: ValueKey('b$rev')),
            _field('Рег. №', g.reg, (v) => g.reg = v, width: 160, hint: 'СТ1234АВ', key: ValueKey('g$rev')),
          ]),
          if (dupAt >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Внимание: тази кола е вече в ${groupOrdinal(dupAt)} група.',
                  style: const TextStyle(color: Color(0xFFD0605A), fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field('Откъде', g.from, (v) => g.from = v, hint: 'Старозагорска митрополия')),
            const SizedBox(width: 10),
            Expanded(child: _field('Закъде', g.to, (v) => g.to = v, hint: 'храм „…“ – с. …')),
          ]),
          const SizedBox(height: 12),
          Text(g.withBishop ? 'Придружават го:' : 'Пътуват:', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _people(g.people, roles: true),
          _field('Забележка към групата (по желание)', g.note, (v) => g.note = v, maxLines: 3),
        ]),
        actions: [
          IconButton(
            tooltip: 'Групата нагоре',
            icon: const Icon(Icons.arrow_upward_rounded),
            onPressed: i == 0
                ? null
                : () => _change(() {
                      final x = doc.groups.removeAt(i);
                      doc.groups.insert(i - 1, x);
                    }),
          ),
          IconButton(
            tooltip: 'Махни групата',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _change(() => doc.groups.removeAt(i)),
          ),
        ],
      ),
    );
  }

  /// Всички пътуващи (владиката пръв), без повторения и без вече вписаните.
  List<ProgramPerson> _travellers(ProgramList l) {
    final have = l.people.map((p) => p.fullName).toSet();
    final cand = <ProgramPerson>[];
    final seen = <String>{};
    if (doc.groups.any((g) => g.withBishop) && doc.bishopName.trim().isNotEmpty) {
      cand.add(ProgramPerson(doc.bishopName.trim().toUpperCase(), rank: 'Митрополит'));
    }
    for (final g in doc.groups) {
      for (final p in g.people) {
        if (p.name.trim().isEmpty) continue;
        cand.add(ProgramPerson(p.name.trim(), rank: p.rank));
      }
    }
    cand.retainWhere((p) => seen.add(p.fullName) && !have.contains(p.fullName));
    return cand;
  }

  /// „Списък на служещите“ – попълнен веднъж с всички със сан
  /// (без тези, които преди сте махали от служещите).
  void _addServingList() {
    final l = ProgramList('Списък на служещите … от … часа.');
    l.people.addAll(_travellers(l)
        .where((p) => p.rank == 'Митрополит' || (p.clergy && mem.servesByDefault(p)))
        .map((p) => ProgramPerson(p.name, rank: p.rank)));
    if (l.people.isEmpty) l.people.add(ProgramPerson(''));
    setState(() => doc.lists.add(l));
  }

  /// „Добави от пътуващите“ – отметки, предложени по сана и по миналите избори.
  Future<void> _addFromTravellers(ProgramList l) async {
    final cand = _travellers(l);
    if (cand.isEmpty) {
      showMessage(context, 'Всички пътуващи вече са в списъка.');
      return;
    }
    final on = {for (final p in cand) p: p.rank == 'Митрополит' || mem.servesByDefault(p)};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Добави от пътуващите'),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              for (final p in cand)
                CheckboxListTile(
                  dense: true,
                  value: on[p],
                  title: Text(p.fullName),
                  onChanged: (v) => set(() => on[p] = v ?? false),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добави')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      l.people.removeWhere((p) => p.name.trim().isEmpty);
      for (final p in cand) {
        if (on[p] == true) l.people.add(ProgramPerson(p.name, rank: p.rank));
        if (p.rank == 'Митрополит') continue;
        final key = p.name.trim().toLowerCase();
        final k = mem.people[key] ?? KnownPerson(p.name.trim(), rank: p.rank);
        k.serves = on[p];
        mem.people[key] = k;
      }
    });
    mem.save();
  }

  Widget _list(int i) {
    final l = doc.lists[i];
    return KeyedSubtree(
      key: ObjectKey(l),
      child: _card(
        'Допълнителен списък',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('Заглавие', l.title, (v) => l.title = v, hint: 'Списък на гостите поканени на официалния обяд'),
          const SizedBox(height: 10),
          _people(l.people, roles: false),
        ]),
        actions: [
          OutlinedButton.icon(
            style: _btn,
            icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
            label: const Text('Добави от пътуващите'),
            onPressed: () => _addFromTravellers(l),
          ),
          IconButton(
            tooltip: 'Махни списъка',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => setState(() => doc.lists.removeAt(i)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final date =
        '${doc.date.day.toString().padLeft(2, '0')}.${doc.date.month.toString().padLeft(2, '0')}.${doc.date.year}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Програма (проба)'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Нова празна'),
            onPressed: () => _change(() {
              doc = ProgramDoc(
                bishopTitle: doc.bishopTitle,
                bishopName: doc.bishopName,
                honorific: doc.honorific,
                date: DateTime.now(),
                groups: [ProgramGroup(withBishop: true, people: [ProgramPerson('')])],
              );
              _rev++;
            }),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Документ за печат'),
              onPressed: _print,
            ),
          ),
        ],
      ),
      body: KeyedSubtree(
        key: ValueKey(_rev),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration:
                BoxDecoration(color: Palette.yellow.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
            child: Text(
                'Проба: нищо не отива в базата и не се изпраща. Хората и колите се запомнят само в този браузър '
                '(${mem.people.length} души, ${mem.cars.length} коли), когато натиснете „Документ за печат“. '
                'Без подпис и печат – те се слагат на ръка.',
                style: TextStyle(fontSize: 14, color: p.textMuted)),
          ),
          _card(
            'Повод и дата',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: _field('Титла', doc.bishopTitle, (v) => doc.bishopTitle = v)),
                const SizedBox(width: 10),
                SizedBox(width: 200, child: _field('Име на владиката', doc.bishopName, (v) => doc.bishopName = v)),
              ]),
              const SizedBox(height: 10),
              _field('Обръщение', doc.honorific, (v) => doc.honorific = v),
              const SizedBox(height: 10),
              _field('Повод', doc.occasion, (v) => doc.occasion = v,
                  maxLines: 3, hint: 'при посещението му в храм „…“ – с. …, … духовна околия.'),
              const SizedBox(height: 10),
              Row(children: [
                OutlinedButton.icon(
            style: _btn,
                  icon: const Icon(Icons.event_rounded),
                  label: Text('$date · ${weekdayBg(doc.date)}'),
                  onPressed: _pickDate,
                ),
                const Spacer(),
                Text('Общо пътуващи: ${doc.total}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          for (var i = 0; i < doc.groups.length; i++) _group(i),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
            style: _btn,
              icon: const Icon(Icons.directions_car_rounded),
              label: const Text('Добави група (кола)'),
              onPressed: () => _change(() => doc.groups.add(ProgramGroup(people: [ProgramPerson('')]))),
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < doc.lists.length; i++) _list(i),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
              style: _btn,
              icon: const Icon(Icons.groups_rounded),
              label: const Text('Списък на служещите'),
              onPressed: _addServingList,
            ),
            OutlinedButton.icon(
              style: _btn,
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Друг списък (гости на обяд…)'),
              onPressed: () => setState(() => doc.lists.add(ProgramList('', [ProgramPerson('')]))),
            ),
          ]),
          const SizedBox(height: 18),
          _card(
            'Забележки и изготвил',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < doc.notes.length; i++)
                Padding(
                  key: ObjectKey('n$i${doc.notes.length}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(child: _field('Забележка', doc.notes[i], (v) => doc.notes[i] = v, maxLines: 3)),
                    IconButton(
                      tooltip: 'Махни',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() => doc.notes.removeAt(i)),
                    ),
                  ]),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Добави забележка'),
                  onPressed: () => setState(() => doc.notes.add('')),
                ),
              ),
              const SizedBox(height: 8),
              _field('Изготвил (име)', doc.preparedBy, (v) => doc.preparedBy = v, width: 320),
            ]),
          ),
        ]),
      ),
    );
  }
}
