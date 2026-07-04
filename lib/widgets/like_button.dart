import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/theme.dart';

/// The "flame" like toggle for a build update, with a live count.
///
/// Optimistic: flips the icon + count immediately, then writes to Supabase and
/// rolls back on failure.
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.entryId,
    required this.initialLiked,
    required this.initialCount,
  });

  final String entryId;
  final bool initialLiked;
  final int initialCount;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  final _client = Supabase.instance.client;
  late bool _liked = widget.initialLiked;
  late int _count = widget.initialCount;
  bool _busy = false;

  Future<void> _toggle() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || _busy) return;

    final wasLiked = _liked;
    setState(() {
      _busy = true;
      _liked = !wasLiked;
      _count += wasLiked ? -1 : 1;
    });

    try {
      if (wasLiked) {
        await _client
            .from('post_likes')
            .delete()
            .eq('build_entry_id', widget.entryId)
            .eq('user_id', uid);
      } else {
        await _client.from('post_likes').upsert(
          {'build_entry_id': widget.entryId, 'user_id': uid},
          onConflict: 'build_entry_id,user_id',
          ignoreDuplicates: true,
        );
      }
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      // Roll back the optimistic change.
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _count += wasLiked ? 1 : -1;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _liked ? Icons.local_fire_department : Icons.local_fire_department_outlined,
              color: _liked ? AppColors.ember : AppColors.steel,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(
              '$_count',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _liked ? AppColors.ember : AppColors.steel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
