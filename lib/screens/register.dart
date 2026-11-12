import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _user, _email, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pass.text != _pass2.text) {
      setState(() => _error = 'Двете пароли не съвпадат.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.read(context);
    final nav = Navigator.of(context);
    final err = await state.register(
      fullName: _name.text,
      username: _user.text,
      email: _email.text,
      password: _pass.text,
    );
    if (!mounted) return;
    if (err == null) {
      nav.popUntil((r) => r.isFirst);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  Widget _field(String label, TextEditingController c,
      {String? hint,
      bool password = false,
      TextInputType? type,
      List<String>? autofill,
      TextCapitalization caps = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          TextField(
            controller: c,
            obscureText: password && !_show,
            keyboardType: type,
            autofillHints: autofill,
            autocorrect: false,
            textCapitalization: caps,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: password
                  ? IconButton(
                      tooltip: _show ? 'Скрий паролата' : 'Покажи паролата',
                      icon: Icon(
                          _show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _show = !_show),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('С този профил влизате от всеки телефон. Имейлът не се показва на никого.',
                style: TextStyle(fontSize: 16, color: p.textMuted)),
            const SizedBox(height: 18),
            _field('Име, както да се показва', _name,
                hint: 'например Отец Георги',
                autofill: const [AutofillHints.name],
                caps: TextCapitalization.words),
            _field('Потребителско име (на латиница)', _user,
                hint: 'например georgi', autofill: const [AutofillHints.newUsername]),
            _field('Имейл (за забравена парола)', _email,
                type: TextInputType.emailAddress, autofill: const [AutofillHints.email]),
            _field('Парола (поне 6 знака)', _pass,
                password: true, autofill: const [AutofillHints.newPassword]),
            _field('Повторете паролата', _pass2, password: true),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!,
                    style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600)),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Създай профил'),
            ),
          ],
        ),
      ),
    );
  }
}
