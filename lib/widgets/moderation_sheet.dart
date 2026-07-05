import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';

const _reasons = <String>[
  'Spam or scam',
  'Harassment or bullying',
  'Inappropriate or explicit',
  'Something else',
];

/// Opens the report / block menu for a piece of content and its author.
/// [onBlocked] fires after a successful block so the caller can refresh.
Future<void> showModerationSheet(
  BuildContext context, {
  required String targetType, // 'post' | 'comment' | 'thread' | 'reply' | 'club' | 'user'
  required String targetId,
  String? authorId,
  String? authorName,
  VoidCallback? onBlocked,
}) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  final canBlock = authorId != null && authorId != uid;
  final name = authorName ?? 'this user';

  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.graphite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: AppColors.steel),
            title: const Text('Report'),
            subtitle: const Text('Flag this for review'),
            onTap: () => Navigator.pop(ctx, 'report'),
          ),
          if (canBlock)
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.danger),
              title: Text('Block $name'),
              subtitle: const Text('You won\'t see their posts or replies'),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'report') {
    await _report(context, targetType, targetId);
  } else if (action == 'block' && canBlock) {
    await _block(context, authorId, name, onBlocked);
  }
}

Future<void> _report(BuildContext context, String targetType, String targetId) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.graphite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Why are you reporting this?',
                style: GoogleFonts.archivo(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.cream)),
          ),
          for (final r in _reasons)
            ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (reason == null) return;
  try {
    await Moderation.report(targetType: targetType, targetId: targetId, reason: reason);
    if (context.mounted) _toast(context, 'Thanks — reported for review.');
  } catch (e) {
    if (context.mounted) _toast(context, 'Could not send the report: $e');
  }
}

Future<void> _block(
  BuildContext context,
  String userId,
  String name,
  VoidCallback? onBlocked,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.graphite,
      title: Text('Block $name?',
          style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
      content: Text('Their posts, replies and comments will be hidden from you.',
          style: GoogleFonts.inter(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Block', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await Moderation.block(userId);
    if (context.mounted) _toast(context, 'Blocked $name.');
    onBlocked?.call();
  } catch (e) {
    if (context.mounted) _toast(context, 'Could not block: $e');
  }
}

void _toast(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
