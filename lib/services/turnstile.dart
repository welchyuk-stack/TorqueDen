import 'dart:async';

import 'package:flutter/material.dart';
import 'package:torqueden/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cloudflare Turnstile — bot check on the auth endpoints.
///
/// Supabase verifies the token server-side (Authentication → Attack Protection),
/// so a scripted client can't skip this by not calling us: once CAPTCHA is
/// enabled on the project, GoTrue rejects any signup/login/reset that arrives
/// without a valid token. This widget only obtains the token.
///
/// **Off until [siteKey] is set.** With an empty key [enabled] is false, the
/// auth screen never shows the sheet, and every call passes `captchaToken: null`
/// — exactly today's behaviour. Turn it on in two places at once (here and in
/// the Supabase dashboard) or one side will reject the other: a token sent to a
/// project with CAPTCHA off is ignored, but CAPTCHA on with no token is a hard
/// auth failure for every user.
class TurnstileConfig {
  TurnstileConfig._();

  /// Public site key from Cloudflare → Turnstile. Safe to ship — the matching
  /// secret key belongs only in Supabase and must never appear in this repo.
  static const String siteKey = '';

  /// Origin the widget is served from inside the webview. Turnstile site keys
  /// are domain-locked, so this must be a hostname listed on the widget in the
  /// Cloudflare dashboard — there's no "any domain" option for mobile.
  static const String origin = 'https://torquedenapp.com';

  static bool get enabled => siteKey.isNotEmpty;
}

/// Renders the Turnstile challenge and completes with its token.
///
/// Returns null if the user dismisses the sheet or the widget errors — callers
/// treat that as "don't proceed" rather than "proceed without a token", since
/// the latter just fails at GoTrue anyway.
Future<String?> obtainTurnstileToken(BuildContext context) {
  if (!TurnstileConfig.enabled) return Future.value(null);
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: true,
    backgroundColor: AppColors.graphite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _TurnstileSheet(),
  );
}

class _TurnstileSheet extends StatefulWidget {
  const _TurnstileSheet();

  @override
  State<_TurnstileSheet> createState() => _TurnstileSheetState();
}

class _TurnstileSheetState extends State<_TurnstileSheet> {
  late final WebViewController _controller;
  bool _done = false;

  static const _html = '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    <style>
      html, body { margin:0; background:#1A1E24; display:flex;
                   align-items:center; justify-content:center; height:100%; }
    </style>
  </head>
  <body>
    <div class="cf-turnstile"
         data-sitekey="{{SITEKEY}}"
         data-callback="onOk"
         data-error-callback="onErr"
         data-expired-callback="onErr"
         data-theme="dark"></div>
    <script>
      function onOk(t)  { Turnstile.postMessage(t); }
      function onErr()  { Turnstile.postMessage(''); }
    </script>
  </body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.graphite)
      ..addJavaScriptChannel(
        'Turnstile',
        onMessageReceived: (msg) {
          if (_done || !mounted) return; // callback can fire more than once
          _done = true;
          final token = msg.message.trim();
          Navigator.of(context).pop(token.isEmpty ? null : token);
        },
      )
      ..loadHtmlString(
        _html.replaceFirst('{{SITEKEY}}', TurnstileConfig.siteKey),
        baseUrl: TurnstileConfig.origin,
      );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 260,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(
              'Just checking you\'re human',
              style: TextStyle(color: AppColors.cream, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}
