import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Чат „Митрополия“ – общият на администрацията и личните разговори.
class MetroChatScreen extends StatefulWidget {
  final bool embedded;
  const MetroChatScreen({super.key, this.embedded = false});

  @override
  State<MetroChatScreen> createState() => _MetroChatScreenState();
}

class _MetroChatScreenState extends State<MetroChatScreen> {
  @override
  void initState() {
    super.initState();
    AppScope.read(context).loadMetroPeople();
  }

  String _name(Map<String, dynamic> x) => withRank(ClergyRank.fromCode(x['rank']), '${x['name'] ?? ''}');

  String _role(Map<String, dynamic> x) {
    final r = StaffRole.fromCode(x['role']);
    if (r == StaffRole.employee) return '${x['title'] ?? r!.label}';
    return r?.label ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final me = s.currentUser?.id;
    final people = s.metroPeople.where((x) => x['user_id'] != me).toList();
    Widget row(String thread, Widget leading, String title, String sub) {
      final th = s.metroThread(thread);
      final unread = s.metroUnread(thread);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: unread > 0 ? p.primary : p.border, width: unread > 0 ? 2 : 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Theme(
                        data: Theme.of(context), child: MetroThreadScreen(thread: thread, title: title)))),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(th.isEmpty ? sub : th.last.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: unread > 0 ? p.text : p.textMuted,
                            fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                ),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(12)),
                    child: Text('$unread', style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w800)),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Чат · Митрополия'), automaticallyImplyLeading: !widget.embedded),
      body: RefreshIndicator(
        onRefresh: () async {
          await s.refresh();
          await s.loadMetroPeople();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          row(
            'c',
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text('☦', style: TextStyle(fontSize: 22, color: p.onPrimary))),
            ),
            'Администрация',
            'Общ разговор на митрополията',
          ),
          if (people.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Text('ЛИЧНИ РАЗГОВОРИ',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: p.primary)),
            ),
          for (final x in people)
            row(
              '${x['user_id']}',
              CircleAvatar(
                radius: 22,
                backgroundColor: p.chipBg,
                child: Text('${x['name'] ?? '?'}'.characters.first, style: TextStyle(color: p.primary)),
              ),
              _name(x),
              _role(x),
            ),
          const SizedBox(height: 10),
          Text('Разговорите виждат само участниците в тях. Съобщенията се пазят 6 месеца.',
              style: TextStyle(fontSize: 13.5, color: p.textMuted)),
        ]),
      ),
    );
  }
}

/// Един разговор в чата „Митрополия“.
class MetroThreadScreen extends StatefulWidget {
  final String thread; // 'c' – общият, иначе id на събеседника
  final String title;
  const MetroThreadScreen({super.key, required this.thread, required this.title});

  @override
  State<MetroThreadScreen> createState() => _MetroThreadScreenState();
}

class _MetroThreadScreenState extends State<MetroThreadScreen> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).metroRead(widget.thread);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).metroSend(widget.thread, t);
      _c.clear();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final me = s.currentUser?.id;
    final msgs = s.metroThread(widget.thread).reversed.toList();
    String who(String? id) {
      final x = s.metroPeople.where((e) => e['user_id'] == id).firstOrNull;
      return x == null ? '' : withRank(ClergyRank.fromCode(x['rank']), '${x['name'] ?? ''}');
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? Center(child: Text('Още няма съобщения.', style: TextStyle(color: p.textMuted)))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final mine = m.senderId == me;
                    Future<void> act() async {
                          final canDelete = mine || (m.recipientId == null && s.isMetropolitanOf(m.dioceseId));
                          final ok = canDelete &&
                              await confirm(context, 'Изтриване', 'Да изтрия ли съобщението?', 'Изтрий');
                          if (ok) {
                            try {
                              await s.metroDelete(m.id);
                            } on AppError catch (e) {
                              if (context.mounted) showMessage(context, e.message);
                            }
                          }
}

                    final dots = MediaQuery.sizeOf(context).width < 1000 ||
                            !(mine || (m.recipientId == null && s.isMetropolitanOf(m.dioceseId)))
                        ? null
                        : IconButton(
                            tooltip: 'Действия',
                            visualDensity: VisualDensity.compact,
                            iconSize: 20,
                            color: p.textMuted,
                            icon: const Icon(Icons.more_vert_rounded),
                            onPressed: act,
                          );
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (mine && dots != null) dots,
                        Flexible(child: GestureDetector(
                        onLongPress: act,
                        onSecondaryTap: act, // десен бутон на мишката
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          decoration: BoxDecoration(
                            color: mine ? p.primary.withValues(alpha: .22) : p.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: mine ? p.primary.withValues(alpha: .5) : p.border),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (!mine && widget.thread == 'c')
                              Text(who(m.senderId),
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: p.primary)),
                            Text(m.body, style: const TextStyle(fontSize: 16.5)),
                            Text(_hm(m.createdAt), style: TextStyle(fontSize: 12, color: p.textMuted)),
                          ]),
                        ),
                      )),
                        if (!mine && dots != null) dots,
                      ]),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (node, e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed &&
                        MediaQuery.sizeOf(context).width >= 1000) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Съобщение…', counterText: ''),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Изпрати',
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
