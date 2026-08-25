import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/dm.dart';
import 'package:torqueden/services/dm_service.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/time_ago.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';

/// A 1-to-1 DM conversation: message bubbles + a compose bar at the bottom.
class DmThreadScreen extends StatefulWidget {
  const DmThreadScreen({super.key, required this.thread});
  final DmThread thread;

  @override
  State<DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends State<DmThreadScreen> {
  final _client = Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode();

  List<DmMessage> _messages = [];
  bool _loading = true;
  bool _error = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _client
          .from('dm_messages')
          .select()
          .eq('thread_id', widget.thread.id)
          .order('created_at');
      final msgs = (rows as List).map((r) => DmMessage.fromMap(r as Map<String, dynamic>)).toList();
      if (mounted) setState(() { _messages = msgs; _loading = false; });
      _markRead();
      // Scroll after frame + small delay to let keyboard animate in first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 350), _scrollToBottom);
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _markRead() async {
    final uid = _uid;
    if (uid == null) return;
    // Mark all messages from the other person as read.
    await _client
        .from('dm_messages')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('thread_id', widget.thread.id)
        .neq('sender_id', uid)
        .isFilter('read_at', null);
  }

  Future<void> _send() async {
    final uid = _uid;
    final body = _input.text.trim();
    if (body.isEmpty || uid == null || _sending) return;

    _input.clear();
    HapticFeedback.selectionClick();

    // Optimistic insert.
    final optimistic = DmMessage(
      id: 'sending-${DateTime.now().millisecondsSinceEpoch}',
      threadId: widget.thread.id,
      senderId: uid,
      body: body,
      createdAt: DateTime.now(),
    );
    setState(() { _messages = [..._messages, optimistic]; _sending = true; });
    _scrollToBottom();

    try {
      final row = await _client.from('dm_messages').insert({
        'thread_id': widget.thread.id,
        'sender_id': uid,
        'body': body,
      }).select().single();
      final real = DmMessage.fromMap(row);
      if (mounted) {
        setState(() {
          _messages = [
            ..._messages.where((m) => m.id != optimistic.id),
            real,
          ];
          _sending = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      // Roll back optimistic message.
      setState(() {
        _messages = _messages.where((m) => m.id != optimistic.id).toList();
        _sending = false;
        _input.text = body;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _more(BuildContext context) async {
    await showModerationSheet(
      context,
      targetType: 'user',
      targetId: widget.thread.otherUserId,
      authorId: widget.thread.otherUserId,
      authorName: widget.thread.displayName,
      onBlocked: () {
        // Delete the thread locally and go back — they're blocked, no point
        // keeping the conversation open.
        DmService.deleteThread(widget.thread.id);
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            color: AppColors.steel,
            tooltip: 'More',
            onPressed: () => _more(context),
          ),
        ],
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.graphiteRaised,
              backgroundImage: widget.thread.otherAvatarUrl != null
                  ? NetworkImage(widget.thread.otherAvatarUrl!)
                  : null,
              child: widget.thread.otherAvatarUrl == null
                  ? Text(
                      widget.thread.displayName.characters.first.toUpperCase(),
                      style: GoogleFonts.archivo(fontWeight: FontWeight.w700, color: AppColors.cream, fontSize: 14),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              widget.thread.displayName,
              style: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.cream),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.hairline),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: AppColors.steel, size: 40),
                            const SizedBox(height: 12),
                            Text('Could not load messages', style: GoogleFonts.inter(color: AppColors.steel)),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: () { setState(() { _loading = true; _error = false; }); _load(); }, child: const Text('Try again')),
                          ],
                        ),
                      )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.waving_hand_outlined, color: AppColors.steel, size: 36),
                            const SizedBox(height: 12),
                            Text(
                              'Say hi to ${widget.thread.displayName}',
                              style: GoogleFonts.inter(fontSize: 15, color: AppColors.steel),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg = _messages[i];
                          final isMine = msg.senderId == uid;
                          final showDate = i == 0 ||
                              _messages[i].createdAt.difference(_messages[i - 1].createdAt).inMinutes > 30;
                          return Column(
                            children: [
                              if (showDate)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    timeAgo(msg.createdAt),
                                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                                  ),
                                ),
                              _Bubble(message: msg, isMine: isMine),
                            ],
                          );
                        },
                      ),
          ),
          _ComposeBar(
            controller: _input,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
          ),
        ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMine});
  final DmMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? AppColors.ember : AppColors.graphiteRaised,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: Text(
          message.body,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: isMine ? AppColors.onEmber : AppColors.cream,
          ),
        ),
      ),
    );
  }
}

class _ComposeBar extends StatefulWidget {
  const _ComposeBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<_ComposeBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      final has = widget.controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    // When keyboard is up, viewInsets.bottom covers the safe area too.
    final bottomPad = bottomInset > 0 ? bottomInset : safeBottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomPad),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.graphiteRaised,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.hairline),
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                maxLines: 5,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.cream),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: _hasText ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 150),
            child: GestureDetector(
              onTap: _hasText && !widget.sending ? widget.onSend : null,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.ember,
                  shape: BoxShape.circle,
                ),
                child: widget.sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
