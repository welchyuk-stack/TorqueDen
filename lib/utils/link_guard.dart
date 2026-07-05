/// Detects web links / bare domains in free text. Used to keep promotional
/// links out of the build log and garage — the sanctioned place for a business
/// link is a Partner Page.
final RegExp _urlPattern = RegExp(
  r'(https?://|www\.)\S+'
  r'|\b[a-z0-9][a-z0-9-]*\.(com|co\.uk|co|net|org|io|shop|store|dev|app|uk|me|biz|info)\b',
  caseSensitive: false,
);

bool containsUrl(String? text) => text != null && _urlPattern.hasMatch(text);
