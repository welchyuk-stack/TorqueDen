import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car_meet.dart';
import 'package:torqueden/screens/create_meet_screen.dart';
import 'package:torqueden/services/guest_mode.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/guest_nudge_sheet.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';
import 'package:torqueden/utils/image_compress.dart';
import 'package:url_launcher/url_launcher.dart';

class MeetDetailScreen extends StatefulWidget {
  const MeetDetailScreen({super.key, required this.meet});
  final CarMeet meet;

  @override
  State<MeetDetailScreen> createState() => _MeetDetailScreenState();
}

class _MeetDetailScreenState extends State<MeetDetailScreen> {
  final _client = Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  late CarMeet _meet;
  bool _rsvping = false;

  @override
  void initState() {
    super.initState();
    _meet = widget.meet;
    _reload();
  }

  Future<void> _reload() async {
    final uid = _uid;
    try {
      final row = await _client
          .from('car_meets')
          .select('*, creator:creator_id(username, display_name, avatar_url), meet_rsvps(user_id, status)')
          .eq('id', _meet.id)
          .single();
      if (mounted) setState(() => _meet = CarMeet.fromMap(row, myId: uid));
    } catch (_) {}
  }

  Future<void> _rsvp(String status) async {
    if (GuestMode.isGuest) {
      await showGuestNudge(context, reason: 'RSVP to meets');
      return;
    }
    final uid = _uid;
    if (uid == null || _rsvping) return;

    // Toggling same status = remove RSVP
    final remove = _meet.myRsvp == status;

    setState(() {
      _rsvping = true;
      // Optimistic update
      _meet = CarMeet(
        id: _meet.id, creatorId: _meet.creatorId, title: _meet.title,
        description: _meet.description, locationName: _meet.locationName,
        latitude: _meet.latitude, longitude: _meet.longitude,
        meetAt: _meet.meetAt, createdAt: _meet.createdAt, coverUrl: _meet.coverUrl,
        creatorUsername: _meet.creatorUsername, creatorDisplayName: _meet.creatorDisplayName,
        creatorAvatarUrl: _meet.creatorAvatarUrl,
        goingCount: _meet.goingCount + (status == 'going' ? (remove ? -1 : (_meet.myRsvp == 'going' ? 0 : 1)) : (_meet.myRsvp == 'going' ? -1 : 0)),
        maybeCount: _meet.maybeCount + (status == 'maybe' ? (remove ? -1 : (_meet.myRsvp == 'maybe' ? 0 : 1)) : (_meet.myRsvp == 'maybe' ? -1 : 0)),
        myRsvp: remove ? null : status,
      );
    });

    try {
      if (remove) {
        await _client.from('meet_rsvps').delete().eq('meet_id', _meet.id).eq('user_id', uid);
      } else {
        await _client.from('meet_rsvps').upsert({
          'meet_id': _meet.id,
          'user_id': uid,
          'status': status,
        }, onConflict: 'meet_id,user_id');
      }
    } catch (_) {
      // roll back on error
      await _reload();
    } finally {
      if (mounted) setState(() => _rsvping = false);
    }
  }

