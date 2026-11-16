import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/notifier.dart';
import '../theme.dart';
import 'common.dart';

/// Следи за повиквания от владиката: щом има неотговорено – показва прозорец
/// „Идвам / Не мога“. На служителите от администрацията веднъж предлага
/// Кайрос да звъни и при „Не безпокойте“.
class CallWatcher extends StatefulWidget {
  final Widget child;
  const CallWatcher({super.key, required this.child});

  @override
  State<CallWatcher> createState() => _CallWatcherState();
}

class _CallWatcherState extends State<CallWatcher> {
  static const _kDndAsked = 'call_dnd_asked';
  final _shown = <String>{};
  bool _open = false;
  bool _dndChecked = false;
  AppState? _s;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.read(context);
    if (!identical(s, _s)) {
      _s?.removeListener(_check);
      _s = s..addListener(_check);
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _s?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final s = _s!;
    if (!_dndChecked && s.isAdmin && !s.isMetropolitan) {
      _dndChecked = true;
      _askDnd();
    }
    if (_open) return;
    final c = s.openCallsForMe.where((c) => !_shown.contains(c.id)).firstOrNull;
    if (c == null) return;
    _shown.add(c.id);
    _open = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await answerCall(context, c);
      _open = false;
      if (mounted) _check();
    });
  }

  Future<void> _askDnd() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kDndAsked) == true || await Notifier.callDndAllowed()) {
      await Notifier.ensureCallChannel();
      return;
    }
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined, size: 36),
        title: const Text('Повикване от владиката'),
        content: const Text('Когато владиката ви повика в кабинета, телефонът ще звънне със звънец.\n\n'
            'За да звъни и при включено „Не безпокойте“, разрешете на Кайрос в следващия екран '
            '(„Достъп до Не безпокойте“).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не сега')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Разреши')),
        ],
      ),
    );
    await prefs.setBool(_kDndAsked, true);
    if (yes == true) await Notifier.askCallDnd();
    await Notifier.ensureCallChannel();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Прозорецът „Владиката ви вика“ с двата отговора.
Future<void> answerCall(BuildContext context, MetroCall c) async {
  final s = AppScope.read(context);
  final p = Palette.of(context);
  if (s.metroPeople.isEmpty) await s.loadMetroPeople();
  if (!context.mounted) return;
  final x = s.metroPeople.where((e) => e['user_id'] == c.callerId).firstOrNull;
  final who = x == null ? 'Владиката' : withRank(ClergyRank.fromCode(x['rank']), '${x['name'] ?? ''}');
  final coming = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.notifications_active_rounded, size: 40, color: Notifier.callColor),
      title: const Text('Владиката ви вика'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$who ви вика в кабинета.', style: const TextStyle(fontSize: 17)),
        if ((c.note ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(c.note!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 8),
        Text(hm(c.createdAt), style: TextStyle(color: p.textMuted)),
      ]),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не мога')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Идвам')),
      ],
    ),
  );
  if (coming == null) return;
  try {
    await s.metroCallAnswer(c.id, coming);
  } on AppError catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
