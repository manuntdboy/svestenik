import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Смяна на паролата. [forced] – след временна парола от председателя:
/// без „назад“, докато не се избере нова парола.
class ChangePasswordScreen extends StatefulWidget {
  final bool forced;
  const ChangePasswordScreen({super.key, this.forced = false});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = _p1.text;
    if (a.length < 6) return setState(() => _error = 'Паролата трябва да е поне 6 знака.');
    if (a != _p2.text) return setState(() => _error = 'Двете пароли не съвпадат.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = AppScope.read(context);
    try {
      await s.changePassword(a);
      if (!mounted) return;
      showMessage(context, 'Паролата е сменена.');
      if (!widget.forced) Navigator.pop(context);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Нова парола'),
          automaticallyImplyLeading: !widget.forced,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              if (widget.forced)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                      'Влязохте с временна парола от председателя. Изберете своя парола – '
                      'с нея ще влизате от сега нататък.',
                      style: TextStyle(fontSize: 16.5, color: p.textMuted, height: 1.4)),
                ),
              TextField(
                controller: _p1,
                obscureText: !_show,
                autofillHints: const [AutofillHints.newPassword],
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'Нова парола (поне 6 знака)',
                  suffixIcon: IconButton(
                    tooltip: _show ? 'Скрий' : 'Покажи',
                    onPressed: () => setState(() => _show = !_show),
                    icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _p2,
                obscureText: !_show,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(labelText: 'Повторете паролата'),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: _busy ? null : _save,
                child: const Text('Запази паролата'),
              ),
              if (widget.forced) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: () => s.logout(), child: const Text('Изход')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
