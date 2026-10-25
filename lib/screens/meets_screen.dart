import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car_meet.dart';
import 'package:torqueden/screens/create_meet_screen.dart';
import 'package:torqueden/screens/meet_detail_screen.dart';
import 'package:torqueden/services/guest_mode.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/utils/image_compress.dart';
import 'package:torqueden/widgets/guest_nudge_sheet.dart';

// ─── Week helpers ─────────────────────────────────────────────────────────────

DateTime _weekStart(int offset) {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final base = DateTime(monday.year, monday.month, monday.day, 1);
  final current = now.isBefore(base) ? base.subtract(const Duration(days: 7)) : base;
  return current.add(Duration(days: 7 * offset));
}

DateTime _weekEnd(int offset) => _weekStart(offset).add(const Duration(days: 7));

String _fmtShortDate(DateTime dt) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]}';
}

String _weekLabel(int offset) {
  if (offset == 0) return 'This week';
  if (offset == -1) return 'Last week';
  if (offset == 1) return 'Next week';
  return '${_fmtShortDate(_weekStart(offset))} – ${_fmtShortDate(_weekEnd(offset).subtract(const Duration(seconds: 1)))}';
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class MeetsScreen extends StatefulWidget {
  const MeetsScreen({super.key});
  @override
  State<MeetsScreen> createState() => _MeetsScreenState();
}

class _MeetsScreenState extends State<MeetsScreen> {
  final _client = Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  List<CarMeet> _all = [];
  bool _loading = true;
  Object? _error;
  int _tab = 0;
  int _weekOffset = 0;
  final _search = TextEditingController();

  List<CarMeet> get _weekMeets {
    final start = _weekStart(_weekOffset);
    final end = _weekEnd(_weekOffset);
    return _all.where((m) =>
        !m.meetAt.isBefore(start) && m.meetAt.isBefore(end)).toList()
      ..sort((a, b) => a.meetAt.compareTo(b.meetAt));
  }

  List<CarMeet> get _myMeets {
    final uid = _uid;
    if (uid == null) return [];
    return _all.where((m) => m.creatorId == uid || m.myRsvp != null).toList()
      ..sort((a, b) => a.meetAt.compareTo(b.meetAt));
  }

  List<CarMeet> get _displayList {
    final base = _tab == 0 ? _weekMeets : _myMeets;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((m) =>
        m.title.toLowerCase().contains(q) ||
        m.locationName.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    final from = _weekStart(-8).toIso8601String();
    final to = _weekEnd(12).toIso8601String();
    try {
      final rows = await _client
          .from('car_meets')
          .select('*, creator:creator_id(username, display_name, avatar_url), meet_rsvps(user_id, status)')
          .gte('meet_at', from)
          .lt('meet_at', to)
          .order('meet_at');
      final meets = rows.map((r) => CarMeet.fromMap(r as Map<String, dynamic>, myId: uid)).toList();
      if (mounted) setState(() { _all = meets; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _openCreate() async {
    if (GuestMode.isGuest) {
      await showGuestNudge(context, reason: 'create meets');
      return;
    }
    final created = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => const CreateMeetScreen()));
    if (created == true) _load();
  }

  Future<void> _openDetail(CarMeet meet) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MeetDetailScreen(meet: meet)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('Meets', style: GoogleFonts.archivo(fontWeight: FontWeight.w700, color: AppColors.cream)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            color: AppColors.ember,
            tooltip: 'Create meet',
            onPressed: _openCreate,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            Container(height: 1, color: AppColors.hairline),
            _SegmentedTabs(
              labels: const ['Upcoming', 'My meets'],
              selected: _tab,
              onChanged: (i) => setState(() { _tab = i; }),
            ),
          ]),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.ember))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Failed to load meets', style: TextStyle(color: AppColors.steel)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Try again')),
                    ],
                  ),
                )
              : _tab == 0
                  ? _UpcomingView(
                      weekOffset: _weekOffset,
                      meets: _displayList,
                      mappedMeets: _weekMeets.where((m) => m.hasCoords).toList(),
                      onPrevWeek: () => setState(() => _weekOffset--),
                      onNextWeek: () => setState(() => _weekOffset++),
                      onTap: _openDetail,
                      onRefresh: _load,
                      search: _search,
                    )
                  : _MyMeetsView(
                      meets: _displayList,
                      onTap: _openDetail,
                      onCreate: _openCreate,
                      onRefresh: _load,
                      search: _search,
                    ),
    );
  }
}

