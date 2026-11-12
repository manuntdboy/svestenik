import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'church_code.dart';

/// „Свържете се с храм“: присъединяване с код или създаване на нов храм.
/// [pushed] = отворен от профила (за добавяне на още един храм).
class ChurchConnectScreen extends StatefulWidget {
  final bool pushed;
  const ChurchConnectScreen({super.key, this.pushed = false});

  @override
  State<ChurchConnectScreen> createState() => _ChurchConnectScreenState();
}

class _ChurchConnectScreenState extends State<ChurchConnectScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _place = TextEditingController();
  final _mun = TextEditingController();
  String? _codeError;
  String? _createError;

  @override
  void dispose() {
    for (final c in [_code, _name, _place, _mun]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _join() async {
    final state = AppScope.read(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final err = await state.joinChurch(_code.text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _codeError = err);
      return;
    }
    _code.clear();
    if (state.pendingChurches.isNotEmpty && state.currentChurch?.id != null && widget.pushed) {
      nav.pop();
    }
    if (state.pendingChurches.isNotEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Заявката е изпратена. Председателят на храма трябва да ви одобри.',
              style: TextStyle(fontSize: 16))));
    } else if (widget.pushed) {
      nav.pop();
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2 ||
        _place.text.trim().length < 2 ||
        _mun.text.trim().length < 2) {
      setState(() => _createError = 'Попълнете име, населено място и община.');
      return;
    }
    final state = AppScope.read(context);
    final nav = Navigator.of(context);
    final pushed = widget.pushed;
    final Church church;
    try {
      church = await state.createChurch(_name.text, _place.text, _mun.text);
    } on AppError catch (e) {
      if (mounted) setState(() => _createError = e.message);
      return;
    }
    // Показваме кода веднага, за да може да се даде на другите свещеници.
    // (Този екран може вече да е заменен от таблото, затова ползваме nav.)
    if (pushed) nav.pop();
    nav.push(MaterialPageRoute(
        builder: (_) => ChurchCodeScreen(churchId: church.id, justCreated: true)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final state = AppScope.of(context);
    return Scaffold(
      appBar: widget.pushed ? AppBar(title: const Text('Добавяне на храм')) : null,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, widget.pushed ? 8 : 32, 20, 24),
          children: [
            if (!widget.pushed) ...[
              const Text('Свържете се с храм',
                  style:
                      TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 6),
            ],
            Text(
                'Календарът ви принадлежи към храм. Присъединете се с код или създайте нов храм.',
                style: TextStyle(fontSize: 16, color: p.textMuted)),
            const SizedBox(height: 16),
            for (final c in state.pendingChurches)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: p.heroBg,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const YellowTag('Чака одобрение'),
                      const SizedBox(height: 10),
                      Text(c.name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(c.place, style: TextStyle(fontSize: 15, color: p.heroMuted)),
                      const SizedBox(height: 8),
                      Text(
                          'Председателят получи известие. Щом ви одобри, ще ви дойде известие '
                          'и храмът ще се отвори тук.',
                          style: TextStyle(fontSize: 15, color: p.heroMuted)),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: state.refresh,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70)),
                        child: const Text('Провери отново'),
                      ),
                    ],
                  ),
                ),
              ),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Имам код',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const FieldLabel('Код на храма'),
                  TextField(
                    controller: _code,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    maxLength: 6,
                    onChanged: (_) {
                      if (_codeError != null) setState(() => _codeError = null);
                    },
                    onSubmitted: (_) => _join(),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6),
                    decoration: InputDecoration(
                      hintText: '______',
                      counterText: '',
                      errorText: _codeError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _join, child: const Text('Присъедини се')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Expanded(child: Divider(color: p.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('или', style: TextStyle(color: p.textMuted, fontSize: 14)),
                ),
                Expanded(child: Divider(color: p.border)),
              ]),
            ),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Създавам нов храм',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const FieldLabel('Име на храма'),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(hintText: 'например Св. Николай'),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Населено място'),
                  TextField(
                    controller: _place,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Община'),
                  TextField(
                    controller: _mun,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                      'Населеното място и общината различават храмове с еднакви имена. '
                      'След създаването получавате код, който давате на другите свещеници.',
                      style: TextStyle(fontSize: 14, color: p.textMuted)),
                  if (_createError != null) ...[
                    const SizedBox(height: 8),
                    Text(_createError!,
                        style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _create, child: const Text('Създай храм')),
                ],
              ),
            ),
            if (!widget.pushed) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => state.logout(),
                  child: Text('Изход от ${state.currentUser?.username ?? ''}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
