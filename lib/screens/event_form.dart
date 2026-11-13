import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/notifier.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Един и същ формуляр за ново събитие и за редакция.
class EventFormScreen extends StatefulWidget {
  final ChurchEvent draft;
  final bool editing;
  final bool copying;
  const EventFormScreen(
      {super.key, required this.draft, this.editing = false, this.copying = false});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late EventKind _kind = widget.draft.kind;
  late DateTime _start = widget.draft.startsAt;
  late int _duration = widget.draft.durationMinutes;
  late bool _outside = widget.draft.outsideChurch;
  late int? _remind = widget.draft.remindMinutes;
  late bool _alarm = widget.draft.alarm;
  bool _saving = false;
  // Продължителността следва вида, докато не я промените ръчно.
  late bool _durationTouched = widget.editing || widget.copying;
  late bool _shared = widget.draft.shared;
  late String _assignee = widget.draft.assigneeId;
  late final _forWhom = TextEditingController(text: widget.draft.forWhom);
  final _forWhomFocus = FocusNode();
  late final _phone = TextEditingController(text: widget.draft.phone);
  late final _address = TextEditingController(text: widget.draft.address);
  late final _note = TextEditingController(text: widget.draft.note);

  @override
  void dispose() {
    for (final c in [_forWhom, _phone, _address, _note]) {
      c.dispose();
    }
    _forWhomFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Изберете дата',
    );
    if (d != null) {
      setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
      _announceOverlap();
    }
  }

  /// Колко застъпвания има: на свещеника и в храма.
  int _conflicts() {
    final s = AppScope.read(context);
    return s.overlapsFor(_probe).length + s.placeOverlapsFor(_probe).length;
  }

  /// Казва веднага, ако избраният час се застъпва с друго събитие
  /// на същия свещеник или с друго събитие в храма.
  void _announceOverlap() {
    if (!mounted) return;
    final s = AppScope.read(context);
    final mine = s.overlapsFor(_probe);
    final place = s.placeOverlapsFor(_probe);
    if (mine.isNotEmpty) {
      showMessage(
          context,
          mine.length == 1
              ? 'Внимание: по това време свещеникът има ${eventShortLabel(mine.first)}'
              : 'Внимание: по това време свещеникът има ${mine.length} други събития');
    } else if (place.isNotEmpty) {
      final o = place.first;
      showMessage(context,
          'Внимание: в храма по това време има ${o.kind.label.toLowerCase()} (${s.priestName(o.assigneeId)})');
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
      helpText: 'Изберете час',
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (t != null) {
      setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
      _announceOverlap();
    }
  }

  /// Временно копие с текущите дата, час и продължителност – за проверка за застъпване.
  ChurchEvent get _probe => ChurchEvent(
        id: widget.draft.id,
        ownerId: widget.draft.ownerId,
        churchId: widget.draft.churchId,
        kind: _kind,
        startsAt: _start,
        durationMinutes: _duration,
        assigneeId: _assignee,
        outsideChurch: _outside,
      );

  void _changeDuration(int delta) {
    final before = _conflicts();
    setState(() {
      _durationTouched = true;
      _duration = (_duration + delta).clamp(minDurationMinutes, maxDurationMinutes);
    });
    // При удължаване съобщаваме само ако се появи ново застъпване.
    if (_conflicts() > before) _announceOverlap();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final overlaps = state.overlapsFor(_probe);
    final place = state.placeOverlapsFor(_probe);
    if (overlaps.isNotEmpty || place.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Застъпване'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (overlaps.isNotEmpty) ...[
                Text('В ${fmtRange(_probe)} свещеникът вече има:',
                    style: const TextStyle(fontSize: 17)),
                const SizedBox(height: 8),
                for (final o in overlaps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${eventShortLabel(o)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
              ],
              if (place.isNotEmpty) ...[
                if (overlaps.isNotEmpty) const SizedBox(height: 12),
                Text('В храма по това време има:', style: const TextStyle(fontSize: 17)),
                const SizedBox(height: 8),
                for (final o in place)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${eventShortLabel(o)} – ${state.priestName(o.assigneeId)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('Промени часа')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Запази въпреки това')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final e = widget.draft
      ..kind = _kind
      ..startsAt = _start
      ..durationMinutes = _duration
      ..forWhom = _forWhom.text.trim()
      ..phone = _phone.text.trim()
      ..outsideChurch = _outside
      ..address = _outside ? _address.text.trim() : ''

      ..remindMinutes = _remind
      ..alarm = _remind != null && _alarm
      ..assigneeId = _assignee
      ..shared = _shared || _assignee != widget.draft.ownerId
      ..note = _note.text.trim();
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await state.saveEvent(e);
      nav.pop(true);
    } on AppError catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, err.message);
    }
  }

  Widget _section(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [FieldLabel(label), child],
        ),
      );

  Widget _pickerButton(String text, IconData icon, VoidCallback onTap) {
    final p = Palette.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.surfaceAlt,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Row(children: [
        Icon(icon, color: p.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  /// Падащо меню „Свещеник“ – кой ще извърши събитието.
  Widget _priestPicker(TextStyle fieldStyle) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final church = widget.draft.churchId;
    // Свещениците в одобрена почивка в този ден не се предлагат
    // (освен вече избрания, за да не изчезне от полето).
    final priests = s
        .priestsOf(church)
        .where((x) => x.$1.id == _assignee || !s.isOnLeave(church, x.$1.id, _start))
        .toList();
    final onLeave = s.priestsOf(church).where((x) => s.isOnLeave(church, x.$1.id, _start)).toList();
    final assigneeOnLeave = s.isOnLeave(church, _assignee, _start);
    // Само записалият може да смени свещеника; при един свещеник менюто не трябва.
    if (priests.length < 2 && !assigneeOnLeave) return const SizedBox.shrink();
    final canChange = widget.draft.ownerId == s.currentUser?.id;
    return _section(
      'Свещеник',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        key: ValueKey('priest-${_start.year}-${_start.month}-${_start.day}'),
        initialValue: _assignee,
        style: fieldStyle.copyWith(color: p.text),
        items: [
          for (final (u, _) in priests)
            DropdownMenuItem(
              value: u.id,
              child: Row(children: [
                PriestBadge(
                    name: u.fullName,
                    color: p.priest(s.priestIndex(widget.draft.churchId, u.id)),
                    size: 32,
                    userId: u.id),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                      (u.id == s.currentUser?.id ? '${u.fullName} (аз)' : u.fullName) +
                          (s.isOnLeave(church, u.id, _start) ? ' – в почивка' : ''),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
        ],
        onChanged: canChange
            ? (v) {
                if (v == null) return;
                setState(() => _assignee = v);
                _announceOverlap();
              }
            : null,
      ),
      if (assigneeOnLeave && _assignee != s.currentUser?.id)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${s.priestName(_assignee)} е в почивка в този ден – изберете друг свещеник.',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.error)),
        )
      else if (onLeave.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('В почивка този ден: ${onLeave.map((x) => x.$1.fullName).join(', ')}',
              style: TextStyle(fontSize: 14, color: p.textMuted)),
        ),
      ]),
    );
  }

  Widget _durationControl() {
    final p = Palette.of(context);
    Widget stepButton(IconData icon, String tooltip, VoidCallback? onTap) => IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, size: 26),
          style: IconButton.styleFrom(
            fixedSize: const Size(56, 56),
            backgroundColor: p.surface,
            foregroundColor: p.primary,
            disabledForegroundColor: p.border,
            side: BorderSide(color: p.border),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          stepButton(
              Icons.remove_rounded,
              'С $durationStepMinutes минути по-кратко',
              _duration > minDurationMinutes
                  ? () => _changeDuration(-durationStepMinutes)
                  : null),
          Expanded(
            child: Column(
              children: [
                Text(fmtDuration(_duration),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('до ${fmtTime(_start.add(Duration(minutes: _duration)))}',
                    style: TextStyle(fontSize: 15, color: p.textMuted)),
              ],
            ),
          ),
          stepButton(
              Icons.add_rounded,
              'С $durationStepMinutes минути по-дълго',
              _duration < maxDurationMinutes
                  ? () => _changeDuration(durationStepMinutes)
                  : null),
        ],
      ),
    );
  }

  Widget _choice(String label, bool active, VoidCallback onTap) {
    final p = Palette.of(context);
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: active ? p.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: active ? p.onPrimary : p.chipText)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _twoWay(String a, String b, bool second, ValueChanged<bool> onChanged) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        _choice(a, !second, () => onChanged(false)),
        const SizedBox(width: 4),
        _choice(b, second, () => onChanged(true)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const fieldStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.editing
              ? 'Редакция'
              : widget.copying
                  ? 'Копие на събитие'
                  : 'Ново събитие')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (!_kind.occupiesChurch) _priestPicker(fieldStyle),
            _section(
              'Вид',
              DropdownButtonFormField<EventKind>(
                initialValue: _kind,
                style: fieldStyle.copyWith(color: p.text),
                items: [
                  for (final k in EventKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (k) {
                  if (k == null) return;
                  setState(() {
                    // При смяна на вида „къде“ следва подразбирането за вида,
                    // докато потребителят не е въвел адрес.
                    if (_address.text.isEmpty) _outside = k.defaultOutside;
                    _kind = k;
                    if (!_durationTouched) _duration = k.defaultMinutes;
                    // Архиерейска Литургия: 08:00–14:00 в избрания ден.
                    final h = k.defaultStartHour;
                    if (k.occupiesChurch) _assignee = widget.draft.ownerId;
                    if (h != null) {
                      _start = DateTime(_start.year, _start.month, _start.day, h);
                      _duration = k.defaultMinutes;
                      _outside = false;
                    }
                  });
                },
              ),
            ),
            Row(children: [
              Expanded(
                child: _section('Дата',
                    _pickerButton(fmtDayLong(_start), Icons.event_outlined, _pickDate)),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: _section('Час',
                    _pickerButton(fmtTime(_start), Icons.schedule_outlined, _pickTime)),
              ),
            ]),
            // Предупреждението е точно под датата и часа, за да се види веднага.
            Builder(builder: (context) {
              final s = AppScope.of(context);
              final overlaps = s.overlapsFor(_probe);
              final place = s.placeOverlapsFor(_probe);
              if (overlaps.isEmpty && place.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(children: [
                  if (overlaps.isNotEmpty)
                    OverlapNotice(
                      overlaps,
                      otherChurch: (o) =>
                          o.churchId == widget.draft.churchId ? '' : s.churchName(o.churchId),
                    ),
                  if (overlaps.isNotEmpty && place.isNotEmpty) const SizedBox(height: 10),
                  if (place.isNotEmpty)
                    OverlapNotice(
                      place,
                      title: s.placeOverlapTitle(_probe, place),
                      suffix: (o) => s.priestName(o.assigneeId),
                    ),
                ]),
              );
            }),
            _section('Продължителност', _durationControl()),
            _section(
              'За кого',
              // Предлага последно въведените имена; изборът попълва и телефона.
              RawAutocomplete<(String, String)>(
                textEditingController: _forWhom,
                focusNode: _forWhomFocus,
                optionsBuilder: (v) =>
                    v.text.trim().isEmpty
                    ? const <(String, String)>[]
                    : AppScope.read(context).recentContacts(v.text),
                displayStringForOption: (o) => o.$1,
                onSelected: (o) {
                  if (_phone.text.trim().isEmpty && o.$2.isNotEmpty) {
                    setState(() => _phone.text = o.$2);
                  }
                },
                fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                  style: fieldStyle,
                  decoration: const InputDecoration(hintText: 'например Иван Петров'),
                ),
                optionsViewBuilder: (context, onSelected, options) {
                  final p = Palette.of(context);
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 6,
                      color: p.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: 280, maxWidth: MediaQuery.of(context).size.width - 40),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          children: [
                            for (final o in options)
                              ListTile(
                                minTileHeight: 52,
                                leading: const Icon(Icons.history_rounded),
                                title: Text(o.$1, style: const TextStyle(fontSize: 17)),
                                subtitle: o.$2.isEmpty ? null : Text(o.$2),
                                onTap: () => onSelected(o),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _section(
              'Телефон за връзка',
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: fieldStyle,
              ),
            ),
            _section(
                'Къде',
                _twoWay('В храма', 'Извън храма', _outside,
                    (v) => setState(() => _outside = v))),
            if (_outside)
              _section(
                'Адрес',
                TextField(
                  controller: _address,
                  textCapitalization: TextCapitalization.sentences,
                  style: fieldStyle,
                  maxLines: 2,
                  minLines: 1,
                ),
              ),
            _section(
              'Напомняне',
              DropdownButtonFormField<int?>(
                initialValue: _remind,
                style: fieldStyle.copyWith(color: p.text),
                items: [
                  for (final entry in reminderOptions.entries)
                    DropdownMenuItem<int?>(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (v) => setState(() => _remind = v),
              ),
            ),
            if (_remind != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.border),
                  ),
                  child: SwitchListTile(
                    value: _alarm,
                    onChanged: (v) async {
                      setState(() => _alarm = v);
                      if (v) await Notifier.requestAlarmPermissions();
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: const Text('Аларма',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        _alarm
                            ? 'Звъни като будилник, докато не натиснете „Спри“'
                            : 'Само известие с кратък звук',
                        style: TextStyle(fontSize: 15, color: p.textMuted)),
                  ),
                ),
              ),
            if (stockForEvent(_kind).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Builder(builder: (context) {
                  final need = stockForEvent(_kind);
                  final church = widget.draft.churchId;
                  final bal = AppScope.of(context).canSeeCash(church) ? AppScope.of(context).stockOf(church) : null;
                  final what = need.entries
                      .map((e) => '${e.value} ${switch (e.key) {
                            StockItem.certBaptism => e.value == 1 ? 'кръщелно свидетелство' : 'кръщелни свидетелства',
                            StockItem.certWedding => e.value == 1 ? 'венчално свидетелство' : 'венчални свидетелства',
                            StockItem.diploma => e.value == 1 ? 'грамота' : 'грамоти',
                            _ => e.key.label,
                          }}')
                      .join(' и ');
                  final short = bal != null && need.entries.any((e) => bal[e.key]! < e.value && bal[e.key]! >= 0);
                  final have = bal == null
                      ? ''
                      : ' В склада: ${need.keys.map((i) => '${i.label.toLowerCase()} ${bal[i]}').join(', ')}.'
                          '${short ? ' Не стигат – заредете склада, иначе събитието няма да може да се отбележи като проведено.' : ''}';
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.inventory_2_outlined, size: 20, color: p.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Когато се отбележи като проведено, от склада ${need.values.fold(0, (a, b) => a + b) == 1 ? 'ще излезе' : 'ще излязат'} $what.$have',
                          style: TextStyle(fontSize: 15, color: p.textMuted)),
                    ),
                  ]);
                }),
              ),
            if (_kind.occupiesChurch)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                    'Архиерейската Литургия е за целия храм: всички свещеници получават известие '
                    'и потвърждават с „Приемам“.',
                    style: TextStyle(fontSize: 15, color: p.textMuted)),
              )
            else if (_assignee == widget.draft.ownerId)
              _section(
                  'Кой го вижда',
                  _twoWay('Само аз', 'Споделено с храма', _shared,
                      (v) => setState(() => _shared = v)))
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                    'Събитие за колега се вижда от целия храм, а '
                    '${AppScope.read(context).priestName(_assignee)} получава известие.',
                    style: TextStyle(fontSize: 15, color: p.textMuted)),
              ),
            _section(
              'Бележка',
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                style: fieldStyle,
                minLines: 2,
                maxLines: 5,
              ),
            ),
            const SizedBox(height: 4),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Записване…' : 'Запази')),
          ],
        ),
      ),
    );
  }
}
