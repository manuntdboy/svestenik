import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'register.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AppScope.read(context).login(_user.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Забравена парола'),
        content: Text(
          'Смяната на паролата през имейл идва в следващата версия.\n\n'
          'Дотогава се обърнете към администратора на приложението.',
          style: TextStyle(fontSize: 17),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
          children: [
            Container(
              width: 64,
              height: 76,
              alignment: Alignment.center,
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: p.calendarTile,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32), bottom: Radius.circular(14)),
              ),
              child: Icon(Icons.calendar_month_outlined, size: 32, color: p.onCalendarTile),
            ),
            const SizedBox(height: 14),
            Text('Кайрос · тестова версия',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.textMuted)),
            const SizedBox(height: 14),
            const Text('Добре дошли',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('Влезте, за да видите календара си.',
                style: TextStyle(fontSize: 17, color: p.textMuted)),
            const SizedBox(height: 24),
            const FieldLabel('Потребителско име или имейл'),
            TextField(
              controller: _user,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Парола'),
            TextField(
              controller: _pass,
              obscureText: !_show,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _login(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: _show ? 'Скрий паролата' : 'Покажи паролата',
                  icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _forgot, child: const Text('Забравена парола?')),
            ),
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
              onPressed: _busy ? null : _login,
              child: const Text('Вход'),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Нямате профил?', style: TextStyle(fontSize: 16, color: p.textMuted)),
                TextButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('Регистрация'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
