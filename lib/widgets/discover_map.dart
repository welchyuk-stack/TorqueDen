import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:torqueden/models/car.dart';
import 'package:torqueden/theme.dart';

/// A dark map of located cars. Each car is a tappable pin showing its photo;
/// tapping one raises a preview card at the bottom that opens the car's page.
///
/// Only pass cars that actually have coordinates. [center] is the search
/// origin ("you are here"); [labelBuilder] supplies each car's distance text.
class DiscoverMap extends StatefulWidget {
  const DiscoverMap({
    super.key,
    required this.cars,
    required this.onOpenCar,
    this.center,
    this.labelBuilder,
  });

  final List<Car> cars;
  final LatLng? center;
  final void Function(Car) onOpenCar;
  final String? Function(Car)? labelBuilder;

  @override
  State<DiscoverMap> createState() => _DiscoverMapState();
}

class _DiscoverMapState extends State<DiscoverMap> {
  final _controller = MapController();
  Car? _selected;

  List<LatLng> get _carPoints =>
      widget.cars.map((c) => LatLng(c.latitude!, c.longitude!)).toList();

  /// Frames all pins (and the search center) once the map is laid out.
  void _fitToContent() {
    final points = [..._carPoints, if (widget.center != null) widget.center!];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _controller.move(points.first, 11);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(56),
        maxZoom: 13,
      ),
    );
  }

  void _select(Car car) {
    setState(() => _selected = car);
    _controller.move(LatLng(car.latitude!, car.longitude!), _controller.camera.zoom);
  }

  static const double _minZoom = 3;
  static const double _maxZoom = 18;

  /// Steps the zoom by [delta] about the current centre (clamped).
  void _zoomBy(double delta) {
    final cam = _controller.camera;
    final z = (cam.zoom + delta).clamp(_minZoom, _maxZoom);
    _controller.move(cam.center, z);
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = widget.center ??
        (_carPoints.isNotEmpty ? _carPoints.first : const LatLng(54.5, -3.0));

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 6,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            onMapReady: _fitToContent,
            onTap: (_, _) => setState(() => _selected = null),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.flingAnimation,
            ),
          ),
          children: [
            TileLayer(
              // CARTO "Voyager" — standard map colours in a soft pastel palette
              // (readable, unlike the very dark basemap).
              urlTemplate:
                  'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              userAgentPackageName: 'com.aquamain.torqueden',
              retinaMode: RetinaMode.isHighDensity(context),
            ),
            if (widget.center != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.center!,
                    width: 22,
                    height: 22,
                    child: const _CenterDot(),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final car in widget.cars)
                  Marker(
                    point: LatLng(car.latitude!, car.longitude!),
                    width: 56,
                    height: 64,
                    alignment: Alignment.topCenter,
                    child: _CarPin(
                      car: car,
                      selected: identical(car, _selected),
                      onTap: () => _select(car),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
                TextSourceAttribution('CARTO'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _MapControls(
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
            onFit: _fitToContent,
          ),
        ),
        if (_selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _CarPreviewCard(
              car: _selected!,
              distanceLabel: widget.labelBuilder?.call(_selected!),
              onTap: () => widget.onOpenCar(_selected!),
              onClose: () => setState(() => _selected = null),
            ),
          ),
      ],
    );
  }
}

/// Stacked zoom-in / zoom-out / fit-all buttons overlaid on the map.
class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MapButton(icon: Icons.add, tooltip: 'Zoom in', onTap: onZoomIn),
        const SizedBox(height: 8),
        _MapButton(icon: Icons.remove, tooltip: 'Zoom out', onTap: onZoomOut),
        const SizedBox(height: 8),
        _MapButton(icon: Icons.fit_screen_outlined, tooltip: 'Fit all cars', onTap: onFit),
      ],
    );
  }
}

/// A single round map-control button.
class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.graphite,
      shape: const CircleBorder(),
      elevation: 4,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: AppColors.cream, size: 22),
          ),
        ),
      ),
    );
  }
}

/// "You are here" dot at the search center.
class _CenterDot extends StatelessWidget {
  const _CenterDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ember,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.cream, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6),
        ],
      ),
    );
  }
}

/// A round photo pin for one car, with a downward pointer. Highlights (ember
/// ring) when it's the selected pin.
class _CarPin extends StatelessWidget {
  const _CarPin({required this.car, required this.selected, required this.onTap});

  final Car car;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = selected ? AppColors.ember : AppColors.cream;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 2.5),
              color: AppColors.graphiteRaised,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 5),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: car.hasPhoto
                ? Image.network(
                    car.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _PinFallback(),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const _PinFallback(),
                  )
                : const _PinFallback(),
          ),
          // Little pointer triangle under the circle.
          Transform.translate(
            offset: const Offset(0, -2),
            child: CustomPaint(
              size: const Size(12, 7),
              painter: _PointerPainter(ring),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinFallback extends StatelessWidget {
  const _PinFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car, color: AppColors.steel, size: 20),
    );
  }
}

class _PointerPainter extends CustomPainter {
  _PointerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => oldDelegate.color != color;
}

/// Bottom preview card for the selected pin: photo, name, distance, tap to open.
class _CarPreviewCard extends StatelessWidget {
  const _CarPreviewCard({
    required this.car,
    required this.onTap,
    required this.onClose,
    this.distanceLabel,
  });

  final Car car;
  final String? distanceLabel;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.graphite,
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: car.hasPhoto
                      ? Image.network(
                          car.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _PinFallback(),
                          loadingBuilder: (context, child, progress) =>
                              progress == null ? child : const _PinFallback(),
                        )
                      : const _PinFallback(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      car.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivo(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      car.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    if (distanceLabel != null || car.locationName != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 13, color: AppColors.ember),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              [
                                ?car.locationName,
                                ?distanceLabel,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.steel,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20, color: AppColors.steel),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
