import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/add_car_screen.dart';
import 'package:torqueden/screens/camera_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';

/// Create-post flow launched from the centre "+" button.
///
/// A post is photos and/or short clips with a caption, attached to one of your
/// cars. It's saved as a (non-silent) build entry so it also lands on
/// followers' feeds. Pops `true` once a post is published.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _client = Supabase.instance.client;
  final _caption = TextEditingController();

  static const _videoExts = {'mp4', 'mov', 'webm', 'avi', 'mkv', 'm4v'};
  final List<({String name, Uint8List bytes, bool isVideo})> _media = [];

  late Future<List<Car>> _carsFuture;
  Car? _selectedCar;
  bool _posting = false;

  // Optional "link to a mod" — the selected car's categorised build entries.
  List<({String id, String label})> _mods = const [];
  String? _selectedModId;

  @override
  void initState() {
    super.initState();
    _carsFuture = _loadCars();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<List<Car>> _loadCars() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('cars')
        .select()
        .eq('owner_id', uid)
        .order('created_at');
    final cars = rows.map(Car.fromMap).toList();
    // Default to the first car so posting is one fewer tap.
    _selectedCar ??= cars.isNotEmpty ? cars.first : null;
    if (_selectedCar != null) await _reloadModsFor(_selectedCar!.id);
    return cars;
  }

  /// Loads the given car's mods (categorised build entries) for the link picker.
  Future<void> _reloadModsFor(String carId) async {
    final rows = await _client
        .from('build_entries')
        .select('id, title, category')
        .eq('car_id', carId)
        .not('category', 'is', null)
        .order('created_at', ascending: false);
    _mods = [
      for (final r in rows)
        (id: r['id'] as String, label: '${r['category']} · ${r['title']}'),
    ];
  }

  Future<void> _onCarChanged(Car? car) async {
    setState(() {
      _selectedCar = car;
      _selectedModId = null;
      _mods = const [];
    });
    if (car != null) {
      await _reloadModsFor(car.id);
      if (mounted) setState(() {});
    }
  }

  /// Asks whether to shoot in-app or pick from the library, then runs it.
  Future<void> _pickSource() async {
    final choice = await showModalBottomSheet<String>(
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
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.ember),
              title: const Text('Camera'),
              subtitle: const Text('Record a clip or take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.ember),
              title: const Text('Library'),
              subtitle: const Text('Choose existing photos or clips'),
              onTap: () => Navigator.pop(ctx, 'library'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'camera') {
      await _openCamera();
    } else if (choice == 'library') {
      await _addMedia();
    }
  }

  /// Opens the in-app camera and adds whatever was captured.
  Future<void> _openCamera() async {
    final cap = await Navigator.of(context).push<CapturedMedia>(
      MaterialPageRoute(builder: (_) => const CameraScreen(), fullscreenDialog: true),
    );
    if (cap != null && mounted) {
      setState(() => _media.add(
            (name: cap.name, bytes: cap.bytes, isVideo: cap.isVideo),
          ));
    }
  }

  /// Opens the in-app photo editor (crop, rotate, filters…) for one photo and
  /// replaces it with the edited result. No-op for video.
  Future<void> _editPhoto(int index) async {
    final original = _media[index];
    if (original.isVideo) return;
    Uint8List? edited;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (editorContext) => ProImageEditor.memory(
          original.bytes,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async => edited = bytes,
            onCloseEditor: (_) => Navigator.of(editorContext).pop(),
          ),
        ),
      ),
    );
    if (edited != null && mounted) {
      setState(() => _media[index] =
          (name: original.name, bytes: edited!, isVideo: false));
    }
  }

  Future<void> _addMedia() async {
    final files = await ImagePicker().pickMultipleMedia();
    if (files.isEmpty) return;
    final added = <({String name, Uint8List bytes, bool isVideo})>[];
    for (final f in files) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      added.add((
        name: f.name,
        bytes: await f.readAsBytes(),
        isVideo: _videoExts.contains(ext),
      ));
    }
    if (!mounted) return;
    setState(() => _media.addAll(added));
  }

  // A post needs a car and at least one of: a caption, or some media.
  bool get _canPost =>
      !_posting &&
      _selectedCar != null &&
      (_media.isNotEmpty || _caption.text.trim().isNotEmpty);

  Future<void> _post() async {
    final car = _selectedCar;
    final caption = _caption.text.trim();
    if (car == null || (caption.isEmpty && _media.isEmpty)) return;

    // Title is required by the table; use the caption, else a sensible label
    // for a caption-less media post.
    final title = caption.isNotEmpty
        ? caption
        : 'Posted ${_media.length} ${_media.length == 1 ? 'item' : 'items'}';

    setState(() => _posting = true);
    try {
      // 1. The build entry carrying the caption (non-silent → hits feeds).
      final inserted = await _client.from('build_entries').insert({
        'car_id': car.id,
        'title': title,
        'silent': false,
        'linked_build_entry_id': _selectedModId,
      }).select();
      final entryId = inserted.first['id'] as String;

      // 2. Upload each media file, then record it in post_media.
      final uid = _client.auth.currentUser!.id;
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
        await _client.storage.from(kCarPhotosBucket).uploadBinary(
              path,
              m.bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
        mediaRows.add({
          'build_entry_id': entryId,
          'car_id': car.id,
          'url': _client.storage.from(kCarPhotosBucket).getPublicUrl(path),
          'kind': m.isVideo ? 'video' : 'image',
          'position': i,
        });
      }
      await _client.from('post_media').insert(mediaRows);

      if (mounted) Navigator.of(context).pop(true);
    } on StorageException catch (e) {
      _fail('Upload failed: ${e.message}');
    } on PostgrestException catch (e) {
      _fail('Post failed: ${e.message}');
    } catch (e) {
      _fail('Could not publish the post: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
    setState(() => _posting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _canPost ? _post : null,
              child: Text(
                'Post',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: _canPost ? AppColors.ember : AppColors.steel,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<Car>>(
          future: _carsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.ember),
              );
            }
            final cars = snapshot.data ?? const <Car>[];
            if (cars.isEmpty) {
              return EmptyState(
                icon: Icons.directions_car_outlined,
                title: 'Add a car first',
                message: 'Posts live on a car\'s profile. Add your car, then post.',
                action: FilledButton.icon(
                  onPressed: () async {
                    final added = await Navigator.of(context).push<Car>(
                      MaterialPageRoute(builder: (_) => const AddCarScreen()),
                    );
                    if (added != null && mounted) {
                      setState(() {
                        _selectedCar = added;
                        _carsFuture = _loadCars();
                      });
                    }
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add a car'),
                ),
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _MediaPicker(
                      media: _media,
                      onAdd: _posting ? null : _pickSource,
                      onRemove: _posting
                          ? null
                          : (i) => setState(() => _media.removeAt(i)),
                      onEdit: _posting ? null : _editPhoto,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _caption,
                      onChanged: (_) => setState(() {}), // refresh Post enabled
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 6,
                      minLines: 3,
                      style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                      decoration: const InputDecoration(
                        labelText: 'Caption',
                        hintText: 'Say something… (a text-only post is fine)',
                      ),
                    ),
                    const SizedBox(height: 18),
                    _CarSelector(
                      cars: cars,
                      selected: _selectedCar,
                      onChanged: _posting ? null : _onCarChanged,
                    ),
                    if (_mods.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _ModSelector(
                        mods: _mods,
                        selectedId: _selectedModId,
                        onChanged: _posting
                            ? null
                            : (id) => setState(() => _selectedModId = id),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_posting)
                      const Center(
                        child: CircularProgressIndicator(color: AppColors.ember),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _canPost ? _post : null,
                        icon: const Icon(Icons.local_fire_department, size: 20),
                        label: const Text('Post'),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Your post appears on the car\'s profile and on your followers\' feeds.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The media strip: an "add" tile plus a horizontal row of chosen thumbnails.
class _MediaPicker extends StatelessWidget {
  const _MediaPicker({
    required this.media,
    required this.onAdd,
    required this.onRemove,
    required this.onEdit,
  });

  final List<({String name, Uint8List bytes, bool isVideo})> media;
  final VoidCallback? onAdd;
  final void Function(int)? onRemove;
  final void Function(int)? onEdit;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: Material(
          color: AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onAdd,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairline),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.steel),
                  SizedBox(height: 10),
                  Text('Add photos or clips',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: media.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == media.length) {
            return _AddTile(onTap: onAdd);
          }
          final m = media[i];
          return _Thumb(
            bytes: m.bytes,
            isVideo: m.isVideo,
            onRemove: onRemove == null ? null : () => onRemove!(i),
            onEdit: (m.isVideo || onEdit == null) ? null : () => onEdit!(i),
          );
        },
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          color: AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        child: const Icon(Icons.add, color: AppColors.steel, size: 30),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.bytes,
    required this.isVideo,
    this.onRemove,
    this.onEdit,
  });

  final Uint8List bytes;
  final bool isVideo;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: isVideo
              ? Container(
                  width: 108,
                  height: 108,
                  color: AppColors.graphiteRaised,
                  alignment: Alignment.center,
                  child: const Icon(Icons.videocam, color: AppColors.steel, size: 30),
                )
              : Image.memory(bytes, width: 108, height: 108, fit: BoxFit.cover),
        ),
        if (isVideo)
          const Positioned(
            left: 6,
            bottom: 6,
            child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 22),
          ),
        if (onEdit != null)
          Positioned(
            left: 6,
            bottom: 6,
            child: GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune, size: 13, color: AppColors.cream),
                    SizedBox(width: 4),
                    Text('Edit', style: TextStyle(color: AppColors.cream, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        if (onRemove != null)
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
                child: const Icon(Icons.close, size: 16, color: AppColors.cream),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dropdown to choose which of your cars the post belongs to.
class _CarSelector extends StatelessWidget {
  const _CarSelector({
    required this.cars,
    required this.selected,
    required this.onChanged,
  });

  final List<Car> cars;
  final Car? selected;
  final ValueChanged<Car?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Car>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Post to'),
      dropdownColor: AppColors.graphiteRaised,
      style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
      iconEnabledColor: AppColors.steel,
      items: [
        for (final c in cars)
          DropdownMenuItem(value: c, child: Text(c.title)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Optional dropdown to link this post to a mod in the car's build list.
class _ModSelector extends StatelessWidget {
  const _ModSelector({
    required this.mods,
    required this.selectedId,
    required this.onChanged,
  });

  final List<({String id, String label})> mods;
  final String? selectedId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: selectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Link to a mod (optional)',
        prefixIcon: Icon(Icons.build_outlined, color: AppColors.steel, size: 20),
      ),
      dropdownColor: AppColors.graphiteRaised,
      style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
      iconEnabledColor: AppColors.steel,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'No linked mod',
            style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15),
          ),
        ),
        for (final m in mods)
          DropdownMenuItem<String?>(
            value: m.id,
            child: Text(m.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
