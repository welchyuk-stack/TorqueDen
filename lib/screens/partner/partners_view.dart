import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/partner_page.dart';
import 'package:torqueden/screens/partner/partner_page_screen.dart';
import 'package:torqueden/theme.dart';

/// Lighter grey panel behind the partner cards (softer than the app's carbon).
const Color _kPartnersBg = Color(0xFF2A2F38);

/// Browsable, view-only list of partner pages (Discover's Partners tab).
/// Managing your own page happens in Settings → Partner Page. [query] filters
/// by business name / bio.
class PartnersView extends StatefulWidget {
  const PartnersView({super.key, this.query = ''});

  final String query;

  @override
  State<PartnersView> createState() => _PartnersViewState();
}

class _PartnersViewState extends State<PartnersView> {
  final _client = Supabase.instance.client;
  late Future<List<PartnerPage>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PartnerPage>> _load() async {
    final rows = await _client.from('partner_pages').select().order('created_at', ascending: false);
    return rows.map(PartnerPage.fromMap).toList();
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  void _open(PartnerPage page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PartnerPageScreen(page: page)))
        .then((_) => _refresh());
  }

  List<PartnerPage> _filter(List<PartnerPage> pages) {
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return pages;
    return pages
        .where((p) => p.businessName.toLowerCase().contains(q) || (p.bio ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _kPartnersBg,
      child: FutureBuilder<List<PartnerPage>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.ember));
        }
        final visible = _filter(snapshot.data ?? const <PartnerPage>[]);
        return RefreshIndicator(
          color: AppColors.ember,
          backgroundColor: AppColors.graphite,
          onRefresh: _refresh,
          child: visible.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 80),
                    Center(
                      child: Text(
                        widget.query.trim().isEmpty ? 'No partners yet.' : 'No partners match "${widget.query.trim()}".',
                        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 15),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      widthFactor: 0.9, // ~10% smaller card
                      child: _PartnerCard(page: visible[i], onTap: () => _open(visible[i])),
                    ),
                  ),
                ),
        );
      },
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
