import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// Постоянният адрес „Свали Кайрос“ – не се сменя при нова версия.
const kDownloadPage = 'https://manuntdboy.github.io/svestenik/svali/';

/// „Покани колега“: QR код и връзка към страницата за сваляне.
class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key});

  static const _message =
      'Кайрос – приложението за свещеници: календар, дежурства, почивки, каса, склад и чат на храма.\n'
      'Свалете го оттук (Android) или го отворете в браузъра (iPhone): $kDownloadPage';

  Future<void> _viber(BuildContext context) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse('viber://forward?text=${Uri.encodeComponent(_message)}'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      await Clipboard.setData(const ClipboardData(text: _message));
      if (context.mounted) showMessage(context, 'Viber не се отвори – поканата е копирана.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Покани колега')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
            Text('Колегата сканира кода с камерата на телефона си. Отваря се страницата „Свали Кайрос“ – '
                'на Android сваля приложението, на iPhone отваря сайта.',
                style: TextStyle(fontSize: 16, color: p.textMuted)),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: kDownloadPage, version: QrVersions.auto, size: 240),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: SelectableText(kDownloadPage,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: p.textMuted)),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Изпрати по Viber'),
              onPressed: () => _viber(context),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Копирай поканата'),
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: _message));
                if (context.mounted) showMessage(context, 'Поканата е копирана.');
              },
            ),
            const SizedBox(height: 18),
            Text('Кодът е винаги един и същ – води към най-новата версия. Можете да го разпечатате.',
                style: TextStyle(fontSize: 14, color: p.textMuted)),
          ]),
        ),
      ),
    );
  }
}
