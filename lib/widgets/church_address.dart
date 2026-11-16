import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import 'common.dart';

/// Навигация до адрес в Google Maps (направо маршрут).
Future<void> navigateGoogle(BuildContext context, String query) async {
  final uri = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': query});
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) showMessage(context, 'Google Maps не може да се отвори.');
}

/// Навигация до адрес в Waze (приложението или сайтът му).
Future<void> navigateWaze(BuildContext context, String query) async {
  final uri = Uri.https('waze.com', '/ul', {'q': query, 'navigate': 'yes'});
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) showMessage(context, 'Waze не може да се отвори.');
}

/// Два бутона: „Google Maps“ и „Waze“.
class NavigateButtons extends StatelessWidget {
  final String query;
  const NavigateButtons(this.query, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, IconData icon, Color bg, VoidCallback onTap) => Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: bg,
              foregroundColor: Colors.white,
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label, maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        );
    return Row(children: [
      btn('Google Maps', Icons.map_rounded, const Color(0xFF1A73E8), () => navigateGoogle(context, query)),
      const SizedBox(width: 8),
      btn('Waze', Icons.navigation_rounded, const Color(0xFF0B9AD8), () => navigateWaze(context, query)),
    ]);
  }
}

/// Прозорец за адрес и Булстат. Връща true, ако е записано.
Future<bool> editChurchInfo(BuildContext context,
    {required String churchId, String? address, String? bulstat}) async {
  final s = AppScope.of(context);
  final a = TextEditingController(text: address ?? '');
  final b = TextEditingController(text: bulstat ?? '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      String? err;
      var busy = false;
      return StatefulBuilder(builder: (ctx, set) {
        Future<void> save() async {
          final digits = b.text.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.isNotEmpty && digits.length != 9 && digits.length != 13) {
            set(() => err = 'Булстатът трябва да е 9 или 13 цифри.');
            return;
          }
          set(() {
            busy = true;
            err = null;
          });
          try {
            await s.setChurchInfo(churchId, a.text, b.text);
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on AppError catch (e) {
            set(() {
              busy = false;
              err = e.message;
            });
          }
        }

        return AlertDialog(
          title: const Text('Адрес и Булстат'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: a,
                autofocus: true,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Точен адрес',
                  hintText: 'ул. „Цар Симеон Велики“ 112',
                  helperText: 'Населеното място и общината се добавят сами.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: b,
                keyboardType: TextInputType.number,
                maxLength: 13,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: 'Булстат', errorText: err),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Отказ')),
            FilledButton(onPressed: busy ? null : save, child: const Text('Запази')),
          ],
        );
      });
    },
  );
  return saved == true;
}

/// Избор на духовна околия за храм – само създателят (всички епархии).
/// Връща true при запис.
Future<bool> editChurchVicariate(BuildContext context,
    {required String churchId, String? dioceseId, String? vicariateId}) async {
  final s = AppScope.read(context);
  if (s.dioceses.isEmpty) await s.loadPlaces();
  if (!context.mounted) return false;
  final all = s.isCreator;
  final options = <(String, String)>[
    for (final d in all ? s.dioceses : s.dioceses.where((d) => d.id == dioceseId))
      for (final v in s.vicariatesOf(d.id))
        (v.id, '${all ? '${d.name} · ' : ''}${v.name}${v.isCenter ? ' (епархийски център)' : ''}'),
  ];
  String? pick = vicariateId;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      String? err;
      var busy = false;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Духовна околия'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: options.any((o) => o.$1 == pick) ? pick : null,
                isExpanded: true,
                hint: const Text('Изберете'),
                items: [
                  for (final o in options)
                    DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() => pick = v),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Отказ')),
            FilledButton(
              onPressed: busy || pick == null
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        await s.setChurchVicariate(churchId, pick!);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on AppError catch (e) {
                        set(() {
                          busy = false;
                          err = e.message;
                        });
                      }
                    },
              child: const Text('Запази'),
            ),
          ],
        ),
      );
    },
  );
  return saved == true;
}

/// Адресът и Булстатът на храма с бутоните за навигация.
/// Председателят вижда и „Редактирай“.
class ChurchAddressBlock extends StatelessWidget {
  final Church church;
  final bool canEdit;
  const ChurchAddressBlock(this.church, {super.key, this.canEdit = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final addr = (church.address ?? '').trim();
    final bul = (church.bulstat ?? '').trim();
    final place = AppScope.of(context).churchPlace(church);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (place.isNotEmpty) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.account_balance_outlined, size: 20, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(place, style: const TextStyle(fontSize: 15))),
          if (AppScope.of(context).isCreator)
            IconButton(
              tooltip: 'Смени околията',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_rounded, size: 18),
              onPressed: () async {
                final ok = await editChurchVicariate(context,
                    churchId: church.id, dioceseId: church.dioceseId, vicariateId: church.vicariateId);
                if (ok && context.mounted) showMessage(context, 'Записано.');
              },
            ),
        ]),
        const SizedBox(height: 6),
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.place_rounded, size: 20, color: p.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: addr.isEmpty
              ? Text(canEdit ? 'Адресът не е въведен – добавете го, за да се намира лесно.' : 'Адресът не е въведен.',
                  style: TextStyle(fontSize: 15, color: p.textMuted))
              : SelectableText('$addr, ${church.settlement}', style: const TextStyle(fontSize: 15)),
        ),
      ]),
      if (bul.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.badge_outlined, size: 20, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(child: SelectableText('Булстат $bul', style: const TextStyle(fontSize: 15))),
          IconButton(
            tooltip: 'Копирай Булстата',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bul));
              showMessage(context, 'Булстатът е копиран.');
            },
          ),
        ]),
      ],
      const SizedBox(height: 10),
      NavigateButtons(church.mapsQuery),
      if (canEdit)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: Text(addr.isEmpty && bul.isEmpty ? 'Добави адрес и Булстат' : 'Редактирай адреса и Булстата'),
            onPressed: () async {
              final ok = await editChurchInfo(context, churchId: church.id, address: church.address, bulstat: church.bulstat);
              if (ok && context.mounted) showMessage(context, 'Записано.');
            },
          ),
        ),
    ]);
  }
}
