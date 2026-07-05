import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/features.dart';
import 'package:torqueden/screens/video_trim_screen.dart';
import 'package:torqueden/services/video_trim_service.dart';
import 'package:torqueden/theme.dart';

/// A single captured photo or clip, returned by [CameraScreen].
class CapturedMedia {
  const CapturedMedia({
    required this.bytes,
    required this.name,
    required this.isVideo,
  });

  final Uint8List bytes;
  final String name;
  final bool isVideo;
}

/// In-app camera, Instagram-style: live preview with a capture button —
/// **tap** for a photo, **hold** to record a clip (auto-stops at
/// [maxClipSeconds]). Flip and torch controls up top. Pops a [CapturedMedia]
/// on success, or null if the user backs out.
///
/// Note: the iOS Simulator has no camera, so this only works on a real device.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.maxClipSeconds = 60});

  final int maxClipSeconds;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  bool _initializing = true;
  String? _error;
  bool _isRecording = false;
  bool _torch = false;

  late final AnimationController _ring;
  Timer? _maxTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ring = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.maxClipSeconds),
    );
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _maxTimer?.cancel();
    _ring.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    // Free the camera when backgrounded; re-acquire on resume.
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initController(_cameras[_cameraIndex]);
    }
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'No camera available on this device.';
          _initializing = false;
        });
        return;
      }
      await _initController(_cameras[_cameraIndex]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not access the camera: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _initController(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      // Only need the mic when recording video — off at launch avoids an
      // unnecessary microphone permission prompt.
      enableAudio: Features.video,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (_torch) await controller.setFlashMode(FlashMode.torch);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start the camera: $e';
        _initializing = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _initializing = false);
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _isRecording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _initializing = true);
    await _controller?.dispose();
    await _initController(_cameras[_cameraIndex]);
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _torch = !_torch;
    await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() {});
  }

  String _ext(XFile x, String fallback) {
    final i = x.path.lastIndexOf('.');
    return (i != -1 && i < x.path.length - 1)
        ? x.path.substring(i + 1).toLowerCase()
        : fallback;
  }

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isRecording) return;
    try {
      final x = await c.takePicture();
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(
        CapturedMedia(bytes: bytes, name: 'photo.${_ext(x, 'jpg')}', isVideo: false),
      );
    } catch (e) {
      _snack('Could not take photo: $e');
    }
  }

  Future<void> _startRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isRecording) return;
    try {
      // Chime first so the start tone doesn't bleed into the clip's audio.
      VideoTrimService.recordChime(start: true);
      await c.startVideoRecording();
      _ring.forward(from: 0);
      _maxTimer = Timer(Duration(seconds: widget.maxClipSeconds), _stopRecording);
      setState(() => _isRecording = true);
    } catch (e) {
      _snack('Could not start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    final c = _controller;
    if (c == null || !_isRecording) return;
    _maxTimer?.cancel();
    _ring.stop();
    try {
      final x = await c.stopVideoRecording();
      // Stop tone — after recording ends, so it's never captured in the clip.
      VideoTrimService.recordChime(start: false);
      if (!mounted) return;
      setState(() => _isRecording = false);
      // Offer a trim before attaching; returns the (trimmed) path, or the
      // original if the user keeps the full clip.
      final finalPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => VideoTrimScreen(inputPath: x.path)),
      );
      final path = finalPath ?? x.path;
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      final ext = path.contains('.') ? path.split('.').last : 'mp4';
      Navigator.of(context).pop(
        CapturedMedia(bytes: bytes, name: 'clip.$ext', isVideo: true),
      );
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
      _snack('Could not save the clip: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? _ErrorView(message: _error!, onClose: () => Navigator.of(context).pop())
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_initializing || _controller == null)
                  const Center(child: CircularProgressIndicator(color: AppColors.ember))
                else
                  _CoverPreview(controller: _controller!),
                // Top controls.
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RoundIcon(
                          icon: Icons.close,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        Row(
                          children: [
                            _RoundIcon(
                              icon: _torch ? Icons.flash_on : Icons.flash_off,
                              onTap: _initializing ? null : _toggleTorch,
                            ),
                            const SizedBox(width: 8),
                            if (_cameras.length > 1)
                              _RoundIcon(
                                icon: Icons.cameraswitch_outlined,
                                onTap: _isRecording || _initializing ? null : _flip,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Recording timer badge.
                if (_isRecording)
                  Positioned(
                    top: MediaQuery.viewPaddingOf(context).top + 56,
                    left: 0,
                    right: 0,
                    child: const Center(child: _RecordingBadge()),
                  ),
                // Capture button + hint.
                if (!_initializing && _controller != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 28,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Text(
                            !Features.video
                                ? 'Tap to take a photo'
                                : _isRecording
                                    ? 'Tap to stop'
                                    : 'Tap for photo  ·  hold to record',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.85),
                              shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
                            ),
                          ),
                        ),
                        GestureDetector(
                          // While recording, a tap stops it (as well as
                          // releasing the hold). Idle: tap = photo, hold = record.
                          // Video off (launch): photo only — no hold-to-record.
                          onTap: _isRecording ? _stopRecording : _takePhoto,
                          onLongPressStart:
                              Features.video ? (_) => _startRecording() : null,
                          onLongPressEnd:
                              Features.video ? (_) => _stopRecording() : null,
                          child: _CaptureButton(ring: _ring, recording: _isRecording),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Fills the screen with the preview, cropping to cover (like a camera app).
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return const ColoredBox(color: Colors.black);
    // previewSize is reported in landscape; swap for a portrait cover fill.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: preview.height,
        height: preview.width,
        child: CameraPreview(controller),
      ),
    );
  }
}

/// The capture control: a ring that fills while recording, around a dot that
/// morphs white (photo) → red (recording).
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.ring, required this.recording});

  final Animation<double> ring;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring — progress while recording, static otherwise.
          AnimatedBuilder(
            animation: ring,
            builder: (context, _) => SizedBox(
              width: 84,
              height: 84,
              child: CircularProgressIndicator(
                value: recording ? ring.value : 1,
                strokeWidth: 4,
                color: recording ? AppColors.ember : Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: recording ? 34 : 66,
            height: recording ? 34 : 66,
            decoration: BoxDecoration(
              color: recording ? AppColors.danger : Colors.white,
              borderRadius: BorderRadius.circular(recording ? 8 : 999),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'REC',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _RoundIcon(icon: Icons.close, onTap: onClose),
            ),
            const Spacer(),
            const Icon(Icons.videocam_off_outlined, color: AppColors.steel, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: the iOS Simulator has no camera — try a real device, or add media from your library instead.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
