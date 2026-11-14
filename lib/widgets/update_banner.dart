import 'package:flutter/material.dart';

import '../data/updater.dart';
import '../theme.dart';

/// Жълта лента „Има нова версия – Обнови“ на началния екран.
class UpdateBanner extends StatelessWidget {
  /// true – създателят е задал минимална версия и тази е по-стара.
  final bool required;
  const UpdateBanner({super.key, this.required = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Updater.i,
      builder: (context, _) {
        final u = Updater.i;
        if (!u.available && !required) return const SizedBox.shrink();
        final busy = u.progress != null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Palette.yellow, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.system_update_rounded, color: Palette.onYellow, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      u.available
                          ? 'Има нова версия на Кайрос${u.latestBuild > 0 ? ' (${u.latestBuild})' : ''}.'
                          : 'Има нова версия на Кайрос. Отворете App Tester и натиснете „Обнови“.',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.onYellow)),
                ),
                if (u.available)
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Palette.onYellow, foregroundColor: Palette.yellow),
                    onPressed: busy ? null : u.install,
                    child: Text(busy ? '${u.progress}%' : 'Обнови'),
                  ),
              ]),
              if (busy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                    value: (u.progress ?? 0) / 100, color: Palette.onYellow, backgroundColor: Colors.white54),
              ],
              if (u.error != null) ...[
                const SizedBox(height: 8),
                Text(u.error!, style: const TextStyle(fontSize: 14, color: Palette.onYellow)),
              ],
            ]),
          ),
        );
      },
    );
  }
}
