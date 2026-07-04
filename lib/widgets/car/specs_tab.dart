import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/car_spec.dart';
import 'package:torqueden/theme.dart';

/// Specs tab for a car's detail view.
///
/// Shows a fixed "identity" card built from the [Car] object itself, then a
/// "Performance & specs" section of free-form label/value rows loaded live from
/// the `car_specs` table (addable and deletable). Self-contained scrollable so
/// it works as a [TabBarView] child.
class SpecsTab extends StatefulWidget {
  const SpecsTab({super.key, required this.car});

  final Car car;

  @override
  State<SpecsTab> createState() => _SpecsTabState();
}

class _SpecsTabState extends State<SpecsTab> {
  final _client = Supabase.instance.client;
  late Future<List<CarSpec>> _specsFuture;

  @override
  void initState() {
    super.initState();
    _specsFuture = _loadSpecs();
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
          style: GoogleFonts.archivo(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete spec: $e')),
      );
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
          _IdentityCard(car: widget.car),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Performance & specs',
                  style: GoogleFonts.archivo(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cream,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openAddSpec,
                icon: const Icon(Icons.add, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ember,
                  side: const BorderSide(color: AppColors.hairline),
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
                            side: const BorderSide(color: AppColors.hairline),
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
                        const Divider(height: 1, color: AppColors.hairline),
                      _SpecRow(
                        spec: specs[i],
                        onDelete: () => _deleteSpec(specs[i]),
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

/// Fixed card describing the car, built from the [Car] object (not the DB).
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.car});

  final Car car;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
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
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.hairline),
            _TwoColumnRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

/// One DB-backed spec row: label/value plus a delete button.
class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.spec, required this.onDelete});

  final CarSpec spec;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _TwoColumnRow(
      label: spec.label,
      value: spec.value,
      trailing: IconButton(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline, size: 20),
        color: AppColors.textMuted,
        tooltip: 'Delete spec',
        visualDensity: VisualDensity.compact,
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
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
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
              style: GoogleFonts.archivo(
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
