import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

import '../data/notifier.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Екранът на звъняща аларма: голям час, събитието и бутон „Спри“.
/// Отваря се сам, щом алармата звънне (и върху заключения екран).
class AlarmRingScreen extends StatelessWidget {
  final AlarmSettings alarm;
  const AlarmRingScreen({super.key, required this.alarm});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = alarm.notificationSettings;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.alarm, size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(fmtTime(DateTime.now()),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                Text(n.title.replaceFirst('⏰ ', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(n.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: p.textMuted)),
                const Spacer(),
                SizedBox(
                  height: 72,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    onPressed: () async {
                      await Notifier.stopAlarm(alarm.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.stop_circle_outlined, size: 32),
                    label: const Text('Спри'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
