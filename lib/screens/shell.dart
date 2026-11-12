import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'calendar.dart';
import 'home.dart';
import 'profile.dart';

/// Основната рамка с долната лента: Начало, Календар, Профил.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Обновява „след 2 часа“ и следващото събитие всяка минута.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pages = [
      HomeScreen(openCalendar: () => setState(() => _tab = 1)),
      const CalendarScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                _NavItem(Icons.home_outlined, 'Начало', _tab == 0, () => setState(() => _tab = 0)),
                _NavItem(Icons.calendar_month_outlined, 'Календар', _tab == 1,
                    () => setState(() => _tab = 1)),
                _NavItem(Icons.person_outline_rounded, 'Профил', _tab == 2,
                    () => setState(() => _tab = 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(this.icon, this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = active ? p.primary : p.textMuted;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: color),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
