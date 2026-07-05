import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/theme.dart';

/// Full-screen cropper with a fixed-aspect frame the user pans/zooms the image
/// within. Pops the cropped [Uint8List], or null if cancelled.
class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({super.key, required this.bytes, this.aspectRatio = 16 / 9, this.title = 'Frame image'});

  final Uint8List bytes;
  final double aspectRatio;
  final String title;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final _controller = CropController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.carbon,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _busy ? null : () { setState(() => _busy = true); _controller.crop(); },
            child: Text('Use',
                style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.bytes,
              controller: _controller,
              aspectRatio: widget.aspectRatio,
              interactive: true,   // pan + pinch-zoom the image
              fixCropRect: true,   // frame stays put; you move the image
              baseColor: AppColors.carbon,
              maskColor: Colors.black.withValues(alpha: 0.6),
              radius: 8,
              onCropped: (result) {
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    if (mounted) Navigator.of(context).pop(croppedImage);
                  case CropFailure():
                    if (mounted) {
                      setState(() => _busy = false);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Could not crop that image. Try another.')));
                    }
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('Drag to position · pinch to zoom',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
