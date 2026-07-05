import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/partner_page.dart';
import 'package:torqueden/screens/partner/edit_partner_page_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/open_link.dart';

/// Public view of a partner's page: banner, business name, bio, website link.
/// The owner sees an Edit action.
class PartnerPageScreen extends StatefulWidget {
  const PartnerPageScreen({super.key, required this.page});

  final PartnerPage page;

  @override
  State<PartnerPageScreen> createState() => _PartnerPageScreenState();
}

class _PartnerPageScreenState extends State<PartnerPageScreen> {
  late PartnerPage _page;

  bool get _isOwner => Supabase.instance.client.auth.currentUser?.id == _page.ownerId;

  @override
  void initState() {
    super.initState();
    _page = widget.page;
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<PartnerPage>(
      MaterialPageRoute(builder: (_) => EditPartnerPageScreen(page: _page)),
    );
    if (updated != null && mounted) setState(() => _page = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_page.businessName),
        actions: [
          if (_isOwner)
            IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined), tooltip: 'Edit'),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _page.hasBanner
                  ? Image.network(_page.bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _BannerFallback())
                  : const _BannerFallback(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _PartnerBadge(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_page.businessName,
                            style: GoogleFonts.archivo(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.cream)),
                      ),
                    ],
                  ),
                  if ((_page.bio ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(_page.bio!.trim(),
                        style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary, height: 1.5)),
                  ],
                  if (_page.hasWebsite) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => openLink(context, _page.websiteUrl!),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Visit website'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerBadge extends StatelessWidget {
  const _PartnerBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.ember, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 13, color: AppColors.onEmber),
          const SizedBox(width: 4),
          Text('Partner',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.onEmber)),
        ],
      ),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2016), AppColors.carbon],
        ),
      ),
      child: Center(child: Icon(Icons.storefront_outlined, size: 40, color: AppColors.steel)),
    );
  }
}
