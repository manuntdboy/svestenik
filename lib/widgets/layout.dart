import 'package:flutter/material.dart';

/// true, докато е показан изгледът за компютър (меню отстрани).
/// Всички останали екрани на широк екран стоят в колона в средата.
final desktopShell = ValueNotifier<bool>(false);

/// Сигнал „към днес“ – календарът се връща на днешния ден (бутонът „Кайрос“).
final calendarToday = ChangeNotifier();

/// Маркер в списъка на [SplitList]: оттук нататък – дясната колона.
class SplitHere extends StatelessWidget {
  const SplitHere({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Списък, който на широк екран (компютър) става две колони:
/// всичко до [SplitHere] – отляво, останалото – отдясно.
/// На телефона е обикновен списък, както досега.
class SplitList extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final double leftWidth;
  const SplitList({super.key, required this.children, required this.padding, this.leftWidth = 460});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final i = children.indexWhere((w) => w is SplitHere);
      if (c.maxWidth < 860 || i < 0) {
        return ListView(
            physics: const AlwaysScrollableScrollPhysics(), padding: padding, children: children);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: leftWidth,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding.copyWith(right: 12),
            children: children.sublist(0, i),
          ),
        ),
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding.copyWith(left: 12),
            children: children.sublist(i + 1),
          ),
        ),
      ]);
    });
  }
}
