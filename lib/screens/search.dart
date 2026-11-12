import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_detail.dart';

/// Търсене в събитията на храма: име, телефон, адрес, бележка, вид, свещеник.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final results = s.search(_q.text);
    final now = DateTime.now();
    final firstPast = results.indexWhere((e) => e.startsAt.isBefore(now));

    return Scaffold(
      appBar: AppBar(title: const Text('Търсене')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Име, телефон, адрес, бележка…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Изчисти',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_q.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _q.text.trim().length < 2
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        'Напишете поне две букви. Търси се в събитията на храма, '
                        'които виждате: за кого, телефон, адрес, бележка, вид и свещеник.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: p.textMuted)),
                  )
                : results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Няма намерени събития.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 17, color: p.textMuted)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final e = results[i];
                          final header = i == 0
                              ? (firstPast == 0 ? 'Минали' : 'Предстоящи')
                              : (i == firstPast ? 'Минали' : null);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (header != null)
                                Padding(
                                  padding: EdgeInsets.only(top: i == 0 ? 4 : 14, bottom: 8),
                                  child: Text(header,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w800)),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: p.surface,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      side: BorderSide(color: p.border)),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => EventDetailScreen(eventId: e.id))),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      child: Row(children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  '${fmtDayLong(e.startsAt)} ${e.startsAt.year}, ${fmtTime(e.startsAt)}',
                                                  style: const TextStyle(
                                                      fontSize: 15, fontWeight: FontWeight.w700)),
                                              Text(
                                                  e.forWhom.isEmpty ? e.kind.label : e.forWhom,
                                                  style: TextStyle(
                                                      fontSize: 17,
                                                      fontWeight: FontWeight.w700,
                                                      decoration: e.isCancelled
                                                          ? TextDecoration.lineThrough
                                                          : null)),
                                              Text(
                                                  [
                                                    s.priestName(e.assigneeId),
                                                    e.placeLabel,
                                                    if (e.phone.isNotEmpty) e.phone,
                                                    if (e.isCancelled) 'отменено',
                                                    if (e.isDone) 'проведено',
                                                  ].join(' · '),
                                                  style: TextStyle(
                                                      fontSize: 14, color: p.textMuted)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        KindChip(e.kind),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
