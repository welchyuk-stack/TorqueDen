class NewsSource {
  final String name;
  final String url;
  const NewsSource({required this.name, required this.url});
}

class NewsCluster {
  final String id;
  final String title;
  final String? summary;
  final String? thumbnail;
  final String category;
  final String? subcategory;
  final int sourceCount;
  final DateTime lastSeenAt;
  final List<NewsSource> sources;

  const NewsCluster({
    required this.id,
    required this.title,
    this.summary,
    this.thumbnail,
    required this.category,
    this.subcategory,
    required this.sourceCount,
    required this.lastSeenAt,
    required this.sources,
  });

  factory NewsCluster.fromJson(Map<String, dynamic> j) => NewsCluster(
        id: j['id'] as String,
        title: _decodeEntities(j['title'] as String),
        summary: j['summary'] != null ? _decodeEntities(j['summary'] as String) : null,
        thumbnail: j['thumbnail'] as String?,
        category: j['category'] as String,
        subcategory: j['subcategory'] as String?,
        sourceCount: j['source_count'] as int,
        lastSeenAt: DateTime.fromMillisecondsSinceEpoch(
          (j['last_seen_at'] as int) * 1000,
        ),
        sources: (j['sources'] as List)
            .cast<Map<String, dynamic>>()
            .map((s) => NewsSource(name: s['name'] as String, url: s['url'] as String))
            .toList(),
      );
}

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#8216;', '‘')
    .replaceAll('&#8217;', '’')
    .replaceAll('&#8220;', '“')
    .replaceAll('&#8221;', '”')
    .replaceAll('&#8211;', '–')
    .replaceAll('&#8212;', '—');
