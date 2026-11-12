import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'church_code.dart';
import 'priest_profile.dart';

/// Списък на свещениците в храма – всеки със своя цвят от календара.
class ChurchPriestsScreen extends StatelessWidget {
  final String churchId;
  const ChurchPriestsScreen({super.key, required this.churchId});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.myChurches.where((c) => c.id == churchId).firstOrNull;
    if (church == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Храмът не е намерен.')));
    }
    final priests = s.priestsOf(churchId);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Свещеници в храма')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(church.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              Text(church.place, style: TextStyle(fontSize: 16, color: p.textMuted)),
              const SizedBox(height: 6),
              Text('Всеки свещеник има свой цвят. Със същия цвят са точките в календара и знакът до всяко събитие.',
                  style: TextStyle(fontSize: 15, color: p.textMuted)),
              const SizedBox(height: 16),
              for (final (u, m) in priests)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                PriestProfileScreen(churchId: churchId, userId: u.id))),
                    child: SurfaceCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    radius: 20,
                    child: Row(
                      children: [
                        PriestBadge(
                            name: u.fullName,
                            color: p.priest(s.priestIndex(churchId, u.id)),
                            size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u.id == s.currentUser?.id ? '${u.fullName} (аз)' : u.fullName,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                              Text(m.isManager ? 'Председател' : (m.isCashier ? 'Свещеник · касиер' : 'Свещеник'),
                                  style: TextStyle(fontSize: 15, color: p.textMuted)),
                              Builder(builder: (context) {
                                final n = s.visibleEvents
                                    .where((e) => e.assigneeId == u.id && e.startsAt.isAfter(now))
                                    .length;
                                return Text(
                                    n == 0
                                        ? 'Няма предстоящи събития'
                                        : n == 1
                                            ? '1 предстоящо събитие'
                                            : '$n предстоящи събития',
                                    style: TextStyle(fontSize: 15, color: p.textMuted));
                              }),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      ],
                    ),
                  ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ChurchCodeScreen(churchId: churchId))),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Покани свещеник (код на храма)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