// ─── Upcoming tab ─────────────────────────────────────────────────────────────

class _UpcomingView extends StatelessWidget {
  const _UpcomingView({
    required this.weekOffset,
    required this.meets,
    required this.mappedMeets,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onTap,
    required this.onRefresh,
    required this.search,
  });
  final int weekOffset;
  final List<CarMeet> meets;
  final List<CarMeet> mappedMeets;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final ValueChanged<CarMeet> onTap;
  final Future<void> Function() onRefresh;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _WeekMap(meets: mappedMeets, onTap: onTap),
        _WeekNav(offset: weekOffset, onPrev: onPrevWeek, onNext: onNextWeek),
        _SearchBar(controller: search),
        Container(height: 1, color: AppColors.hairline),
        Expanded(
          child: meets.isEmpty
              ? EmptyState(
                  icon: Icons.directions_car_outlined,
                  title: search.text.isNotEmpty ? 'No results' : 'No meets this week',
                  message: search.text.isNotEmpty
                      ? 'Try a different name or location.'
                      : 'Use the arrows to browse other weeks.',
                )
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  color: AppColors.ember,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    itemCount: meets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _MeetCard(meet: meets[i], onTap: () => onTap(meets[i])),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── My meets tab ─────────────────────────────────────────────────────────────

class _MyMeetsView extends StatelessWidget {
  const _MyMeetsView({
    required this.meets,
    required this.onTap,
    required this.onCreate,
    required this.onRefresh,
    required this.search,
  });
  final List<CarMeet> meets;
  final ValueChanged<CarMeet> onTap;
  final VoidCallback onCreate;
  final Future<void> Function() onRefresh;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(controller: search),
        Container(height: 1, color: AppColors.hairline),
        Expanded(
          child: meets.isEmpty
              ? EmptyState(
                  icon: Icons.directions_car_outlined,
                  title: search.text.isNotEmpty ? 'No results' : 'No meets yet',
                  message: search.text.isNotEmpty
                      ? 'Try a different name or location.'
                      : 'Meets you create or RSVP to appear here.',
                  action: search.text.isEmpty ? FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create a meet'),
                  ) : null,
                )
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  color: AppColors.ember,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    itemCount: meets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _MeetCard(meet: meets[i], onTap: () => onTap(meets[i])),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Persistent search bar ────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: controller,
        style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
        cursorColor: AppColors.ember,
        decoration: InputDecoration(
          hintText: 'Search by name or location…',
          hintStyle: GoogleFonts.inter(color: AppColors.steel, fontSize: 15),
          prefixIcon: Icon(Icons.search, color: AppColors.steel, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, color: AppColors.steel, size: 18),
                  onPressed: controller.clear,
                )
              : null,
          filled: true,
          fillColor: AppColors.graphite,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ─── Week map ─────────────────────────────────────────────────────────────────

class _WeekMap extends StatefulWidget {
  const _WeekMap({required this.meets, required this.onTap});
  final List<CarMeet> meets;
  final ValueChanged<CarMeet> onTap;

  @override
  State<_WeekMap> createState() => _WeekMapState();
}

class _WeekMapState extends State<_WeekMap> {
  final _mapController = MapController();
  bool _locating = false;

  LatLng get _center {
    final meets = widget.meets;
    if (meets.isEmpty) {
      // Fall back to the user's saved settings location, then UK overview
      if (SavedLocation.isSet) return LatLng(SavedLocation.lat!, SavedLocation.lng!);
      return const LatLng(54.0, -2.0);
    }
    final lats = meets.map((m) => m.latitude!);
    final lngs = meets.map((m) => m.longitude!);
    return LatLng(
      (lats.reduce((a, b) => a < b ? a : b) + lats.reduce((a, b) => a > b ? a : b)) / 2,
      (lngs.reduce((a, b) => a < b ? a : b) + lngs.reduce((a, b) => a > b ? a : b)) / 2,
    );
  }

  double get _zoom {
    final meets = widget.meets;
    if (meets.isEmpty) return SavedLocation.isSet ? 11.0 : 5.0;
    final lats = meets.map((m) => m.latitude!);
    final lngs = meets.map((m) => m.longitude!);
    final span = (lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b)).abs()
               + (lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b)).abs();
    return span < 0.05 ? 13.0 : span < 0.5 ? 11.0 : span < 2.0 ? 9.0 : span < 8.0 ? 7.0 : 5.0;
  }

  Future<void> _locateMe() async {
    if (kIsWeb) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) return;
      final pos = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(pos.latitude, pos.longitude), 13);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.torqueden.app',
              ),
              MarkerLayer(
                markers: widget.meets.map((m) => Marker(
                  point: LatLng(m.latitude!, m.longitude!),
                  width: 160,
                  height: 52,
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () => widget.onTap(m),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.graphite,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.ember.withValues(alpha: 0.6)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
                          ),
                          child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.cream)),
                        ),
                        CustomPaint(size: const Size(12, 6), painter: _StemPainter()),
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.ember,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: AppColors.ember.withValues(alpha: 0.5), blurRadius: 6)],
                          ),
                        ),
                      ],
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),

          // Zoom + locate controls — bottom-right
          Positioned(
            right: 10,
            bottom: 10,
            child: Column(
              children: [
                _MapBtn(
                  icon: _locating ? null : Icons.my_location,
                  loading: _locating,
                  onTap: _locateMe,
                ),
                const SizedBox(height: 6),
                _MapBtn(icon: Icons.add, onTap: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                }),
                const SizedBox(height: 4),
                _MapBtn(icon: Icons.remove, onTap: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  const _MapBtn({this.icon, required this.onTap, this.loading = false});
  final IconData? icon;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.graphite.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.hairline),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ember),
              )
            : Icon(icon, color: AppColors.cream, size: 18),
      ),
    );
  }
}

