import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/models/app_notification.dart';
import 'package:torqueden/services/notifications_service.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';

/// The notifications inbox: a list of the events you've been notified about,
/// with unread ones highlighted. Rows are created by DB triggers that respect
/// your notification preferences (Settings → Notifications).
class NotificationsListScreen extends StatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() => _NotificationsListScreenState();
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = NotificationsService.list();
  }

  Future<void> _refresh() async {
    final future = NotificationsService.list();
    setState(() => _future = future);
    await future;
  }

  Future<void> _markAllRead() async {
    await NotificationsService.markAllRead();
    await _refresh();
  }

  Future<void> _onTap(AppNotification n) async {
    if (!n.read) {
      await NotificationsService.markRead(n.id);
      await _refresh();
    }
    // Deep-linking to the exact post/thread is a follow-up; for now tapping
    // just marks the notification read.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: Text('Mark all read',
                style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.ember,
          backgroundColor: AppColors.graphite,
          onRefresh: _refresh,
          child: FutureBuilder<List<AppNotification>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.ember));
              }
              final items = snapshot.data ?? const <AppNotification>[];
              if (items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.notifications_none,
                      title: 'No notifications yet',
                      message: 'Follows, comments, likes and club activity will show up here.',
                    ),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(color: AppColors.hairline, height: 1),
                itemBuilder: (_, i) => _NotificationTile(
                  notification: items[i],
                  onTap: () => _onTap(items[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return Material(
      color: n.read ? Colors.transparent : AppColors.ember.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(url: n.actorAvatarUrl, type: n.type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: n.read ? FontWeight.w500 : FontWeight.w700,
                        color: AppColors.cream,
                        height: 1.3,
                      ),
                    ),
                    if (n.body != null && n.body!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        n.body!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _relativeTime(n.createdAt),
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (!n.read) ...[
                const SizedBox(width: 8),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.ember, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The actor's avatar if we have one, otherwise a type icon.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.type});

  final String? url;
  final String type;

  IconData get _icon => switch (type) {
        'new_follower' => Icons.person_add_alt_1,
        'post_comment' => Icons.mode_comment_outlined,
        'post_like' => Icons.local_fire_department,
        'club_new_thread' => Icons.forum_outlined,
        'thread_reply' => Icons.reply,
        'comment_reply' => Icons.reply,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.trim().isNotEmpty;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        shape: BoxShape.circle,
        image: hasUrl ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: hasUrl ? null : Icon(_icon, size: 20, color: AppColors.steel),
    );
  }
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${(d.inDays / 7).floor()}w ago';
}
