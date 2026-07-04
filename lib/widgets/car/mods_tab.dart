import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/mod.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';

/// Preset categories offered when logging a mod. "Other" is the fallback.
const List<String> kModCategories = [
  'Engine / Tune',
  'Intake',
  'Exhaust',
  'Suspension',
  'Wheels & Tyres',
  'Brakes',
  'Exterior',
  'Interior',
  'Drivetrain',
  'Other',
];

/// Mods tab on the car detail screen — the parts list for a single car,
/// loaded live from Supabase. Self-contained so it can live in a TabBarView.
class ModsTab extends StatefulWidget {
  const ModsTab({super.key, required this.car});

  final Car car;

  @override
  State<ModsTab> createState() => _ModsTabState();
}

class _ModsTabState extends State<ModsTab> {
  final _client = Supabase.instance.client;
  late Future<List<Mod>> _modsFuture;

  @override
  void initState() {
    super.initState();
    _modsFuture = _loadMods();
  }

  Future<List<Mod>> _loadMods() async {
    final rows = await _client
        .from('mods')
        .select()
        .eq('car_id', widget.car.id)
        .order('created_at', ascending: false);
    return rows.map(Mod.fromMap).toList();
  }

  Future<void> _refresh() async {
    // Block body, not an arrow: setState() throws if its callback returns a
    // Future, so we assign inside and await the local.
    final future = _loadMods();
    setState(() {
      _modsFuture = future;
    });
    await future;
  }

  /// Opens the add/edit sheet. Returns true once a row is saved.
  Future<void> _openEditor() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ModEditorSheet(carId: widget.car.id),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _confirmDelete(Mod mod) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text(
          'Delete mod?',
          style: GoogleFonts.archivo(
            fontWeight: FontWeight.w700,
            color: AppColors.cream,
          ),
        ),
        content: Text(
          'Remove "${mod.name}" from this build? This can\'t be undone.',
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
      await _client.from('mods').delete().eq('id', mod.id);
      if (!mounted) return;
      await _refresh();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the mod: $e')),
      );
    }
  }

  /// Groups mods by category — preset categories first (in their canonical
  /// order), then any others — skipping empty categories.
  List<(String, List<Mod>)> _groupByCategory(List<Mod> mods) {
    final byCat = <String, List<Mod>>{};
    for (final m in mods) {
      byCat.putIfAbsent(m.category, () => <Mod>[]).add(m);
    }
    final ordered = <(String, List<Mod>)>[];
    for (final c in kModCategories) {
      final list = byCat.remove(c);
      if (list != null) ordered.add((c, list));
    }
    for (final entry in byCat.entries) {
      ordered.add((entry.key, entry.value));
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Mod>>(
      future: _modsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.ember),
          );
        }
        if (snapshot.hasError) {
          return RefreshIndicator(
            color: AppColors.ember,
            backgroundColor: AppColors.graphite,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6,
                  child: EmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load mods',
                    message: '${snapshot.error}',
                    action: FilledButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final mods = snapshot.data ?? const <Mod>[];

        return RefreshIndicator(
          color: AppColors.ember,
          backgroundColor: AppColors.graphite,
          onRefresh: _refresh,
          child: mods.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.6,
                      child: EmptyState(
                        icon: Icons.build_outlined,
                        title: 'No mods logged yet',
                        message: 'Add the first mod to start the list.',
                        action: FilledButton.icon(
                          onPressed: _openEditor,
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Add mod'),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _openEditor,
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Add mod'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final group in _groupByCategory(mods))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CategorySection(
                          category: group.$1,
                          mods: group.$2,
                          onDelete: _confirmDelete,
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// A collapsible category group: a tappable header (name + count + chevron),
/// with slim mod rows underneath. Expanded by default.
class _CategorySection extends StatefulWidget {
  const _CategorySection({
    required this.category,
    required this.mods,
    required this.onDelete,
  });

  final String category;
  final List<Mod> mods;
  final void Function(Mod) onDelete;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.category,
                      style: GoogleFonts.archivo(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.graphiteRaised,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.mods.length}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.steel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more, color: AppColors.steel),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final mod in widget.mods) ...[
              const Divider(height: 1, color: AppColors.hairline),
              _ModRow(mod: mod, onDelete: () => widget.onDelete(mod)),
            ],
        ],
      ),
    );
  }
}

/// A slim row for one mod inside a category group.
class _ModRow extends StatelessWidget {
  const _ModRow({required this.mod, required this.onDelete});

  final Mod mod;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final notes = mod.notes?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mod.name,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cream,
                  ),
                ),
                if (hasNotes) ...[
                  const SizedBox(height: 2),
                  Text(
                    notes,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.steel,
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete mod',
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet form for adding a mod. Pops `true` once the row is saved.
class _ModEditorSheet extends StatefulWidget {
  const _ModEditorSheet({required this.carId});

  final String carId;

  @override
  State<_ModEditorSheet> createState() => _ModEditorSheetState();
}

class _ModEditorSheetState extends State<_ModEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _notes = TextEditingController();

  String _category = 'Other';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _save({required bool post}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final client = Supabase.instance.client;
    final name = _name.text.trim();
    final notes = _notes.text.trim();

    try {
      // .select() so the future completes (esp. on web) once the row lands.
      await client.from('mods').insert({
        'car_id': widget.carId,
        'category': _category,
        'name': name,
        'notes': notes.isEmpty ? null : notes,
      }).select();

      // Posting a mod also drops an update onto followers' feeds.
      if (post) {
        await client.from('build_entries').insert({
          'car_id': widget.carId,
          'title': 'Added $name',
          'body': notes.isEmpty ? '$_category mod fitted.' : notes,
          'silent': false,
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      _fail('Save failed: ${e.message}');
    } catch (e) {
      _fail('Could not save the mod: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    // Pad for the keyboard so it never covers the fields.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 20 + bottomInset,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Add mod',
                style: GoogleFonts.archivo(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cream,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                dropdownColor: AppColors.graphiteRaised,
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                iconEnabledColor: AppColors.steel,
                items: [
                  for (final c in kModCategories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: _saving
                    ? null
                    : (v) {
                        if (v != null) setState(() => _category = v);
                      },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g. Cat-back exhaust',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Brand, specs, install notes…',
                ),
              ),
              const SizedBox(height: 24),
              if (_saving)
                const Center(child: CircularProgressIndicator(color: AppColors.ember))
              else
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        onPressed: () => _save(post: true),
                        icon: const Icon(Icons.local_fire_department, size: 18),
                        label: const Text('Post update'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: () => _save(post: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.steel,
                          side: const BorderSide(color: AppColors.hairline),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Silent'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                'Post update shares it to followers’ feeds. Silent just adds the mod.',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