class _StemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.ember.withValues(alpha: 0.6));
  }
  @override
  bool shouldRepaint(covariant _StemPainter old) => false;
}

// ─── Week navigator ───────────────────────────────────────────────────────────

class _WeekNav extends StatelessWidget {
  const _WeekNav({required this.offset, required this.onPrev, required this.onNext});
  final int offset;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final start = _weekStart(offset);
    final end = _weekEnd(offset).subtract(const Duration(seconds: 1));
    final dateRange = '${_fmtShortDate(start)} – ${_fmtShortDate(end)}';

    return Container(
      color: AppColors.graphite,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: AppColors.steel,
            onPressed: onPrev,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              children: [
                Text(_weekLabel(offset),
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.cream)),
                Text(dateRange,
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.steel)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: AppColors.steel,
            onPressed: onNext,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─── Segmented tabs ───────────────────────────────────────────────────────────

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.labels, required this.selected, required this.onChanged});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected == i ? AppColors.ember : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: selected == i ? FontWeight.w600 : FontWeight.w400,
                      color: selected == i ? AppColors.cream : AppColors.steel,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Meet card ────────────────────────────────────────────────────────────────

class _MeetCard extends StatelessWidget {
  const _MeetCard({required this.meet, required this.onTap});
  final CarMeet meet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPast = meet.isPast;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: AppDecorations.glassCard(radius: 16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (meet.coverUrl != null)
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Image.network(supabaseThumb(meet.coverUrl!, width: 600), fit: BoxFit.cover),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPast ? AppColors.graphiteRaised : AppColors.ember.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(_formatDate(meet.meetAt),
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                            color: isPast ? AppColors.steel : AppColors.ember)),
                  ),
                  const SizedBox(height: 8),
                  Text(meet.title,
                      style: GoogleFonts.archivo(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.cream)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 13, color: AppColors.steel),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(meet.locationName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _RsvpChip(icon: Icons.check_circle_outline, label: '${meet.goingCount} going', active: meet.myRsvp == 'going'),
                    const SizedBox(width: 8),
                    if (meet.maybeCount > 0)
                      _RsvpChip(icon: Icons.help_outline, label: '${meet.maybeCount} maybe', active: meet.myRsvp == 'maybe'),
                    const Spacer(),
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.graphiteRaised,
                      backgroundImage: meet.creatorAvatarUrl != null ? NetworkImage(meet.creatorAvatarUrl!) : null,
                      child: meet.creatorAvatarUrl == null
                          ? Text(meet.organizerName.characters.first.toUpperCase(),
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.cream))
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(meet.organizerName,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} · $hour:$min';
  }
}

class _RsvpChip extends StatelessWidget {
  const _RsvpChip({required this.icon, required this.label, required this.active});
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: active ? AppColors.ember : AppColors.steel),
        const SizedBox(width: 3),
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: active ? AppColors.ember : AppColors.steel)),
      ],
    );
  }
}
