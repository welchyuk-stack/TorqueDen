import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/build_entry.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _entriesFuture = _load();
  }

  Future<List<BuildEntry>> _load() async {
    final rows = await _client
        .from('build_entries')
        .select('*, post_media(id, url, kind, position)')
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

  Future<void> _openEditor() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BuildEntrySheet(carId: widget.car.id),
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
                  message: 'Log your first update — a milestone, a fix, a plan.',
                  action: FilledButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Add update'),
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: entries.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Add update'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ember,
                      side: const BorderSide(color: AppColors.hairline),
                      textStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                );
              }
              final entry = entries[i - 1];
              return _BuildEntryCard(
                entry: entry,
                onDelete: () => _confirmDelete(entry),
              );
            },
          );
        },
      ),
    );
  }
}

/// One card in the build timeline: date, title, optional body, delete action.
class _BuildEntryCard extends StatelessWidget {
  const _BuildEntryCard({required this.entry, required this.onDelete});

  final BuildEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final body = entry.body?.trim();
    final hasBody = body != null && body.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (entry.hasCategory) ...[
                          _CategoryChip(label: entry.category!),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            _formatDate(entry.createdAt).toUpperCase(),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              letterSpacing: 0.5,
                              color: AppColors.ember,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.title,
                      style: GoogleFonts.archivo(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: AppColors.cream,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.steel,
                tooltip: 'Delete update',
              ),
            ],
          ),
          if (entry.hasMedia) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PostMediaView(media: entry.media),
            ),
          ],
          if (hasBody) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small pill showing an entry's mod category, e.g. "EXHAUST".
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.steel,
        ),
      ),
    );
  }
}

/// Bottom sheet to add a build-log update. Pops `true` after a successful save.
class _BuildEntrySheet extends StatefulWidget {
  const _BuildEntrySheet({required this.carId});

  final String carId;

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

  // Media chosen but not yet uploaded (held as bytes for preview + upload).
  static const _videoExts = {'mp4', 'mov', 'webm', 'avi', 'mkv', 'm4v'};
  final List<({String name, Uint8List bytes, bool isVideo})> _media = [];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _addMedia() async {
    // pickMultipleMedia lets the user choose photos AND videos together.
    final files = await ImagePicker().pickMultipleMedia();
    if (files.isEmpty) return;
    final added = <({String name, Uint8List bytes, bool isVideo})>[];
    for (final f in files) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      added.add((name: f.name, bytes: await f.readAsBytes(), isVideo: _videoExts.contains(ext)));
    }
    if (!mounted) return;
    setState(() => _media.addAll(added));
  }

  Future<void> _save({required bool silent}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final client = Supabase.instance.client;
    final body = _body.text.trim();
    final payload = {
      'car_id': widget.carId,
      'title': _title.text.trim(),
      'body': body.isEmpty ? null : body,
      'category': _category, // optional mod tag; null for a general update
      'silent': silent, // silent updates stay off followers' feeds
      // created_at uses the table's DB default.
    };

    try {
      // .select() so the future completes (esp. on web) and returns the row id.
      final inserted = await client.from('build_entries').insert(payload).select();
      final entryId = inserted.first['id'] as String;

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
          final path = '$uid/${entryId}_$i.$ext';
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
            'position': i,
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
                  'Add update',
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
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addMedia,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                    label: Text(_media.isEmpty ? 'Add photos / video' : 'Add more'),
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
                  'Silent updates save to the build log but stay off your followers’ feeds.',
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
