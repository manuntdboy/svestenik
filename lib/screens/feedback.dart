import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Обратна връзка до създателя: текст и по желание снимка на екрана.
class FeedbackScreen extends StatefulWidget {
  /// Viber на създателя (само в тестовата версия).
  final String? viber;
  const FeedbackScreen({super.key, this.viber});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _text = TextEditingController();
  Uint8List? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (f == null) return;
    final b = await f.readAsBytes();
    if (mounted) setState(() => _photo = b);
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) {
      showMessage(context, 'Напишете няколко думи.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AppScope.read(context).sendFeedback(_text.text, photo: _photo);
      if (!mounted) return;
      showMessage(context, 'Благодарим! Съобщението е изпратено.');
      Navigator.pop(context);
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Обратна връзка')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('Опишете какво не работи или какво бихте искали. Може да прикачите снимка на екрана.',
                style: TextStyle(fontSize: 15.5, color: p.textMuted, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 5,
              maxLines: 10,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(
                hintText: 'напр. „В касата бутонът Запиши не се вижда целият“',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_photo != null)
              Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(_photo!, height: 220, fit: BoxFit.cover)),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filled(
                    tooltip: 'Махни снимката',
                    onPressed: () => setState(() => _photo = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ])
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _pick,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Прикачи снимка на екрана'),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Изпрати'),
            ),
            if (widget.viber != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => ContactButtons.viber(context, widget.viber!),
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF7360F2)),
                label: const Text('или пишете ми във Viber'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
