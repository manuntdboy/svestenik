import 'package:flutter/material.dart';

import '../data/app_state.dart';
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
  late bool _outside = widget.draft.outsideChurch;
  late int? _remind = widget.draft.remindMinutes;
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
    }
  }

  Future<void> _save() async {
    final e = widget.draft
      ..kind = _kind
      ..startsAt = _start
      ..forWhom = _forWhom.text.trim()
      ..phone = _phone.text.trim()
      ..outsideChurch = _outside
      ..address = _outside ? _address.text.trim() : ''
      ..remindMinutes = _remind
      ..shared = _shared
      ..note = _note.text.trim();
    final nav = Navigator.of(context);
    await AppScope.read(context).saveEvent(e);
    nav.pop(true);
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
            FilledButton(onPressed: _save, child: const Text('Запази')),
          ],
        ),
      ),
    );
  }
}
