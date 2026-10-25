import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/screens/about_screen.dart';
import 'package:torqueden/screens/account_screen.dart';
import 'package:torqueden/screens/contact_screen.dart';
import 'package:torqueden/screens/data_policies_screen.dart';
import 'package:torqueden/screens/donate_screen.dart';
import 'package:torqueden/screens/invite_screen.dart';
import 'package:torqueden/screens/location_settings_screen.dart';
import 'package:torqueden/screens/following_screen.dart';
import 'package:torqueden/screens/notifications_screen.dart';
import 'package:torqueden/main_shell.dart';
import 'package:torqueden/screens/auth/auth_screen.dart';
import 'package:torqueden/services/biometric_lock.dart';
import 'package:torqueden/services/feed_prefs.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/services/theme_pref.dart';
import 'package:torqueden/services/units_pref.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/settings_group.dart';

/// Settings tab — account management and app settings.
/// Most rows are placeholders for now; "Log out" is wired up to Supabase.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Whether the device supports biometrics — decided here so the Preferences
  /// group composes its rows (and dividers) correctly, rather than a row
  /// hiding itself and leaving a stray divider behind.
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    BiometricLock.isAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text(
          'Log out?',
          style: GoogleFonts.spaceGrotesk(color: AppColors.cream, fontWeight: FontWeight.w700),
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
      MainShell.jumpToFeed.add(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _SectionHeader('Account'),
            SettingsGroup(
              children: [
                if (isLoggedIn)
                  _SettingTile(
                    icon: Icons.person_outline,
                    label: 'Account',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    ),
                  )
                else
                  _SettingTile(
                    icon: Icons.login,
                    label: 'Sign in / Create account',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    ),
                  ),
              ],
            ),
            const _SectionHeader('Preferences'),
            SettingsGroup(
              children: [
                const _LocationTile(),
                const _DistanceUnitsToggle(),
                if (_bioAvailable) const _BiometricToggle(),
              ],
            ),
            const _SectionHeader('Appearance'),
            const SettingsGroup(children: [_ThemeModeTile()]),
            const _SectionHeader('Feed'),
            const SettingsGroup(children: [_FeedFiltersTile()]),
            const _SectionHeader('App'),
            SettingsGroup(
              children: [
                _SettingTile(
                  icon: Icons.favorite_border,
                  label: 'Following',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FollowingScreen()),
                  ),
                ),
                _SettingTile(
                  icon: Icons.notifications_none,
                  label: 'Notifications',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()),
                  ),
                ),
                _SettingTile(
                  icon: Icons.policy_outlined,
                  label: 'Data & policies',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const DataPoliciesScreen()),
                  ),
                ),
                _SettingTile(
                  icon: Icons.info_outline,
                  label: 'About TorqueDen',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
              ],
            ),
            const _SectionHeader('Support'),
            SettingsGroup(
              children: [
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
              ],
            ),
            const SizedBox(height: 16),
            if (isLoggedIn)
              SettingsGroup(
                children: [
                  _SettingTile(
                    icon: Icons.logout,
                    label: 'Log out',
                    color: AppColors.danger,
                    onTap: () => _confirmLogout(context),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Biometric app-lock switch (Face ID / Touch ID). Hidden on devices without
/// biometric support. Enabling prompts to confirm first.
class _BiometricToggle extends StatefulWidget {
  const _BiometricToggle();

  @override
  State<_BiometricToggle> createState() => _BiometricToggleState();
}

class _BiometricToggleState extends State<_BiometricToggle> {
  bool _on = BiometricLock.enabled;

  Future<void> _set(bool value) async {
    final ok = await BiometricLock.setEnabled(value);
    if (!mounted) return;
    setState(() => _on = BiometricLock.enabled);
    if (value && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t turn on biometric unlock.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Availability is checked by SettingsScreen, which only includes this row
    // on devices that support biometrics.
    return SwitchListTile(
      value: _on,
      onChanged: _set,
      activeThumbColor: AppColors.ember,
      secondary: Icon(Icons.face_outlined, color: AppColors.steel),
      title: Text('Biometric unlock', style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
      subtitle: Text('Use biometrics to open the app',
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
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
      leading: Icon(Icons.location_on_outlined, color: AppColors.steel),
      title: Text('Location', style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      trailing: Icon(Icons.chevron_right, color: AppColors.steel, size: 20),
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
      secondary: Icon(Icons.straighten, color: AppColors.steel),
      title: Text('Distances in miles',
          style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
      subtitle: Text(
        _miles ? 'Showing distances in miles' : 'Showing distances in kilometres',
        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }
}

/// Two toggle switches for feed filtering — media-only posts and hide Shot entries.
class _FeedFiltersTile extends StatelessWidget {
  const _FeedFiltersTile();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: FeedPrefs.mediaOnly,
          builder: (context, value, _) => SwitchListTile(
            value: value,
            onChanged: FeedPrefs.setMediaOnly,
            title: Text(
              'Media only',
              style: GoogleFonts.inter(fontSize: 15, color: AppColors.cream),
            ),
            subtitle: Text(
              'Show posts with photos or videos only',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            ),
            activeThumbColor: AppColors.ember,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
        ),
        Divider(height: 1, color: AppColors.hairline, indent: 16, endIndent: 16),
        ValueListenableBuilder<bool>(
          valueListenable: FeedPrefs.hideShot,
          builder: (context, value, _) => SwitchListTile(
            value: value,
            onChanged: FeedPrefs.setHideShot,
            title: Text(
              'Hide The Shot entries',
              style: GoogleFonts.inter(fontSize: 15, color: AppColors.cream),
            ),
            subtitle: Text(
              'Keep weekly challenge posts out of your feed',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            ),
            activeThumbColor: AppColors.ember,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
        ),
      ],
    );
  }
}

/// Appearance switch — Dark, Light, or follow the system setting. Opens a
/// bottom sheet with the three options; the current choice shows as the
/// subtitle. Persisted via [ThemePref].
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  static String _label(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'Dark',
        ThemeMode.light => 'Light',
        ThemeMode.system => 'Follow system',
      };

  Future<void> _open(BuildContext context) async {
    final chosen = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'Appearance',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppColors.cream,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final mode in ThemeMode.values)
                  ListTile(
                    title: Text(_label(mode),
                        style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
                    trailing: mode == ThemePref.mode
                        ? const Icon(Icons.check, color: AppColors.ember)
                        : null,
                    onTap: () => Navigator.pop(ctx, mode),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen != null && chosen != ThemePref.mode) {
      await ThemePref.setMode(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemePref.notifier,
      builder: (context, mode, _) {
        return ListTile(
          leading: Icon(Icons.dark_mode_outlined, color: AppColors.steel),
          title: Text('Theme', style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
          subtitle: Text(_label(mode),
              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
          trailing: Icon(Icons.chevron_right, color: AppColors.steel, size: 20),
          onTap: () => _open(context),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
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
      trailing: Icon(Icons.chevron_right, color: AppColors.steel, size: 20),
      onTap: onTap ??
          () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label — coming soon.')),
              ),
    );
  }
}
