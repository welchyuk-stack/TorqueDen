import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/screens/about_screen.dart';
import 'package:torqueden/screens/account_screen.dart';
import 'package:torqueden/screens/contact_screen.dart';
import 'package:torqueden/screens/donate_screen.dart';
import 'package:torqueden/screens/invite_screen.dart';
import 'package:torqueden/screens/location_settings_screen.dart';
import 'package:torqueden/screens/membership_screen.dart';
import 'package:torqueden/screens/notifications_screen.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/services/units_pref.dart';
import 'package:torqueden/theme.dart';

/// Settings tab — account management and app settings.
/// Most rows are placeholders for now; "Log out" is wired up to Supabase.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text(
          'Log out?',
          style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You can log back in anytime.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Log out',
              style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
      // AuthGate swaps back to the login screen automatically.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _SectionHeader('Account'),
            _SettingTile(
              icon: Icons.person_outline,
              label: 'Account',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountScreen()),
              ),
            ),
            _SettingTile(
              icon: Icons.workspace_premium_outlined,
              label: 'Membership',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MembershipScreen()),
              ),
            ),
            const _SectionHeader('Preferences'),
            const _LocationTile(),
            const _DistanceUnitsToggle(),
            const _SectionHeader('App'),
            _SettingTile(
              icon: Icons.notifications_none,
              label: 'Notifications',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
            const _SettingTile(icon: Icons.policy_outlined, label: 'Data & policies'),
            _SettingTile(
              icon: Icons.info_outline,
              label: 'About TorqueDen',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
            const _SectionHeader('Support'),
            _SettingTile(
              icon: Icons.mail_outline,
              label: 'Contact us & Feedback',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactScreen()),
              ),
            ),
            _SettingTile(
              icon: Icons.group_add_outlined,
              label: 'Invite friends',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InviteScreen()),
              ),
            ),
            _SettingTile(
              icon: Icons.volunteer_activism_outlined,
              label: 'Donate',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DonateScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _SettingTile(
              icon: Icons.logout,
              label: 'Log out',
              color: AppColors.danger,
              onTap: () => _confirmLogout(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the Location screen and shows the currently saved place as its
/// subtitle, refreshing when you return.
class _LocationTile extends StatefulWidget {
  const _LocationTile();

  @override
  State<_LocationTile> createState() => _LocationTileState();
}

class _LocationTileState extends State<_LocationTile> {
  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LocationSettingsScreen()),
    );
    if (mounted) setState(() {}); // reflect any change to the saved location
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = SavedLocation.isSet ? (SavedLocation.label ?? 'Set') : 'Not set';
    return ListTile(
      leading: const Icon(Icons.location_on_outlined, color: AppColors.steel),
      title: Text('Location', style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.steel, size: 20),
      onTap: _open,
    );
  }
}

/// Distance-units switch. Off = kilometres (default), on = miles. Persists to
/// [UnitsPref] so Discover's radius search + distance labels follow it.
class _DistanceUnitsToggle extends StatefulWidget {
  const _DistanceUnitsToggle();

  @override
  State<_DistanceUnitsToggle> createState() => _DistanceUnitsToggleState();
}

class _DistanceUnitsToggleState extends State<_DistanceUnitsToggle> {
  bool _miles = UnitsPref.useMiles;

  Future<void> _set(bool value) async {
    setState(() => _miles = value);
    await UnitsPref.setUseMiles(value);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _miles,
      onChanged: _set,
      activeThumbColor: AppColors.ember,
      secondary: const Icon(Icons.straighten, color: AppColors.steel),
      title: Text('Distances in miles',
          style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
      subtitle: Text(
        _miles ? 'Showing distances in miles' : 'Showing distances in kilometres',
        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.steel),
      title: Text(label, style: GoogleFonts.inter(color: color ?? AppColors.cream, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.steel, size: 20),
      onTap: onTap ??
          () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label — coming soon.')),
              ),
    );
  }
}
