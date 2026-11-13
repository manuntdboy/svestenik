import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/church_banner.dart';
import '../widgets/common.dart';

/// Разделът „Чат“: общият чат на храма и личните разговори с колегите.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurch!;
    final me = s.currentUser!.id;
    final colleagues = s.priestsOf(church.id).where((x) => x.$1.id != me && x.$2.isActive).map((x) => x.$1).toList();
    // По-скорошните разговори – отгоре.
    DateTime last(String t) {
      final th = s.chatThread(church.id, t);
      return th.isEmpty ? DateTime(2000) : th.last.createdAt;
    }

    colleagues.sort((a, b) => last(b.id).compareTo(last(a.id)));
    final general = s.chatThread(church.id, 'c');

    Widget row({
      required Widget leading,
      required String title,
      required String preview,
      required int unread,
      required bool muted,
      required VoidCallback onTap,
      DateTime? at,
    }) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: unread > 0 ? p.primary : p.border, width: unread > 0 ? 2 : 1)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                        if (muted) Icon(Icons.notifications_off_outlined, size: 18, color: p.textMuted),
                        if (at != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(_when(at), style: TextStyle(fontSize: 12.5, color: p.textMuted)),
                          ),
                      ]),
                      const SizedBox(height: 2),
                      Text(preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              color: unread > 0 ? p.text : p.textMuted,
                              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400)),
                    ]),
                  ),
                  if (unread > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(12)),
                      child: Text('$unread',
                          style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w800, fontSize: 13.5)),
                    ),
                ]),
              ),
            ),
          ),
        );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const ChurchBanner(title: 'Чат'),
        const SizedBox(height: 14),
        row(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.forum_rounded, color: p.onPrimary),
          ),
          title: 'Чат на храма',
          preview: general.isEmpty
              ? 'Всички свещеници в храма'
              : '${s.priestName(general.last.senderId)}: ${general.last.body}',
          unread: s.chatUnread(church.id, 'c'),
          muted: s.chatMuted(church.id, 'c'),
          at: general.isEmpty ? null : general.last.createdAt,
          onTap: () => openChat(context, 'c'),
        ),
        const SizedBox(height: 10),
        Text('Лични съобщения', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.textMuted)),
        const SizedBox(height: 8),
        if (colleagues.isEmpty)
          Text('В храма още няма други свещеници.', style: TextStyle(fontSize: 15, color: p.textMuted)),
        for (final u in colleagues)
          Builder(builder: (_) {
            final th = s.chatThread(church.id, u.id);
            return row(
              leading: PriestBadge(
                  name: u.fullName, color: p.priest(s.priestIndex(church.id, u.id)), size: 44, userId: u.id),
              title: u.fullName,
              preview: th.isEmpty ? 'Напишете съобщение' : '${th.last.senderId == me ? 'Вие: ' : ''}${th.last.body}',
              unread: s.chatUnread(church.id, u.id),
              muted: s.chatMuted(church.id, u.id),
              at: th.isEmpty ? null : th.last.createdAt,
              onTap: () => openChat(context, u.id),
            );
          }),
        const SizedBox(height: 8),
        Text('Само текст. Съобщенията се пазят 6 месеца.', style: TextStyle(fontSize: 13, color: p.textMuted)),
      ],
    );
  }
}

String _when(DateTime t) {
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) return DateFormat('HH:mm').format(t);
  final y = now.subtract(const Duration(days: 1));
  if (t.year == y.year && t.month == y.month && t.day == y.day) return 'вчера';
  return DateFormat('d.MM').format(t);
}

void openChat(BuildContext context, String thread, {String draft = ''}) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(thread: thread, draft: draft)));
}

