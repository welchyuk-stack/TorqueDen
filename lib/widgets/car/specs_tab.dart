import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/car_spec.dart';
import 'package:torqueden/models/challenge.dart';
import 'package:torqueden/services/challenge_service.dart';
import 'package:torqueden/services/dm_service.dart';
import 'package:torqueden/theme.dart';

/// Specs tab for a car's detail view.
///
/// Shows a fixed "identity" card built from the [Car] object itself, then a
/// "Performance & specs" section of free-form label/value rows loaded live from
/// the `car_specs` table (addable and deletable). Self-contained scrollable so
/// it works as a [TabBarView] child.
class SpecsTab extends StatefulWidget {
  const SpecsTab({super.key, required this.car, this.isOwner = false});

  final Car car;

  /// True when the signed-in user owns this car (hides owner card + message btn).
  final bool isOwner;

  @override
  State<SpecsTab> createState() => _SpecsTabState();
}

class _SpecsTabState extends State<SpecsTab> {
  final _client = Supabase.instance.client;
  late Future<List<CarSpec>> _specsFuture;
  Map<String, dynamic>? _ownerProfile;

  @override
  void initState() {
    super.initState();
    _specsFuture = _loadSpecs();
    if (!widget.isOwner && widget.car.ownerId != null) _loadOwner();
  }

  Future<void> _loadOwner() async {
    try {
      final row = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .eq('id', widget.car.ownerId!)
          .single();
      if (mounted) setState(() => _ownerProfile = row);
    } catch (_) {}
  }

  Future<List<CarSpec>> _loadSpecs() async {
    final rows = await _client
        .from('car_specs')
        .select()
        .eq('car_id', widget.car.id)
        .order('position')
        .order('created_at');
    return rows.map(CarSpec.fromMap).toList();
  }

  Future<void> _refresh() async {
    // Block body, not an arrow: returning the Future from setState() throws.
    final future = _loadSpecs();
    setState(() {
      _specsFuture = future;
    });
    await future;
  }

