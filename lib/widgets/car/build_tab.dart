import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/features.dart';
import 'package:torqueden/models/build_entry.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/link_guard.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/post_media_view.dart';

/// Preset mod categories offered when logging a build update. An update can be
/// left uncategorised (a plain milestone/fix/plan) or tagged as a specific mod.
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

/// Build-log tab for a car: a dated timeline of updates and mods. Each entry is
/// date-stamped and can carry an optional mod category. Self-contained
/// scrollable so it slots straight into a TabBarView.
class BuildTab extends StatefulWidget {
  const BuildTab({super.key, required this.car});

  final Car car;

  @override
  State<BuildTab> createState() => _BuildTabState();
}

class _BuildTabState extends State<BuildTab> {
  final _client = Supabase.instance.client;
  late Future<List<BuildEntry>> _entriesFuture;

  /// Only the car's owner can add/edit/delete build updates.
  bool get _canManage {
    final uid = _client.auth.currentUser?.id;
    return uid != null && widget.car.ownerId != null && uid == widget.car.ownerId;
  }

  @override
  void initState() {
    super.initState();
    _entriesFuture = _load();
  }

  Future<List<BuildEntry>> _load() async {
    final rows = await _client
        .from('build_entries')
        .select(
          '*, post_media(id, url, kind, position), '
          'linked:linked_build_entry_id(title, category)',
        )
        .eq('car_id', widget.car.id)
        .order('created_at', ascending: false);
    return rows.map(BuildEntry.fromMap).toList();
  }

  Future<void> _refresh() async {
    // Block body, not an arrow: setState() throws if its callback returns the
    // Future.
    final future = _load();
    setState(() {
      _entriesFuture = future;
    });
    await future;
  }

  Future<void> _openEditor({BuildEntry? entry}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BuildEntrySheet(carId: widget.car.id, entry: entry),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _confirmDelete(BuildEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text(
          'Delete this update?',
          style: GoogleFonts.archivo(
            fontWeight: FontWeight.w700,
            color: AppColors.cream,
          ),
        ),
        content: Text(
          'This removes "${entry.title}" from the build log. This can\'t be undone.',
          style: GoogleFonts.inter(color: AppColors.textSecondary, height: 1.5),
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
      await _client.from('build_entries').delete().eq('id', entry.id);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.message}')),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the update: $e')),
      );
      return;
    }
    if (!mounted) return;
    await _refresh();
  }

  /// Bucket for entries with no mod category.
  static const _generalLabel = 'General';

  /// Group entries by category label (uncategorised → "General").
  Map<String, List<BuildEntry>> _group(List<BuildEntry> entries) {
    final map = <String, List<BuildEntry>>{};
    for (final e in entries) {
      // Own category, else the linked mod's category, else General — so a post
      // linked to (say) a Suspension mod files under Suspension.
      final key = e.effectiveCategory ?? _generalLabel;
      (map[key] ??= []).add(e);
    }
    return map;
  }

  /// Categories to show, in preset order, then any stragglers, "General" last.
  List<String> _orderedKeys(Map<String, List<BuildEntry>> grouped) {
    final keys = <String>[
      for (final c in kModCategories)
        if (grouped.containsKey(c)) c,
      for (final k in grouped.keys)
        if (!kModCategories.contains(k) && k != _generalLabel) k,
    ];
    if (grouped.containsKey(_generalLabel)) keys.add(_generalLabel);
    return keys;
  }

  /// Drill into a single entry: full detail sheet, with owner edit/delete.
  /// Tapping a category card brings up every mod in that section.
  Future<void> _openCategory(String label, List<BuildEntry> entries) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _CategorySheet(
        label: label,
        entries: entries,
        canManage: _canManage,
        onEdit: (entry) {
          Navigator.of(sheetCtx).pop();
          _openEditor(entry: entry);
        },
        onDelete: (entry) {
          Navigator.of(sheetCtx).pop();
          _confirmDelete(entry);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.ember,
      backgroundColor: AppColors.graphite,
      onRefresh: _refresh,
      child: FutureBuilder<List<BuildEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 80),
                child: CircularProgressIndicator(color: AppColors.ember),
              ),
            );
          }
          if (snapshot.hasError) {
            // ListView so the RefreshIndicator still works on the error state.
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load the build log',
                  message: '${snapshot.error}',
                  action: FilledButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            );
          }

          final entries = snapshot.data ?? const <BuildEntry>[];
          if (entries.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.timeline_outlined,
                  title: 'No build updates yet',
                  message: _canManage
                      ? 'Log your first update — a milestone, a fix, a plan.'
                      : 'This build doesn\'t have any updates yet.',
                  action: _canManage
                      ? FilledButton.icon(
                          onPressed: _openEditor,
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Add update'),
                        )
                      : null,
                ),
              ],
            );
          }

          // Category grid: entries grouped into fixed cards, each previewing up
          // to three slots with a pop-down drill-in for the rest.
          final grouped = _group(entries);
          final keys = _orderedKeys(grouped);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              if (_canManage) ...[
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Add update'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ember,
                      side: const BorderSide(color: AppColors.hairline),
                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final cardW = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final k in keys)
                        SizedBox(
                          width: cardW,
                          child: _CategoryCard(
                            label: k,
                            entries: grouped[k]!,
                            onOpen: () => _openCategory(k, grouped[k]!),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One category cell in the build grid: a labelled card previewing up to two
/// entry slots (with a three-dot "more" hint when there are others). Tapping
/// anywhere on the card — header or a slot — brings up every mod in the section.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.label,
    required this.entries,
    required this.onOpen,
  });

  final String label;
  final List<BuildEntry> entries;
  final VoidCallback onOpen;

  static const _slots = 2;

  @override
  Widget build(BuildContext context) {
    final hasMore = entries.length > _slots;
    final visible = entries.take(_slots).toList();

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.graphite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.ember,
                    ),
                  ),
                ),
                Text(
                  '${entries.length}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.steel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final e in visible) _EntrySlot(entry: e),
            // Faint placeholders fill an under-filled card up to the slot count
            // so cards paired in a row line up and the grid reads evenly.
            for (var i = visible.length; i < _slots; i++) const _GhostSlot(),
            // Reserve a matching bottom row on every card — a centred three-dot
            // hint when there are more mods than shown, else an empty spacer —
            // so collapsed cards stay level.
            SizedBox(
              height: 22,
              width: double.infinity,
              child: hasMore
                  ? const Center(
                      child: Icon(Icons.more_horiz, size: 18, color: AppColors.steel),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single compact entry row inside a category card: title + date + media hint.
/// Display-only — the whole card handles the tap.
class _EntrySlot extends StatelessWidget {
  const _EntrySlot({required this.entry});

  final BuildEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(color: AppColors.ember, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cream,
                  ),
                ),
                Text(
                  _formatDate(entry.createdAt),
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (entry.hasMedia)
            const Icon(Icons.photo_outlined, size: 14, color: AppColors.steel),
        ],
      ),
    );
  }
}

