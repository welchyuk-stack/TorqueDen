import 'dart:convert';
import 'dart:io';
import 'package:torqueden/models/news_cluster.dart';

class NewsService {
  NewsService._();
  static final instance = NewsService._();

  static const _base = 'https://torqueden-news.welchyuk.workers.dev';

  Future<List<NewsCluster>> fetchClusters({
    String? category,
    String? subcategory,
    int limit = 40,
    int? before,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (category != null) params['category'] = category;
    if (subcategory != null) params['subcategory'] = subcategory;
    if (before != null) params['before'] = '$before';

    final uri = Uri.parse('$_base/news').replace(queryParameters: params);
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(const Utf8Decoder()).join();
      if (res.statusCode != 200) throw Exception('news API ${res.statusCode}');
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['clusters'] as List)
          .cast<Map<String, dynamic>>()
          .map(NewsCluster.fromJson)
          .toList();
    } finally {
      client.close();
    }
  }
}