  Future<void> _openAddSpec() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddSpecSheet(carId: widget.car.id),
    );
    if (added == true) {
      await _refresh();
    }
  }

  Future<void> _deleteSpec(CarSpec spec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text(
          'Delete spec?',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: AppColors.cream,
          ),
        ),
        content: Text(
          'Remove "${spec.label}" from this car\'s specs?',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _client.from('car_specs').delete().eq('id', spec.id);
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete spec: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.ember,
      backgroundColor: AppColors.graphite,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.isOwner && widget.car.ownerId != null) ...[
            _OwnerCard(
              profile: _ownerProfile,
              onMessage: _ownerProfile == null
                  ? null
                  : () => DmService.openOrCreate(
                        context: context,
                        otherUserId: _ownerProfile!['id'] as String,
                        otherUsername: _ownerProfile!['username'] as String,
                        otherDisplayName: _ownerProfile!['display_name'] as String?,
                        otherAvatarUrl: _ownerProfile!['avatar_url'] as String?,
                      ),
            ),
            const SizedBox(height: 16),
          ],
          _IdentityCard(car: widget.car),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Performance & specs',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cream,
                  ),
                ),
              ),
              if (widget.isOwner)
                OutlinedButton.icon(
                  onPressed: _openAddSpec,
                  icon: const Icon(Icons.add, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ember,
                    side: BorderSide(color: AppColors.hairline),
                    textStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  label: const Text('Add spec'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<CarSpec>>(
            future: _specsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.ember),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _SpecsCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Could not load specs.',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _refresh,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ember,
                            side: BorderSide(color: AppColors.hairline),
                          ),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final specs = snapshot.data ?? const <CarSpec>[];
              if (specs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No extra specs yet — add power, torque, 0–60, anything.',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                );
              }
              return _SpecsCard(
                child: Column(
                  children: [
                    for (var i = 0; i < specs.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: AppColors.hairline),
                      _SpecRow(
                        spec: specs[i],
                        onDelete: widget.isOwner
                            ? () => _deleteSpec(specs[i])
                            : null,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (widget.car.description != null &&
              widget.car.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 24),
            _NotesBlock(notes: widget.car.description!.trim()),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The car's free-text notes, shown at the bottom of the Specs tab.
class _NotesBlock extends StatelessWidget {
  const _NotesBlock({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return _SpecsCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notes',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              notes,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.cream,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owner row: avatar + name + Message button. Shows a skeleton while loading.
class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.profile, required this.onMessage});

  final Map<String, dynamic>? profile;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile?['avatar_url'] as String?;
    final displayName = (profile?['display_name'] as String?)?.trim();
    final username = profile?['username'] as String?;
    final name = (displayName?.isNotEmpty ?? false)
        ? displayName!
        : (username != null ? '@$username' : null);
    final loading = profile == null;

    return _SpecsCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.graphiteRaised,
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: loading || avatarUrl != null
                  ? null
                  : Text(
                      (name ?? '?').characters.first.toUpperCase(),
                      style: GoogleFonts.archivo(
                          fontWeight: FontWeight.w700, color: AppColors.cream, fontSize: 16),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Owner',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  loading
                      ? Container(
                          height: 14,
                          width: 100,
                          decoration: BoxDecoration(
                            color: AppColors.graphiteRaised,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Text(
                          name ?? 'Unknown',
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.cream),
                        ),
                ],
              ),
            ),
            if (!loading)
              TextButton.icon(
                onPressed: onMessage,
                icon: Icon(Icons.forum_outlined, size: 18, color: AppColors.ember),
                label: Text(
                  'Message',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ember),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppColors.ember.withValues(alpha: 0.3)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fixed card describing the car, built from the [Car] object (not the DB).
/// Also loads and displays any Shot trophies in a ghosted Awards section.
class _IdentityCard extends StatefulWidget {
  const _IdentityCard({required this.car});
  final Car car;

  @override
  State<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends State<_IdentityCard> {
  List<CarBadge> _badges = [];

  @override
  void initState() {
    super.initState();
    ChallengeService.instance.fetchBadgesForCar(widget.car.id).then((b) {
      if (mounted) setState(() => _badges = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final cells = <(String, String)>[
      ('Make', car.make),
      ('Model', car.model),
      if (car.chassisModel != null && car.chassisModel!.trim().isNotEmpty)
        ('Chassis', car.chassisModel!.trim()),
      if (car.year != null) ('Year', '${car.year}'),
      if (car.color != null && car.color!.trim().isNotEmpty)
        ('Colour', car.color!.trim()),
      if (car.nickname != null && car.nickname!.trim().isNotEmpty)
        ('Nickname', car.nickname!.trim()),
    ];

    return _SpecsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cells.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _IdentityCell(cell: cells[i])),
                  const SizedBox(width: 16),
                  Expanded(
                    child: i + 1 < cells.length
                        ? _IdentityCell(cell: cells[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
            if (_badges.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: AppColors.hairline, height: 1),
              const SizedBox(height: 14),
              Text(
                'Awards',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _badges.map((b) => _AwardChip(badge: b)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AwardChip extends StatelessWidget {
  const _AwardChip({required this.badge});
  final CarBadge badge;

  @override
  Widget build(BuildContext context) {
    final month = _monthAbbr(badge.awardedAt.month);
    final year = badge.awardedAt.year;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.ember.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.ember.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(
            '${badge.challengeTitle} — $month $year',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _monthAbbr(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];
}

/// One label-over-value cell in the identity grid.
class _IdentityCell extends StatelessWidget {
  const _IdentityCell({required this.cell});

  final (String, String) cell;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cell.$1,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          cell.$2,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.cream,
          ),
        ),
      ],
    );
  }
}

/// One DB-backed spec row: label/value with delete tucked behind a kebab —
/// a bare trash can on every row keeps a destructive action one mis-tap away.
class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.spec, required this.onDelete});

  final CarSpec spec;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return _TwoColumnRow(
      label: spec.label,
      value: spec.value,
      trailing: onDelete == null
          ? null
          : PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: AppColors.textMuted),
              tooltip: 'More',
              color: AppColors.graphiteRaised,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'delete') onDelete!();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.danger),
                      const SizedBox(width: 10),
                      Text('Delete spec',
                          style: GoogleFonts.inter(color: AppColors.danger)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Two-column row: muted label on the left, cream value on the right, with an
/// optional trailing widget (e.g. a delete button). Expanded flexes keep it
/// from overflowing on narrow widths.
class _TwoColumnRow extends StatelessWidget {
  const _TwoColumnRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, trailing == null ? 16 : 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.cream,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Brand-dark card shell used by both the identity card and the specs list.
class _SpecsCard extends StatelessWidget {
  const _SpecsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppDecorations.glassCard(radius: 12),
      child: child,
    );
  }
}

/// Bottom sheet to add a spec. Pops with `true` on a successful insert.
class _AddSpecSheet extends StatefulWidget {
  const _AddSpecSheet({required this.carId});

  final String carId;

  @override
  State<_AddSpecSheet> createState() => _AddSpecSheetState();
}

class _AddSpecSheetState extends State<_AddSpecSheet> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _value = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _value.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final client = Supabase.instance.client;
    try {
      await client.from('car_specs').insert({
        'car_id': widget.carId,
        'label': _label.text.trim(),
        'value': _value.text.trim(),
      }).select();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      _fail('Save failed: ${e.message}');
    } catch (e) {
      _fail('Could not save the spec: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
    setState(() => _saving = false);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCapitalization,
      validator: _required,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pad for the keyboard so it never covers the fields.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add spec',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.cream,
              ),
            ),
            const SizedBox(height: 20),
            _field(
              _label,
              'Label *',
              hint: 'e.g. Power',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            _field(_value, 'Value *', hint: 'e.g. 473 hp'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onEmber,
                      ),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
