import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/services/video_trim_service.dart';
import 'package:torqueden/theme.dart';
import 'package:video_player/video_player.dart';

/// Trim a video clip before it's attached. Pops the (trimmed) file path to use,
/// or the original path if the user keeps the full clip / an export fails.
/// Trimming runs natively via easy_video_editor (AVFoundation on iOS — no
/// ffmpeg). Phase 1 of video editing; text overlay + filters come later.
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
  bool _exporting = false;

  static const _minClipMs = 500.0; // don't allow a trim shorter than 0.5s

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
      // Restart from the trim start if we're outside the window.
      final posMs = c.value.position.inMilliseconds.toDouble();
      if (posMs < _startMs || posMs >= _endMs) {
        await c.seekTo(Duration(milliseconds: _startMs.toInt()));
      }
      await c.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _useFull() => _finish(widget.inputPath);

  Future<void> _useTrimmed() async {
    // No meaningful trim? Just keep the original.
    if (_startMs <= 0 && _endMs >= _totalMs) {
      await _finish(widget.inputPath);
      return;
    }
    setState(() => _exporting = true);
    try {
      final out = await VideoTrimService.trim(
        widget.inputPath,
        Duration(milliseconds: _startMs.toInt()),
        Duration(milliseconds: _endMs.toInt()),
      );
      await _finish(out ?? widget.inputPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not trim the clip — using the full video.')),
      );
      await _finish(widget.inputPath);
    }
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Trim'),
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
                              VideoPlayer(c),
                              if (!c.value.isPlaying)
                                const DecoratedBox(
                                  decoration: BoxDecoration(color: Colors.black26),
                                  child: Center(
                                    child: Icon(Icons.play_arrow, size: 56, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
                                  // Preview the start frame while scrubbing.
                                  c.seekTo(Duration(milliseconds: _startMs.toInt()));
                                },
                        ),
                        const SizedBox(height: 8),
                        if (_exporting)
                          const Center(child: CircularProgressIndicator(color: AppColors.ember))
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _useFull,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.steel,
                                    side: const BorderSide(color: AppColors.hairline),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  child: const Text('Full clip'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  onPressed: _useTrimmed,
                                  icon: const Icon(Icons.content_cut, size: 18),
                                  label: const Text('Use trim'),
                                  style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 13)),
                                ),
                              ),
                            ],
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
