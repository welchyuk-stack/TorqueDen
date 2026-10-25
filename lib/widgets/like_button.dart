import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/services/guest_mode.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/guest_nudge_sheet.dart';

enum Reaction {
  fire('fire', '🔥', 'Fire'),
  clean('clean', '⭐', 'Clean'),
  sick('sick', '🤘', 'Sick'),
  insane('insane', '🤯', 'Insane');

  const Reaction(this.value, this.emoji, this.label);
  final String value;
  final String emoji;
  final String label;
}

/// Reaction bar. Shows the user's current reaction (or a neutral add-reaction
/// button) and a count. Tapping opens a picker; selecting a reaction switches
/// to it (radio-style — only one per user per post).
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

  /// reaction_type → total count
  late Map<String, int> _counts;

  /// The single reaction type this user has applied, or null.
  String? _mine;

  bool _busy = false;
  final _pickerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _counts = {'fire': widget.initialCount};
    if (widget.initialLiked) _mine = 'fire';
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _client
          .from('post_likes')
          .select('reaction_type, user_id')
          .eq('build_entry_id', widget.entryId);

      final counts = <String, int>{};
      String? mine;
      for (final r in rows) {
        final type = (r['reaction_type'] as String?) ?? 'fire';
        counts[type] = (counts[type] ?? 0) + 1;
        if (r['user_id'] == uid) mine = type;
      }
      if (mounted) {
        setState(() {
          _counts = counts;
          _mine = mine;
        });
      }
    } catch (_) {}
  }

  /// Switch to [type]. If already selected, deselect.
  Future<void> _select(String type) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || _busy) return;

    final prev = _mine;
    final same = prev == type;

    // Optimistic update
    setState(() {
      _busy = true;
      if (prev != null) _counts[prev] = (_counts[prev] ?? 1) - 1;
      if (!same) {
        _mine = type;
        _counts[type] = (_counts[type] ?? 0) + 1;
      } else {
        _mine = null;
      }
    });

    try {
      // Remove existing reaction (if any)
      if (prev != null) {
        await _client
            .from('post_likes')
            .delete()
            .eq('build_entry_id', widget.entryId)
            .eq('user_id', uid)
            .eq('reaction_type', prev);
      }
      // Insert new reaction (unless deselecting)
      if (!same) {
        await _client.from('post_likes').upsert(
          {'build_entry_id': widget.entryId, 'user_id': uid, 'reaction_type': type},
          onConflict: 'build_entry_id,user_id,reaction_type',
          ignoreDuplicates: true,
        );
      }
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      // Roll back
      if (!mounted) return;
      setState(() {
        if (!same && _mine != null) _counts[_mine!] = (_counts[_mine!] ?? 1) - 1;
        if (prev != null) _counts[prev] = (_counts[prev] ?? 0) + 1;
        _mine = prev;
        _busy = false;
      });
    }
  }

  void _showPicker() {
    if (GuestMode.isGuest) {
      showGuestNudge(context, reason: 'react to posts');
      return;
    }
    final box = _pickerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);

    final dark = Theme.of(context).brightness == Brightness.dark;
    showMenu<String>(
      context: context,
      color: dark ? AppColors.graphiteRaised : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? const Color(0xFF3A3F4A) : Colors.black.withValues(alpha: 0.12), width: 1),
      ),
      elevation: 8,
      position: RelativeRect.fromLTRB(
        0,
        (pos.dy - 100).clamp(MediaQuery.of(context).padding.top + 8, double.infinity),
        MediaQuery.of(context).size.width,
        pos.dy,
      ),
      items: [
        PopupMenuItem(
          enabled: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: Reaction.values.map((r) {
              final active = _mine == r.value;
              return _PickerItem(
                reaction: r,
                active: active,
                onTap: () {
                  Navigator.pop(context);
                  _select(r.value);
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentReaction = _mine != null
        ? Reaction.values.firstWhere((r) => r.value == _mine,
            orElse: () => Reaction.fire)
        : null;

    // Total reactions across all types
    final total = _counts.values.fold(0, (s, v) => s + v);

    return GestureDetector(
      key: _pickerKey,
      onTap: _showPicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: currentReaction != null
              ? AppColors.ember.withValues(alpha: 0.14)
              : Colors.transparent,
          border: Border.all(
            color: currentReaction != null
                ? AppColors.ember.withValues(alpha: 0.30)
                : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentReaction?.emoji ?? '🤝',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 6),
            Text(
              '$total',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: currentReaction != null ? AppColors.ember : AppColors.steel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerItem extends StatefulWidget {
  const _PickerItem({required this.reaction, required this.active, required this.onTap});
  final Reaction reaction;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_PickerItem> createState() => _PickerItemState();
}

class _PickerItemState extends State<_PickerItem> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 60),
  ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onTap() async {
    await _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return GestureDetector(
      onTap: _onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? AppColors.ember.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border.all(
              color: active ? AppColors.ember : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.reaction.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(
                widget.reaction.label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? AppColors.ember
                      : Theme.of(context).brightness == Brightness.dark
                          ? AppColors.textSecondary
                          : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
