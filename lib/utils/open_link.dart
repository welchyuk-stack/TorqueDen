import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in an in-app browser view, falling back to a snackbar if it
/// can't be launched.
Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t open the page.')));
    }
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t open the page.')));
  }
}
