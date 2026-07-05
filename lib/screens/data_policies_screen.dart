import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/policies/policy_documents.dart';
import 'package:torqueden/screens/about_screen.dart' show kAppVersion;
import 'package:torqueden/theme.dart';

/// Data & policies hub: Privacy Policy, Terms, Community Guidelines, and the
/// open-source license list.
class DataPoliciesScreen extends StatelessWidget {
  const DataPoliciesScreen({super.key});

  void _openDoc(BuildContext context, PolicyDoc doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PolicyScreen(doc: doc)),
    );
  }

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
              onTap: () => _openDoc(context, kPrivacyPolicy),
            ),
            _Tile(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              onTap: () => _openDoc(context, kTermsOfService),
            ),
            _Tile(
              icon: Icons.groups_outlined,
              label: 'Community Guidelines',
              onTap: () => _openDoc(context, kCommunityGuidelines),
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
  const _Tile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.steel),
      title: Text(label, style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.steel, size: 20),
      onTap: onTap,
    );
  }
}

/// Renders a [PolicyDoc] as a readable scrollable page.
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.doc});
  final PolicyDoc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(doc.title,
                style: GoogleFonts.archivo(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.cream)),
            const SizedBox(height: 4),
            Text('Effective ${doc.effective}',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            for (final s in doc.sections) ...[
              Text(s.heading,
                  style: GoogleFonts.archivo(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.cream)),
              const SizedBox(height: 6),
              Text(s.body,
                  style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary, height: 1.5)),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}
