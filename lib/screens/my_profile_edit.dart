import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'my_profile.dart';

/// Редакция на личния профил (прост екран; ще бъде дизайниран отделно).
class MyProfileEditScreen extends StatefulWidget {
  const MyProfileEditScreen({super.key});

  @override
  State<MyProfileEditScreen> createState() => _MyProfileEditScreenState();
}

class _MyProfileEditScreenState extends State<MyProfileEditScreen> {
  late final _d = AppScope.read(context).myDetails.copy();
  late final _names = TextEditingController(text: _d.threeNames);
  late ClergyRank? _rank = AppScope.read(context).currentUser?.rank;
  late final _phone = TextEditingController(text: AppScope.read(context).currentUser?.phone ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _names.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickFull(DateTime? current, String help, {DateTime? initial}) =>
      showDatePicker(
        context: context,
        initialDate: current ?? initial ?? DateTime(1975, 1, 1),
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        helpText: help,
        initialDatePickerMode: current == null ? DatePickerMode.year : DatePickerMode.day,
        initialEntryMode: DatePickerEntryMode.calendarOnly,
      );

  Future<void> _pickNameDay() async {
    // Годината не се записва – календарът е за 2000 г. (високосна, има 29 февруари).
    final d = await showDatePicker(
      context: context,
      initialDate: _d.hasNameDay
          ? DateTime(2000, _d.nameDayMonth!, _d.nameDayDay!)
          : DateTime(2000, DateTime.now().month, DateTime.now().day),
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2000, 12, 31),
      helpText: 'Имен ден (само ден и месец)',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d != null) {
      setState(() {
        _d.nameDayMonth = d.month;
        _d.nameDayDay = d.day;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    _d.threeNames = _names.text;
    final nav = Navigator.of(context);
    final s = AppScope.read(context);
    try {
      if (_rank != s.currentUser?.rank || _phone.text.trim() != (s.currentUser?.phone ?? '')) {
        await s.setRankAndPhone(_rank, _phone.text);
      }
      await s.saveDetails(_d);
      nav.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, e.message);
    }
  }

  Widget _dateField(String label, String value, VoidCallback onTap, VoidCallback? onClear) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldLabel(label),
        Row(children: [
          Expanded(
            child: OutlinedButton(
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
                Icon(Icons.event_outlined, color: p.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(value,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'Изчисти',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Редактирай профила')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(
              child: Stack(clipBehavior: Clip.none, children: [
                const ProfilePhoto(size: 112),
                Positioned(
                  right: -4,
                  bottom: 0,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    onPressed: () => pickAndUploadPhoto(context),
                    icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    label: const Text('Смени'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            const FieldLabel('Сан'),
            DropdownButtonFormField<ClergyRank?>(
              initialValue: _rank,
              isExpanded: true,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не е избран')),
                for (final r in ClergyRank.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (v) => setState(() => _rank = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              child: Text(
                  'Стои пред името ви навсякъде в Кайрос, например „Протойерей Тодор Чобанов“.',
                  style: TextStyle(fontSize: 14, color: Palette.of(context).textMuted)),
            ),
            const FieldLabel('Три имена'),
            TextField(
              controller: _names,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: 'Име Презиме Фамилия'),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Телефон'),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: 'например 0888 123 456'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              child: Text(
                  'По желание. Виждат го само свещениците от вашия храм – за „Обади се“ и „Viber“.',
                  style: TextStyle(fontSize: 14, color: Palette.of(context).textMuted)),
            ),
            _dateField(
              'Дата на раждане',
              fmtDateFull(_d.birthDate),
              () async {
                final v = await _pickFull(_d.birthDate, 'Дата на раждане');
                if (v != null) setState(() => _d.birthDate = v);
              },
              _d.birthDate == null ? null : () => setState(() => _d.birthDate = null),
            ),
            _dateField(
              'Дата на ръкоположение',
              fmtDateFull(_d.ordinationDate),
              () async {
                final v = await _pickFull(_d.ordinationDate, 'Дата на ръкоположение',
                    initial: DateTime(2000, 1, 1));
                if (v != null) setState(() => _d.ordinationDate = v);
              },
              _d.ordinationDate == null ? null : () => setState(() => _d.ordinationDate = null),
            ),
            _dateField(
              'Имен ден (ден и месец)',
              fmtNameDay(_d),
              _pickNameDay,
              !_d.hasNameDay
                  ? null
                  : () => setState(() {
                        _d.nameDayMonth = null;
                        _d.nameDayDay = null;
                      }),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Записване…' : 'Запази'),
            ),
          ],
        ),
      ),
    );
  }
}
