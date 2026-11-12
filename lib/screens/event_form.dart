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
  const EventFormScreen({super.key, required this.draft, this.editing = false});

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
  late bool _shared = widget.draft.shared;
  late final _forWhom = TextEditingController(text: widget.draft.forWhom);
  late final _phone = TextEditingController(text: widget.draft.phone);
  late final _address = TextEditingController(text: widget.draft.address);
  late final _note = TextEditingController(text: widget.draft.note);

  @override
  void dispose() {
    for (final c in [_forWhom, _phone, _address, _note]) {
      c.dispose();
    }
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

  /// Казва веднага, ако избраният час се застъпва с друго събитие.
  void _announceOverlap() {
    if (!mounted) return;
    final overlaps = AppScope.read(context).overlapsFor(_probe);
    if (overlaps.isEmpty) return;
    showMessage(
        context,
        overlaps.length == 1
            ? 'Внимание: по това време имате ${eventShortLabel(overlaps.first)}'
            : 'Внимание: по това време имате ${overlaps.length} други събития');
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
      );

  void _changeDuration(int delta) {
    final before = AppScope.read(context).overlapsFor(_probe).length;
    setState(() {
      _duration = (_duration + delta).clamp(minDurationMinutes, maxDurationMinutes);
    });
    // При удължаване съобщаваме само ако се появи ново застъпване.
    if (AppScope.read(context).overlapsFor(_probe).length > before) _announceOverlap();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final overlaps = state.overlapsFor(_probe);
    if (overlaps.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Застъпване'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('В ${fmtRange(_probe)} вече имате:', style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 8),
              for (final o in overlaps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${eventShortLabel(o)}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
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
      ..shared = _shared
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
      appBar: AppBar(title: Text(widget.editing ? 'Редакция' : 'Ново събитие')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
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
              if (overlaps.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OverlapNotice(
                  overlaps,
                  otherChurch: (o) =>
                      o.churchId == widget.draft.churchId ? '' : s.churchName(o.churchId),
                ),
              );
            }),
            _section('Продължителност', _durationControl()),
            _section(
              'За кого',
              TextField(
                controller: _forWhom,
                textCapitalization: TextCapitalization.words,
                style: fieldStyle,
                decoration: const InputDecoration(hintText: 'например Иван Петров'),
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
            _section(
                'Кой го вижда',
                _twoWay('Само аз', 'Споделено с храма', _shared,
                    (v) => setState(() => _shared = v))),
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