  Future<void> _openInMaps() async {
    final loc = Uri.encodeComponent(_meet.locationName);
    final uri = _meet.hasCoords
        ? Uri.parse(
            'https://maps.apple.com/?ll=${_meet.latitude},${_meet.longitude}&q=$loc')
        : Uri.parse('https://maps.apple.com/?q=$loc');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Delete meet?', style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: Text('This cannot be undone.', style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _client.from('car_meets').delete().eq('id', _meet.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = _uid == _meet.creatorId;
    final isPast = _meet.isPast;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            expandedHeight: _meet.coverUrl != null ? 220 : 0,
            leading: const BackButton(),
            actions: [
              if (isOwner) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: AppColors.steel,
                  tooltip: 'Edit meet',
                  onPressed: () async {
                    final updated = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => CreateMeetScreen(meet: _meet)),
                    );
                    if (updated == true) _reload();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.danger,
                  onPressed: _delete,
                ),
              ],
              if (!isOwner)
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  color: AppColors.steel,
                  tooltip: 'Report',
                  onPressed: () => showModerationSheet(
                    context,
                    targetType: 'meet',
                    targetId: _meet.id,
                    authorId: _meet.creatorId,
                    authorName: _meet.creatorDisplayName,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.map_outlined),
                color: AppColors.steel,
                tooltip: 'Open in Maps',
                onPressed: _openInMaps,
              ),
            ],
            flexibleSpace: _meet.coverUrl != null
                ? FlexibleSpaceBar(
                    background: Image.network(supabaseThumb(_meet.coverUrl!, width: 800), fit: BoxFit.cover),
                  )
                : null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: isPast ? AppColors.graphiteRaised : AppColors.ember.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatDateTime(_meet.meetAt),
                      style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: isPast ? AppColors.steel : AppColors.ember,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_meet.title, style: GoogleFonts.archivo(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.cream)),
                  const SizedBox(height: 8),

                  // Location row
                  GestureDetector(
                    onTap: _openInMaps,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.location_on_outlined, size: 16, color: AppColors.ember),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _meet.locationName,
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary, decoration: TextDecoration.underline, decorationColor: AppColors.textSecondary),
                              ),
                              if (_meet.address != null && _meet.address!.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _meet.address!.trim(),
                                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Organiser
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 15, color: AppColors.steel),
                      const SizedBox(width: 6),
                      Text('Organised by ${_meet.organizerName}',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // RSVP buttons
                  if (!isPast)
                    Row(
                      children: [
                        Expanded(
                          child: _RsvpButton(
                            label: 'Going',
                            icon: Icons.check_circle_outline,
                            active: _meet.myRsvp == 'going',
                            count: _meet.goingCount,
                            onTap: () => _rsvp('going'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RsvpButton(
                            label: 'Maybe',
                            icon: Icons.help_outline,
                            active: _meet.myRsvp == 'maybe',
                            count: _meet.maybeCount,
                            onTap: () => _rsvp('maybe'),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 16, color: AppColors.steel),
                        const SizedBox(width: 6),
                        Text('${_meet.goingCount} went · ${_meet.maybeCount} maybe',
                            style: GoogleFonts.inter(fontSize: 14, color: AppColors.steel)),
                      ],
                    ),

                  if (_meet.description != null && _meet.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Divider(color: AppColors.hairline),
                    const SizedBox(height: 16),
                    Text(_meet.description!.trim(),
                        style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary, height: 1.6)),
                  ],

                  // Map — always shown; pin only when coords available
                  ...[
                    const SizedBox(height: 24),
                    Divider(color: AppColors.hairline),
                    const SizedBox(height: 16),
                    Text('Location', style: GoogleFonts.archivo(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.cream)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 200,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: _meet.hasCoords
                                ? LatLng(_meet.latitude!, _meet.longitude!)
                                : const LatLng(54.0, -2.0),
                            initialZoom: _meet.hasCoords ? 14 : 5,
                            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.torqueden.app',
                            ),
                            if (_meet.hasCoords)
                              MarkerLayer(markers: [
                                Marker(
                                  point: LatLng(_meet.latitude!, _meet.longitude!),
                                  width: 36,
                                  height: 36,
                                  child: Icon(Icons.location_on, color: AppColors.ember, size: 36),
                                ),
                              ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: _openInMaps,
                        icon: Icon(Icons.open_in_new, size: 14, color: AppColors.ember),
                        label: Text('Open in Maps', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ember)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    final day = days[dt.weekday - 1];
    final month = months[dt.month - 1];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day ${dt.day} $month ${dt.year} · $hour:$min';
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({required this.label, required this.icon, required this.active, required this.count, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.ember : AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.ember : AppColors.hairline),
        ),
        child: Column(
          children: [
            Icon(active ? _filledIcon(icon) : icon, color: active ? AppColors.onEmber : AppColors.steel, size: 22),
            const SizedBox(height: 4),
            Text(
              count > 0 ? '$count $label' : label,
              style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? AppColors.onEmber : AppColors.steel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _filledIcon(IconData icon) {
    if (icon == Icons.check_circle_outline) return Icons.check_circle;
    if (icon == Icons.help_outline) return Icons.help;
    return icon;
  }
}
