import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/theme.dart';

/// Follow / Following toggle for a car.
///
/// Self-contained: if [initialFollowing] is given (e.g. a list screen already
/// knows the state), it skips the lookup; otherwise it queries on init. Calls
/// [onChanged] after a successful toggle so parents can refresh if they want.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.carId,
    this.initialFollowing,
    this.onChanged,
    this.compact = false,
  });

  final String carId;
  final bool? initialFollowing;
  final ValueChanged<bool>? onChanged;

  /// A smaller pill, for use inside list rows.
  final bool compact;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  final _client = Supabase.instance.client;

  bool? _following; // null = still loading
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFollowing != null) {
      _following = widget.initialFollowing;
    } else {
      _check();
    }
  }

  Future<void> _check() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _following = false);
      return;
    }
    try {
      final rows = await _client
          .from('follows')
          .select('id')
          .eq('follower_id', uid)
          .eq('car_id', widget.carId)
          .limit(1);
      if (mounted) setState(() => _following = rows.isNotEmpty);
    } catch (_) {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _toggle() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || _following == null) return;
    setState(() => _busy = true);

    final wantFollow = !(_following!);
    try {
      if (wantFollow) {
        // Upsert + ignoreDuplicates so re-following an already-followed car is a
        // no-op instead of a unique-constraint error (the button state can lag
        // behind the DB if you followed the same car from another screen).
        await _client.from('follows').upsert(
          {'follower_id': uid, 'car_id': widget.carId},
          onConflict: 'follower_id,car_id',
          ignoreDuplicates: true,
        );
      } else {
        await _client
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('car_id', widget.carId);
      }
      if (!mounted) return;
      setState(() {
        _following = wantFollow;
        _busy = false;
      });
      widget.onChanged?.call(wantFollow);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final following = _following;
    if (following == null) {
      // Reserve roughly the button's footprint while we check.
      return const SizedBox(
        height: 36,
        width: 96,
        child: Center(
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.steel),
          ),
        ),
      );
    }

    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 10);

    final child = _busy
        ? const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.steel),
          )
        : Text(following ? 'Following' : 'Follow');

    if (following) {
      return OutlinedButton(
        onPressed: _busy ? null : _toggle,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.steel,
          side: const BorderSide(color: AppColors.hairline),
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: _busy ? null : _toggle,
      style: FilledButton.styleFrom(
        padding: padding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: child,
    );
  }
}