/// A faint, empty placeholder occupying one slot — used to pad short cards so
/// the grid rows line up. Matches an [_EntrySlot]'s footprint.
class _GhostSlot extends StatelessWidget {
  const _GhostSlot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.hairline.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.hairline.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing every mod in one category — opened by tapping a card.
class _CategorySheet extends StatelessWidget {
  const _CategorySheet({
    required this.label,
    required this.entries,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final String label;
  final List<BuildEntry> entries;
  final bool canManage;
  final void Function(BuildEntry) onEdit;
  final void Function(BuildEntry) onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.ember,
                      ),
                    ),
                  ),
                  Text(
                    entries.length == 1 ? '1 mod' : '${entries.length} mods',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.steel,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: AppColors.hairline, height: 28),
                itemBuilder: (_, i) => _EntryDetailBlock(
                  entry: entries[i],
                  canManage: canManage,
                  onEdit: () => onEdit(entries[i]),
                  onDelete: () => onDelete(entries[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full detail of one entry within the category sheet: date, title, media,
/// body, linked-mod, plus edit/delete for the owner.
class _EntryDetailBlock extends StatelessWidget {
  const _EntryDetailBlock({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final BuildEntry entry;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final body = entry.body?.trim();
    final hasBody = body != null && body.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatDate(entry.createdAt).toUpperCase(),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0.5,
            color: AppColors.ember,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entry.title,
          style: GoogleFonts.archivo(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.cream,
          ),
        ),
        if (entry.hasMedia) ...[
          const SizedBox(height: 12),
          PostMediaView(media: entry.media),
        ],
        if (hasBody) ...[
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary, height: 1.5),
          ),
        ],
        if (entry.hasLinkedMod) ...[
          const SizedBox(height: 12),
          LinkedModChip(label: entry.linkedModLabel!),
        ],
        if (canManage) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ember,
                    side: const BorderSide(color: AppColors.hairline),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.hairline),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A pill marking that a post is linked to a mod in the build list.
class LinkedModChip extends StatelessWidget {
  const LinkedModChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.build, size: 13, color: AppColors.ember),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.cream,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to add or edit a build-log update. Pops `true` after a
/// successful save. Pass [entry] to edit an existing update.
class _BuildEntrySheet extends StatefulWidget {
  const _BuildEntrySheet({required this.carId, this.entry});

  final String carId;
  final BuildEntry? entry;

  @override
  State<_BuildEntrySheet> createState() => _BuildEntrySheetState();
}

class _BuildEntrySheetState extends State<_BuildEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  /// Optional mod category; null means "general update".
  String? _category;
  bool _saving = false;

  bool get _isEditing => widget.entry != null;

  // Media chosen but not yet uploaded (held as bytes for preview + upload).
  static const _videoExts = {'mp4', 'mov', 'webm', 'avi', 'mkv', 'm4v'};
  final List<({String name, Uint8List bytes, bool isVideo})> _media = [];

  // When editing: existing media still attached, and the ids the user removed.
  final List<PostMedia> _existing = [];
  final Set<String> _removedMediaIds = {};

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e != null) {
      _title.text = e.title;
      _body.text = e.body ?? '';
      _category = e.category;
      _existing.addAll(e.media);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _addMedia() async {
    // Video on: photos AND videos together. Video off (launch): photos only.
    final files = Features.video
        ? await ImagePicker().pickMultipleMedia()
        : await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    final added = <({String name, Uint8List bytes, bool isVideo})>[];
    for (final f in files) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      added.add((name: f.name, bytes: await f.readAsBytes(), isVideo: _videoExts.contains(ext)));
    }
    if (!mounted) return;
    setState(() => _media.addAll(added));
  }

  Future<void> _save({bool silent = false}) async {
    if (!_formKey.currentState!.validate()) return;
    // Build updates are promotion-free — links belong on a Partner Page.
    if (containsUrl(_title.text) || containsUrl(_body.text)) {
      _fail('Links aren\'t allowed in build updates. Businesses can add their website on a Partner Page.');
      return;
    }
    setState(() => _saving = true);

    final client = Supabase.instance.client;
    final body = _body.text.trim();
    final title = _title.text.trim();

    try {
      final String entryId;
      final int mediaStart; // position offset for any newly-added media
      if (_isEditing) {
        // Update text fields in place; leave the silent/created_at values as-is.
        entryId = widget.entry!.id;
        mediaStart = widget.entry!.media.length;
        await client.from('build_entries').update({
          'title': title,
          'body': body.isEmpty ? null : body,
          'category': _category,
        }).eq('id', entryId);
        // Drop any existing media the user removed.
        if (_removedMediaIds.isNotEmpty) {
          await client.from('post_media').delete().inFilter('id', _removedMediaIds.toList());
        }
      } else {
        // .select() so the future completes (esp. on web) and returns the row id.
        final inserted = await client.from('build_entries').insert({
          'car_id': widget.carId,
          'title': title,
          'body': body.isEmpty ? null : body,
          'category': _category, // optional mod tag; null for a general update
          'silent': silent, // silent updates stay off followers' feeds
          // created_at uses the table's DB default.
        }).select();
        entryId = inserted.first['id'] as String;
        mediaStart = 0;
      }

      if (_media.isNotEmpty) {
        final uid = client.auth.currentUser!.id;
        final mediaRows = <Map<String, dynamic>>[];
        for (var i = 0; i < _media.length; i++) {
          final m = _media[i];
          final ext = m.name.contains('.')
              ? m.name.split('.').last.toLowerCase()
              : (m.isVideo ? 'mp4' : 'jpg');
          final contentType = m.isVideo
              ? switch (ext) {
                  'webm' => 'video/webm',
                  'mov' => 'video/quicktime',
                  _ => 'video/mp4',
                }
              : switch (ext) {
                  'png' => 'image/png',
                  'webp' => 'image/webp',
                  'gif' => 'image/gif',
                  _ => 'image/jpeg',
                };
          final pos = mediaStart + i; // append after any existing media
          final path = '$uid/${entryId}_$pos.$ext';
          await client.storage.from('car-photos').uploadBinary(
                path,
                m.bytes,
                fileOptions: FileOptions(contentType: contentType),
              );
          mediaRows.add({
            'build_entry_id': entryId,
            'car_id': widget.carId,
            'url': client.storage.from('car-photos').getPublicUrl(path),
            'kind': m.isVideo ? 'video' : 'image',
            'position': pos,
          });
        }
        await client.from('post_media').insert(mediaRows);
      }

      if (mounted) Navigator.of(context).pop(true);
    } on StorageException catch (e) {
      _fail('Upload failed: ${e.message}');
    } on PostgrestException catch (e) {
      _fail('Save failed: ${e.message}');
    } catch (e) {
      _fail('Could not save the update: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
    setState(() => _saving = false);
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    // Pad for the keyboard so it never covers the fields.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + bottomInset,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEditing ? 'Edit update' : 'Add update',
                  style: GoogleFonts.archivo(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppColors.cream,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String?>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category (optional)'),
                  dropdownColor: AppColors.graphiteRaised,
                  style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                  iconEnabledColor: AppColors.steel,
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'General update',
                        style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15),
                      ),
                    ),
                    for (final c in kModCategories)
                      DropdownMenuItem<String?>(value: c, child: Text(c)),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    hintText: 'e.g. Fitted coilovers',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _body,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Details (optional)',
                    hintText: 'What changed, parts used, next steps…',
                  ),
                ),
                if (_existing.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Current media',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _existing.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final m = _existing[i];
                        return _ExistingThumb(
                          media: m,
                          onRemove: _saving
                              ? null
                              : () => setState(() {
                                    _removedMediaIds.add(m.id);
                                    _existing.remove(m);
                                  }),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addMedia,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                    label: Text(_media.isEmpty && _existing.isEmpty ? 'Add photos / video' : 'Add more'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ember,
                      side: const BorderSide(color: AppColors.hairline),
                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (_media.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _media.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => _MediaThumb(
                        bytes: _media[i].bytes,
                        isVideo: _media[i].isVideo,
                        onRemove: _saving ? null : () => setState(() => _media.removeAt(i)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_saving)
                  const Center(child: CircularProgressIndicator(color: AppColors.ember))
                else if (_isEditing)
                  FilledButton(
                    onPressed: () => _save(),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const Text('Save changes'),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          onPressed: () => _save(silent: false),
                          icon: const Icon(Icons.local_fire_department, size: 18),
                          label: const Text('Post update'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => _save(silent: true),
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
                  _isEditing
                      ? 'Existing photos and videos are kept; anything you add here is appended.'
                      : 'Silent updates save to the build log but stay off your followers’ feeds.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A square preview of a chosen-but-not-yet-uploaded photo or video, with a
/// remove "x" (and a play badge for videos, which can't preview a frame here).
class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.bytes, required this.isVideo, this.onRemove});

  final Uint8List bytes;
  final bool isVideo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: isVideo
              ? Container(
                  width: 84,
                  height: 84,
                  color: AppColors.graphiteRaised,
                  alignment: Alignment.center,
                  child: const Icon(Icons.videocam, color: AppColors.steel, size: 28),
                )
              : Image.memory(bytes, width: 84, height: 84, fit: BoxFit.cover),
        ),
        if (isVideo)
          const Positioned(
            left: 6,
            bottom: 6,
            child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 20),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 15, color: AppColors.cream),
            ),
          ),
        ),
      ],
    );
  }
}

/// A square preview of an already-uploaded photo/video (edit mode), with a
/// remove "x". Removing it marks the media for deletion on save.
class _ExistingThumb extends StatelessWidget {
  const _ExistingThumb({required this.media, this.onRemove});

  final PostMedia media;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: media.isVideo
              ? Container(
                  width: 84,
                  height: 84,
                  color: AppColors.graphiteRaised,
                  alignment: Alignment.center,
                  child: const Icon(Icons.videocam, color: AppColors.steel, size: 28),
                )
              : Image.network(
                  media.url,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 84,
                    height: 84,
                    color: AppColors.graphiteRaised,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, color: AppColors.steel, size: 24),
                  ),
                ),
        ),
        if (media.isVideo)
          const Positioned(
            left: 6,
            bottom: 6,
            child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 20),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 15, color: AppColors.cream),
            ),
          ),
        ),
      ],
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a date like "30 Jun 2026" without pulling in the intl package.
String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
