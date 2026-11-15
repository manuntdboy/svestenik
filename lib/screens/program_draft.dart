import 'package:flutter/material.dart';

import '../data/print_page.dart';
import '../data/program_doc.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// „Програма (проба)“ – само в компютърната версия, само за създателя.
/// Попълва се програма за архиерейско служение и се отваря като документ
/// за печат във вида на бланката. Нищо не се записва и не се изпраща.
class ProgramDraftScreen extends StatefulWidget {
  const ProgramDraftScreen({super.key});

  @override
  State<ProgramDraftScreen> createState() => _ProgramDraftScreenState();
}

class _ProgramDraftScreenState extends State<ProgramDraftScreen> {
  ProgramDoc doc = ProgramDoc.sample();
  int _rev = 0; // при „Нова празна“ полетата се създават наново

  void _print() {
    if (!openPrintPage(programHtml(doc))) {
      showMessage(context, 'Браузърът спря новия раздел – разрешете изскачащите прозорци за Кайрос.');
    }
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

  Widget _people(List<ProgramPerson> people, {required bool roles}) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < people.length; i++)
        Padding(
          key: ObjectKey(people[i]),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 28, child: Text('${i + 1}.', style: TextStyle(color: p.textMuted))),
            Expanded(
                flex: 3,
                child: _field('Сан и име', people[i].name, (v) => people[i].name = v,
                    hint: 'Иконом Иван Иванов')),
            if (roles) ...[
              const SizedBox(width: 8),
              Expanded(
                  flex: 2,
                  child: _field('Роля (по желание)', people[i].role, (v) => people[i].role = v,
                      hint: 'шофьор')),
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

  Widget _group(int i) {
    final g = doc.groups[i];
    return KeyedSubtree(
      key: ObjectKey(g),
      child: _card(
        '${groupOrdinal(i)} група · ${g.count} души',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _field('Час', g.time, (v) => g.time = v, width: 110, hint: '08:30'),
            _field('Превозно средство', g.vehicle, (v) => g.vehicle = v, width: 200, hint: 'микробус'),
            _field('Марка', g.brand, (v) => g.brand = v, width: 160, hint: 'Мерцедес'),
            _field('Рег. №', g.reg, (v) => g.reg = v, width: 150, hint: 'СТ1234АВ'),
            FilterChip(
              label: const Text('Владиката пътува тук'),
              selected: g.withBishop,
              onSelected: (v) => setState(() => g.withBishop = v),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field('Откъде', g.from, (v) => g.from = v, hint: 'Старозагорска митрополия')),
            const SizedBox(width: 10),
            Expanded(child: _field('Закъде', g.to, (v) => g.to = v, hint: 'храм „…“ – с. …')),
          ]),
          const SizedBox(height: 12),
          Text(g.withBishop ? 'Придружават го:' : 'Пътуват:',
              style: const TextStyle(fontWeight: FontWeight.w700)),
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
                : () => setState(() {
                      final x = doc.groups.removeAt(i);
                      doc.groups.insert(i - 1, x);
                    }),
          ),
          IconButton(
            tooltip: 'Махни групата',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => setState(() => doc.groups.removeAt(i)),
          ),
        ],
      ),
    );
  }

  Widget _list(int i) {
    final l = doc.lists[i];
    return KeyedSubtree(
      key: ObjectKey(l),
      child: _card(
        'Допълнителен списък',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('Заглавие', l.title, (v) => l.title = v,
              hint: 'Списък на гостите поканени на официалния обяд'),
          const SizedBox(height: 10),
          _people(l.people, roles: false),
        ]),
        actions: [
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
    final date = '${doc.date.day.toString().padLeft(2, '0')}.${doc.date.month.toString().padLeft(2, '0')}.${doc.date.year}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Програма (проба)'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Нова празна'),
            onPressed: () => setState(() {
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
            decoration: BoxDecoration(
                color: Palette.yellow.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
            child: Text(
                'Проба: нищо не се записва и не се изпраща. Попълнете и натиснете „Документ за печат“ – '
                'отваря се в нов раздел, откъдето се печата или запазва като PDF. Без подпис и печат – '
                'те се слагат на ръка.',
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
                  icon: const Icon(Icons.event_rounded),
                  label: Text('$date · ${weekdayBg(doc.date)}'),
                  onPressed: _pickDate,
                ),
                const Spacer(),
                Text('Общо пътуващи: ${doc.total}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          for (var i = 0; i < doc.groups.length; i++) _group(i),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.directions_car_rounded),
              label: const Text('Добави група (кола)'),
              onPressed: () => setState(() => doc.groups.add(ProgramGroup(people: [ProgramPerson('')]))),
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < doc.lists.length; i++) _list(i),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Добави списък (служещи, гости на обяд…)'),
              onPressed: () => setState(() => doc.lists.add(ProgramList('', [ProgramPerson('')]))),
            ),
          ),
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
