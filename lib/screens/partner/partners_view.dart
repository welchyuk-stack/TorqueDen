import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/partner_page.dart';
import 'package:torqueden/screens/membership_screen.dart';
import 'package:torqueden/screens/partner/edit_partner_page_screen.dart';
import 'package:torqueden/screens/partner/partner_page_screen.dart';
import 'package:torqueden/services/entitlements.dart';
import 'package:torqueden/theme.dart';

/// Browsable list of partner pages (used in Discover's Partners tab). Everyone
/// can view; only Partner-tier users get the create/edit-your-page action.
/// [query] filters by business name.
class PartnersView extends StatefulWidget {
  const PartnersView({super.key, this.query = ''});

  final String query;

  @override
  State<PartnersView> createState() => _PartnersViewState();
}

class _PartnersViewState extends State<PartnersView> {
  final _client = Supabase.instance.client;
  late Future<List<PartnerPage>> _future;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PartnerPage>> _load() async {
    await Entitlements.refresh();
    final rows = await _client.from('partner_pages').select().order('created_at', ascending: false);
    return rows.map(PartnerPage.fromMap).toList();
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  Future<void> _manageMyPage(PartnerPage? mine) async {
    final saved = await Navigator.of(context).push<PartnerPage>(
      MaterialPageRoute(builder: (_) => EditPartnerPageScreen(page: mine)),
    );
    if (saved != null) await _refresh();
  }

  void _open(PartnerPage page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PartnerPageScreen(page: page)))
        .then((_) => _refresh());
  }

  List<PartnerPage> _filter(List<PartnerPage> pages) {
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return pages;
    return pages.where((p) => p.businessName.toLowerCase().contains(q) || (p.bio ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PartnerPage>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.ember));
        }
        final all = snapshot.data ?? const <PartnerPage>[];
        PartnerPage? mine;
        for (final p in all) {
          if (p.ownerId == _uid) { mine = p; break; }
        }
        final visible = _filter(all);
        return RefreshIndicator(
          color: AppColors.ember,
          backgroundColor: AppColors.graphite,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _headerCard(mine),
              const SizedBox(height: 16),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      widget.query.trim().isEmpty ? 'No partners yet.' : 'No partners match "${widget.query.trim()}".',
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 15),
                    ),
                  ),
                )
              else
                for (final p in visible) ...[
                  _PartnerCard(page: p, onTap: () => _open(p)),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _headerCard(PartnerPage? mine) {
    final isPartner = Entitlements.canManagePartnerPage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isPartner ? 'Your Partner Page' : 'Become a Partner',
              style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
          const SizedBox(height: 6),
          Text(
            isPartner
                ? (mine == null
                    ? 'Set up your business page — banner, bio and a link to your site.'
                    : 'Edit your business page.')
                : 'Partner members get a public page for their business, brand or shop.',
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: isPartner
                ? FilledButton(
                    onPressed: () => _manageMyPage(mine),
                    child: Text(mine == null ? 'Create your page' : 'Edit your page'),
                  )
                : OutlinedButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const MembershipScreen())),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ember,
                      side: const BorderSide(color: AppColors.hairline),
                    ),
                    child: const Text('See Membership'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.page, required this.onTap});
  final PartnerPage page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
              aspectRatio: 16 / 6,
              child: page.hasBanner
                  ? Image.network(page.bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback())
                  : _fallback(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(page.businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivo(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.cream)),
                  if ((page.bio ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(page.bio!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
                  ],
                ],
              ),
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
