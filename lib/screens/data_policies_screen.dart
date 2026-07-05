import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/screens/about_screen.dart' show kAppVersion;
import 'package:torqueden/support_links.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/open_link.dart';

/// Data & policies hub: opens the hosted Privacy Policy, Terms, and Community
/// Guidelines, plus the in-app open-source license list.
class DataPoliciesScreen extends StatelessWidget {
  const DataPoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data & policies')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _Tile(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              external: true,
              onTap: () => openLink(context, SupportLinks.privacyPolicyUrl),
            ),
            _Tile(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              external: true,
              onTap: () => openLink(context, SupportLinks.termsUrl),
            ),
            _Tile(
              icon: Icons.groups_outlined,
              label: 'Community Guidelines',
              external: true,
              onTap: () => openLink(context, SupportLinks.communityGuidelinesUrl),
            ),
            _Tile(
              icon: Icons.article_outlined,
              label: 'Open-source licenses',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'TorqueDen',
                applicationVersion: kAppVersion,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap, this.external = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.steel),
      title: Text(label, style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
      trailing: Icon(external ? Icons.open_in_new : Icons.chevron_right, color: AppColors.steel, size: 20),
      onTap: onTap,
    );
  }
}
