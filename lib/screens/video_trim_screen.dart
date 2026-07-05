import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/services/video_trim_service.dart';
import 'package:torqueden/theme.dart';
import 'package:video_player/video_player.dart';

/// The clip editor: trim + colour filters, applied in a single native
/// re-encode (AVFoundation — no ffmpeg). Pops the edited file path to use, or
/// the original path if nothing changed / an export fails. Text overlay is the
/// remaining editing phase.
class VideoTrimScreen extends StatefulWidget {
  const VideoTrimScreen({super.key, required this.inputPath});

  final String inputPath;

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  VideoPlayerController? _controller;
  double _startMs = 0;
  double _endMs = 0;
  double _totalMs = 0;
  String? _filterId; // null = no filter
  bool _exporting = false;

  // Text overlay.
  String? _text; // null = no caption
  double _textNormY = 0.82; // vertical centre (0 top … 1 bottom)
  double _textSize = 0.08; // font size as fraction of video height
  String _textColorHex = '#FFFFFF';

  static const _minClipMs = 500.0; // don't allow a trim shorter than 0.5s

  _VideoFilter get _filter => _filters.firstWhere((f) => f.id == _filterId);

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.file(File(widget.inputPath));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _totalMs = c.value.duration.inMilliseconds.toDouble();
        _endMs = _totalMs;
      });
      c.addListener(_loopWithinRange);
    });
  }

  // Keep playback inside the selected [start, end] window.
  void _loopWithinRange() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final posMs = c.value.position.inMilliseconds.toDouble();
    if (c.value.isPlaying && posMs >= _endMs) {
      c.seekTo(Duration(milliseconds: _startMs.toInt()));
      c.pause();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_loopWithinRange);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      final posMs = c.value.position.inMilliseconds.toDouble();
      if (posMs < _startMs || posMs >= _endMs) {
        await c.seekTo(Duration(milliseconds: _startMs.toInt()));
      }
      await c.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _done() async {
    final trimmed = _startMs > 0 || _endMs < _totalMs;
    final filtered = _filterId != null;
    final hasText = _text != null && _text!.trim().isNotEmpty;
    if (!trimmed && !filtered && !hasText) {
      await _finish(widget.inputPath); // nothing changed
      return;
    }
    setState(() => _exporting = true);
    try {
      var path = widget.inputPath;
      // 1. Trim + filter in one re-encode (if either changed).
      if (trimmed || filtered) {
        final out = await VideoTrimService.trim(
          path,
          Duration(milliseconds: _startMs.toInt()),
          Duration(milliseconds: _endMs.toInt()),
          filter: _filterId,
        );
        if (out != null) path = out;
      }
      // 2. Bake the caption over the result (a second pass, only if used).
      if (hasText) {
        final out = await VideoTrimService.overlayText(
          path,
          text: _text!.trim(),
          normY: _textNormY,
          sizeFraction: _textSize,
          colorHex: _textColorHex,
        );
        if (out != null) path = out;
      }
      await _finish(path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t process the clip — using the original.')),
      );
      await _finish(widget.inputPath);
    }
  }

  Future<void> _editText() async {
    final controller = TextEditingController(text: _text ?? '');
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Caption',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          style: GoogleFonts.inter(color: AppColors.cream),
          decoration: const InputDecoration(hintText: 'Your caption'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (entered != null) setState(() => _text = entered.isEmpty ? null : entered);
  }

  Color _hexColor(String hex) =>
      Color(int.parse(hex.replaceFirst('#', ''), radix: 16) | 0xFF000000);

  Widget _textTools() {
    final hasText = _text != null && _text!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _exporting ? null : _editText,
                icon: Icon(hasText ? Icons.edit : Icons.text_fields, size: 18),
                label: Text(hasText ? 'Edit text' : 'Add text'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ember,
                  side: const BorderSide(color: AppColors.hairline),
                ),
              ),
              if (hasText) ...[
                const Spacer(),
                IconButton(
                  onPressed: _exporting ? null : () => setState(() => _text = null),
                  icon: const Icon(Icons.close, size: 18, color: AppColors.steel),
                  tooltip: 'Remove text',
                ),
              ],
            ],
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  for (final hex in const ['#FFFFFF', '#111318', '#FF6A2B', '#FFD400'])
                    GestureDetector(
                      onTap: () => setState(() => _textColorHex = hex),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _hexColor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _textColorHex == hex ? AppColors.ember : AppColors.hairline,
                            width: _textColorHex == hex ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  _sizeChip('S', 0.05),
                  _sizeChip('M', 0.08),
                  _sizeChip('L', 0.12),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sizeChip(String label, double value) {
    final sel = _textSize == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: () => setState(() => _textSize = value),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? AppColors.ember : AppColors.graphiteRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? AppColors.ember : AppColors.hairline),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: sel ? AppColors.onEmber : AppColors.steel,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _finish(String path) async {
    if (!mounted) return;
    Navigator.of(context).pop(path);
  }

  String _fmt(double ms) {
    final total = (ms / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized && _totalMs > 0;
    final selMs = (_endMs - _startMs).clamp(0, _totalMs);
    final cf = _filter.colorFilter;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Edit clip'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exporting ? null : () => _finish(widget.inputPath),
        ),
      ),
      body: SafeArea(
        child: !ready
            ? const Center(child: CircularProgressIndicator(color: AppColors.ember))
            : Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              cf == null
                                  ? VideoPlayer(c)
                                  : ColorFiltered(colorFilter: cf, child: VideoPlayer(c)),
                              if (!c.value.isPlaying)
                                const DecoratedBox(
                                  decoration: BoxDecoration(color: Colors.black26),
                                  child: Center(
                                    child: Icon(Icons.play_arrow, size: 56, color: Colors.white),
                                  ),
                                ),
                              if (_text != null && _text!.trim().isNotEmpty)
                                Positioned.fill(
                                  child: LayoutBuilder(
                                    builder: (ctx, box) {
                                      final ph = box.maxHeight;
                                      return Align(
                                        alignment: Alignment(
                                            0, (_textNormY * 2 - 1).clamp(-1.0, 1.0)),
                                        child: GestureDetector(
                                          onVerticalDragUpdate: (d) => setState(() {
                                            _textNormY =
                                                (_textNormY + d.delta.dy / ph).clamp(0.0, 1.0);
                                          }),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            child: Text(
                                              _text!,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: _hexColor(_textColorHex),
                                                fontSize: _textSize * ph,
                                                fontWeight: FontWeight.bold,
                                                shadows: const [
                                                  Shadow(color: Colors.black, blurRadius: 6),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Filter strip.
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final f = _filters[i];
                        final selected = f.id == _filterId;
                        return GestureDetector(
                          onTap: _exporting ? null : () => setState(() => _filterId = f.id),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.ember : AppColors.graphiteRaised,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: selected ? AppColors.ember : AppColors.hairline),
                            ),
                            child: Text(
                              f.label,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected ? AppColors.onEmber : AppColors.steel,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _textTools(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Start ${_fmt(_startMs)}',
                                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
                            Text('${_fmt(selMs.toDouble())} selected',
                                style: GoogleFonts.inter(
                                    color: AppColors.cream, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('End ${_fmt(_endMs)}',
                                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                        RangeSlider(
                          min: 0,
                          max: _totalMs,
                          values: RangeValues(_startMs, _endMs),
                          activeColor: AppColors.ember,
                          inactiveColor: AppColors.hairline,
                          labels: RangeLabels(_fmt(_startMs), _fmt(_endMs)),
                          onChanged: _exporting
                              ? null
                              : (v) {
                                  setState(() {
                                    _startMs = v.start;
                                    _endMs = (v.end - v.start < _minClipMs)
                                        ? (v.start + _minClipMs).clamp(0, _totalMs)
                                        : v.end;
                                  });
                                  c.seekTo(Duration(milliseconds: _startMs.toInt()));
                                },
                        ),
                        const SizedBox(height: 8),
                        if (_exporting)
                          const Center(child: CircularProgressIndicator(color: AppColors.ember))
                        else
                          FilledButton.icon(
                            onPressed: _done,
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Done'),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A colour filter preset: [id] is sent to the native exporter (null = none);
/// [colorFilter] is the live-preview approximation over the player.
class _VideoFilter {
  const _VideoFilter({required this.id, required this.label, required this.colorFilter});
  final String? id;
  final String label;
  final ColorFilter? colorFilter;
}

final _filters = <_VideoFilter>[
  const _VideoFilter(id: null, label: 'None', colorFilter: null),
  const _VideoFilter(id: 'mono', label: 'Mono', colorFilter: ColorFilter.matrix(_kGreyscale)),
  const _VideoFilter(id: 'vivid', label: 'Vivid', colorFilter: ColorFilter.matrix(_kVivid)),
  const _VideoFilter(id: 'warm', label: 'Warm', colorFilter: ColorFilter.matrix(_kWarm)),
  const _VideoFilter(id: 'cool', label: 'Cool', colorFilter: ColorFilter.matrix(_kCool)),
];

const _kGreyscale = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
];
const _kVivid = <double>[
  1.3937, -0.3576, -0.0361, 0, 0, //
  -0.1063, 1.1424, -0.0361, 0, 0, //
  -0.1063, -0.3576, 1.4639, 0, 0, //
  0, 0, 0, 1, 0,
];
const _kWarm = <double>[
  1.15, 0, 0, 0, 0, //
  0, 1.0, 0, 0, 0, //
  0, 0, 0.85, 0, 0, //
  0, 0, 0, 1, 0,
];
const _kCool = <double>[
  0.85, 0, 0, 0, 0, //
  0, 1.0, 0, 0, 0, //
  0, 0, 1.2, 0, 0, //
  0, 0, 0, 1, 0,
];