/// Един разговор: общият чат ('c') или с колега (неговото id).
class ChatScreen extends StatefulWidget {
  final String thread;
  final String draft;
  const ChatScreen({super.key, required this.thread, this.draft = ''});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _text = TextEditingController(text: widget.draft);
  final _scroll = ScrollController();
  Timer? _poll;
  bool _busy = false;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    // Докато разговорът е отворен – нови съобщения на всеки 5 секунди.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final s = AppScope.read(context);
      s.pollChat(s.currentChurchId!);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _busy) return;
    final s = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await s.sendChat(s.currentChurchId!, widget.thread == 'c' ? null : widget.thread, t);
      _text.clear();
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _actions(ChatMessage m) async {
    final s = AppScope.read(context);
    final mine = m.senderId == s.currentUser?.id;
    final canDelete = mine || (m.recipientId == null && s.isManagerOf(m.churchId));
    if (!canDelete) return;
    final ok = await confirm(context, 'Изтриване на съобщението', m.body, 'Изтрий');
    if (!ok || !mounted) return;
    try {
      await s.deleteChat(m);
    } on AppError catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _mutedList() async {
    final s = AppScope.read(context);
    final ids = s.chatMutedBy(s.currentChurchId!);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Заглушили чата на храма', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (ids.isEmpty) const Text('Никой – всички получават известия.', style: TextStyle(fontSize: 16)),
            for (final id in ids)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(s.priestName(id)),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final church = s.currentChurchId!;
    final me = s.currentUser!.id;
    final general = widget.thread == 'c';
    final msgs = s.chatThread(church, widget.thread);
    final muted = s.chatMuted(church, widget.thread);
    if (msgs.length != _lastCount) {
      _lastCount = msgs.length;
      _toBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) s.markChatRead(church, widget.thread);
      });
    }
    final title = general ? 'Чат на храма' : s.priestName(widget.thread);
    final dayF = DateFormat('EEEE, d MMMM', 'bg');

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (general && s.isManagerOf(church))
            IconButton(
              tooltip: 'Кой е заглушил чата',
              onPressed: _mutedList,
              icon: Badge(
                isLabelVisible: s.chatMutedBy(church).isNotEmpty,
                label: Text('${s.chatMutedBy(church).length}'),
                child: const Icon(Icons.groups_outlined),
              ),
            ),
          IconButton(
            tooltip: muted ? 'Включи известията' : 'Заглуши',
            onPressed: () async {
              try {
                await s.muteChat(church, widget.thread, !muted);
                if (context.mounted) {
                  showMessage(context, muted ? 'Известията са включени.' : 'Разговорът е заглушен – без известия.');
                }
              } on AppError catch (e) {
                if (context.mounted) showMessage(context, e.message);
              }
            },
            icon: Icon(muted ? Icons.notifications_off_rounded : Icons.notifications_active_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (muted)
            Container(
              width: double.infinity,
              color: p.chipBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                  general
                      ? 'Заглушили сте чата – няма да получавате известия. Председателят вижда това.'
                      : 'Заглушили сте разговора – няма да получавате известия.',
                  style: TextStyle(fontSize: 14, color: p.chipText)),
            ),
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(general ? 'Още няма съобщения в чата на храма.' : 'Още няма съобщения.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: p.textMuted)),
                    ),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    children: [
                      for (final (i, m) in msgs.indexed) ...[
                        if (i == 0 || dayF.format(msgs[i - 1].createdAt) != dayF.format(m.createdAt))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: Text(capitalize(dayF.format(m.createdAt)),
                                  style: TextStyle(fontSize: 13, color: p.textMuted)),
                            ),
                          ),
                        _Bubble(
                          msg: m,
                          mine: m.senderId == me,
                          showName: m.senderId != me,
                          onLongPress: () => _actions(m),
                        ),
                      ],
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 17),
                  decoration: const InputDecoration(hintText: 'Съобщение', counterText: ''),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Изпрати',
                iconSize: 26,
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final bool mine;
  final bool showName;
  final VoidCallback onLongPress;
  const _Bubble({required this.msg, required this.mine, required this.showName, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    // Всеки свещеник – в своя цвят: снимка/инициали, име и лента на балончето.
    final who = p.priest(s.priestIndex(msg.churchId, msg.senderId));
    final name = msg.senderId.isEmpty ? 'Изтрит потребител' : s.priestName(msg.senderId);
    final bg = mine ? p.primary : Color.alphaBlend(who.withValues(alpha: p.dark ? .22 : .12), p.surface);
    final onColor = mine ? p.onPrimary : p.text;
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .74),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border(left: BorderSide(color: who, width: 5)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showName)
            Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: who)),
          SelectableText(msg.body, style: TextStyle(fontSize: 16.5, color: onColor, height: 1.3)),
          Align(
            alignment: Alignment.centerRight,
            child: Text(DateFormat('HH:mm').format(msg.createdAt),
                style: TextStyle(fontSize: 11.5, color: onColor.withValues(alpha: .7))),
          ),
        ]),
      ),
    );
    if (mine) return Align(alignment: Alignment.centerRight, child: bubble);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: PriestBadge(name: name, color: who, size: 34, userId: msg.senderId.isEmpty ? null : msg.senderId),
      ),
      Flexible(child: bubble),
    ]);
  }
}
