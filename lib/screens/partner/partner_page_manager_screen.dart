import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/partner_page.dart';
import 'package:torqueden/screens/membership_screen.dart';
import 'package:torqueden/screens/partner/edit_partner_page_screen.dart';
import 'package:torqueden/screens/partner/partner_page_screen.dart';
import 'package:torqueden/services/entitlements.dart';
import 'package:torqueden/theme.dart';

/// Settings → Partner Page: where a Partner-tier user creates, edits, views or
/// deletes their own page. Non-partners get a nudge to Membership.
class PartnerPageManagerScreen extends StatefulWidget {
  const PartnerPageManagerScreen({super.key});

  @override
  State<PartnerPageManagerScreen> createState() => _PartnerPageManagerScreenState();
}

class _PartnerPageManagerScreenState extends State<PartnerPageManagerScreen> {
  final _client = Supabase.instance.client;
  late Future<PartnerPage?> _future;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PartnerPage?> _load() async {
    await Entitlements.refresh();
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client.from('partner_pages').select().eq('owner_id', uid).maybeSingle();
    return row == null ? null : PartnerPage.fromMap(row);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(PartnerPage? page) async {
    final saved = await Navigator.of(context).push<PartnerPage>(
      MaterialPageRoute(builder: (_) => EditPartnerPageScreen(page: page)),
    );
    if (saved != null) _reload();
  }

  Future<void> _delete(PartnerPage page) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Delete your Partner Page?',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: Text('This removes your business page. You can create a new one later.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.from('partner_pages').delete().eq('id', page.id);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partner Page')),
      body: SafeArea(
        child: FutureBuilder<PartnerPage?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.ember));
            }
            if (!Entitlements.canManagePartnerPage) return _notPartner();
            final page = snapshot.data;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: page == null ? _noPage() : _hasPage(page),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _noPage() => [
        Text('Set up your Partner Page',
            style: GoogleFonts.archivo(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.cream)),
        const SizedBox(height: 8),
        Text('Add a banner, a bio and a link to your site. It shows in Discover → Partners for everyone to find.',
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.45)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _edit(null),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Create your page'),
        ),
      ];

  List<Widget> _hasPage(PartnerPage page) => [
        Container(
          decoration: BoxDecoration(
            color: AppColors.graphite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: kBannerAspect,
                child: page.hasBanner
                    ? Image.network(page.bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback())
                    : _fallback(),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(page.businessName,
                    style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _edit(page),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.edit_outlined, size: 20),
          label: const Text('Edit page'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => PartnerPageScreen(page: page))),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ember,
            side: const BorderSide(color: AppColors.hairline),
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.visibility_outlined, size: 20),
          label: const Text('View page'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => _delete(page),
          icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
          label: Text('Delete page', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
      ];

  Widget _notPartner() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.ember.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.storefront_outlined, size: 34, color: AppColors.ember),
            ),
            const SizedBox(height: 18),
            Text('Partner Pages are for Partner members',
                textAlign: TextAlign.center,
                style: GoogleFonts.archivo(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.cream)),
            const SizedBox(height: 10),
            Text('Upgrade to the Partner tier to get a public page for your business, brand or shop.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.45)),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MembershipScreen())),
              child: const Text('See Membership'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => const DecoratedBox(
        decoration: BoxDecoration(color: AppColors.graphiteRaised),
        child: Center(child: Icon(Icons.storefront_outlined, size: 30, color: AppColors.steel)),
      );
}
