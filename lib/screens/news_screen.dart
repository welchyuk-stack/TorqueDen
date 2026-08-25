import 'dart:async';
import 'package:flutter/material.dart';
import 'package:torqueden/models/news_cluster.dart';
import 'package:torqueden/services/news_service.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/open_link.dart';
import 'package:torqueden/utils/time_ago.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  static final refreshSignal = StreamController<void>.broadcast();

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

// ─── filter state ────────────────────────────────────────────────────────────

enum _Category { general, racing }

extension _CategoryX on _Category {
  String get label => switch (this) {
        _Category.general => 'General',
        _Category.racing => 'Racing',
      };

  String? get apiValue => switch (this) {
        _Category.general => null,
        _Category.racing => 'racing',
      };
}

const _racingSubcats = ['f1', 'nascar', 'indycar', 'gt3', 'drifting'];

const _subcatLabels = {
  'f1': 'F1',
  'nascar': 'NASCAR',
  'indycar': 'IndyCar',
  'gt3': 'GT / WEC',
  'drifting': 'Drifting',
};

// ─── state ───────────────────────────────────────────────────────────────────

class _NewsScreenState extends State<NewsScreen> {
  _Category _cat = _Category.general;
  String? _subcat;

  late Future<List<NewsCluster>> _future;
  StreamSubscription<void>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _refreshSub = NewsScreen.refreshSignal.stream.listen((_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<List<NewsCluster>> _load() => NewsService.instance.fetchClusters(
        category: _cat.apiValue,
        subcategory: _subcat,
        limit: 40,
      );

  void _setCategory(_Category cat) {
    setState(() {
      _cat = cat;
      _subcat = null;
      _future = _load();
    });
  }

  void _setSubcat(String? sub) {
    setState(() {
      _subcat = sub;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              category: _cat,
              subcategory: _subcat,
              onCategory: _setCategory,
              onSubcat: _setSubcat,
            ),
            Expanded(
              child: FutureBuilder<List<NewsCluster>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.ember),
                    );
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              color: AppColors.steel, size: 40),
                          const SizedBox(height: 12),
                          Text('Could not load news',
                              style: TextStyle(color: AppColors.textMuted)),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () =>
                                setState(() => _future = _load()),
                            child: const Text('Retry',
                                style: TextStyle(color: AppColors.ember)),
                          ),
                        ],
                      ),
                    );
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return Center(
                      child: Text('Nothing yet — check back soon.',
                          style: TextStyle(color: AppColors.textMuted)),
                    );
                  }
                  return RefreshIndicator(
                    color: AppColors.ember,
                    backgroundColor: AppColors.graphite,
                    onRefresh: () async {
                      setState(() => _future = _load());
                      await _future;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: items.length,
                      separatorBuilder: (context, x) =>
                          Divider(color: AppColors.hairline, height: 1),
                      itemBuilder: (context, i) =>
                          _NewsCard(cluster: items[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── header with category + subcat chips ─────────────────────────────────────

class _Header extends StatelessWidget {
  final _Category category;
  final String? subcategory;
  final ValueChanged<_Category> onCategory;
  final ValueChanged<String?> onSubcat;

  const _Header({
    required this.category,
    required this.subcategory,
    required this.onCategory,
    required this.onSubcat,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('News',
              style: TextStyle(
                  color: AppColors.cream,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _Category.values.map((cat) {
              final selected = category == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Chip(
                  label: cat.label,
                  selected: selected,
                  onTap: () => onCategory(cat),
                ),
              );
            }).toList(),
          ),
        ),
        if (category == _Category.racing) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: 'All Racing',
                    selected: subcategory == null,
                    onTap: () => onSubcat(null),
                    small: true,
                  ),
                ),
                ..._racingSubcats.map((sub) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: _subcatLabels[sub] ?? sub,
                        selected: subcategory == sub,
                        onTap: () => onSubcat(sub),
                        small: true,
                      ),
                    )),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Divider(color: AppColors.hairline, height: 1),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected ? AppColors.ember : AppColors.graphite,
        foregroundColor: selected ? AppColors.onEmber : AppColors.textSecondary,
        padding: EdgeInsets.symmetric(
            horizontal: small ? 12 : 16, vertical: small ? 4 : 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: TextStyle(
          fontSize: small ? 12 : 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      child: Text(label),
    );
  }
}

// ─── single news card ─────────────────────────────────────────────────────────

class _NewsCard extends StatelessWidget {
  final NewsCluster cluster;
  const _NewsCard({required this.cluster});

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = cluster.thumbnail != null;
    return InkWell(
      onTap: () => openLink(context, cluster.sources.first.url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // category badge
                  _CategoryBadge(
                      category: cluster.category,
                      subcategory: cluster.subcategory),
                  const SizedBox(height: 5),
                  // headline
                  Text(
                    cluster.title,
                    style: TextStyle(
                      color: AppColors.cream,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // meta row
                  Row(
                    children: [
                      Text(
                        cluster.sources.first.name,
                        style: TextStyle(
                            color: AppColors.ember,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                      if (cluster.sourceCount > 1) ...[
                        Text('  ·  ',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        Text(
                          '+${cluster.sourceCount - 1} more',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                      Text('  ·  ',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      Text(
                        timeAgo(cluster.lastSeenAt),
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (hasThumbnail) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  cluster.thumbnail!,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, e, s) => const SizedBox(width: 80),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;
  final String? subcategory;
  const _CategoryBadge({required this.category, this.subcategory});

  @override
  Widget build(BuildContext context) {
    final label = subcategory != null
        ? (_subcatLabels[subcategory] ?? subcategory)!.toUpperCase()
        : switch (category) {
            'racing' => 'RACING',
            'road_cars' => 'ROAD CARS',
            'modified' => 'MODIFIED',
            _ => category.toUpperCase(),
          };
    final color = switch (category) {
      'racing' => const Color(0xFF4FC3F7), // sky blue
      'road_cars' => const Color(0xFF81C784), // green
      'modified' => AppColors.ember,
      _ => AppColors.steel,
    };
    return Text(
      label,
      style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8),
    );
  }
}
