import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Код за присъединяване на храма, QR код и свързаните свещеници.
class ChurchCodeScreen extends StatelessWidget {
  final String churchId;
  final bool justCreated;
  const ChurchCodeScreen({super.key, required this.churchId, this.justCreated = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.myChurches.where((c) => c.id == churchId).firstOrNull;
    if (church == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Храмът не е намерен.')));
    }
    final manager = s.isManagerOf(churchId);
    final members = s.membersOf(churchId);

    return Scaffold(
      appBar: AppBar(title: Text(justCreated ? 'Храмът е създаден' : 'Код на храма')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(church.name,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            Text(church.place, style: TextStyle(fontSize: 16, color: p.textMuted)),
            const SizedBox(height: 16),
            SurfaceCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Код за присъединяване',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: p.textMuted)),
                  const SizedBox(height: 6),
                  SelectableText(church.joinCode,
                      style: const TextStyle(
                          fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 8)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.white, // QR кодът се чете най-добре на бяло
                    child: QrImageView(
                      data: 'KAIROS:${church.joinCode}',
                      version: QrVersions.auto,
                      size: 180,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: church.joinCode));
                      showMessage(context, 'Кодът е копиран.');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Копирай кода'),
                  ),
                  if (manager) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        final ok = await confirm(
                            context,
                            'Нов код',
                            'Старият код спира да работи. Вече свързаните свещеници остават свързани.',
                            'Смени кода');
                        if (!ok) return;
                        try {
                          await s.regenerateCode(churchId);
                        } on AppError catch (e) {
                          if (context.mounted) showMessage(context, e.message);
                        }
                      },
                      child: const Text('Смени кода'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
                'Дайте кода на другите свещеници. Те го въвеждат в Кайрос на своя телефон '
                '(„Добави още един храм“ или при първия вход) и се свързват с този храм.',
                style: TextStyle(fontSize: 14, color: p.textMuted)),
            const SizedBox(height: 20),
            Text('Свързани свещеници',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final (u, m) in members)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  radius: 18,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.fullName,
                                style:
                                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            Text(m.isManager ? 'Председател' : (m.isCashier ? 'Свещеник · касиер' : 'Свещеник'),
                                style: TextStyle(fontSize: 14, color: p.textMuted)),
                          ],
                        ),
                      ),
                      if (manager && u.id != s.currentUser?.id)
                        TextButton(
                          onPressed: () async {
                            final ok = await confirm(context, 'Премахване',
                                '${u.fullName} няма да вижда споделените събития на храма.', 'Премахни');
                            if (!ok) return;
                            try {
                              await s.removeMember(churchId, u.id);
                            } on AppError catch (e) {
                              if (context.mounted) showMessage(context, e.message);
                            }
                          },
                          child: const Text('Премахни'),
                        ),
                    ],
                  ),
                ),
              ),
            if (justCreated) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Към началото'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
