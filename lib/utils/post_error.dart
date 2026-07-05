/// Turns a Supabase insert failure into a message a member can act on. Covers
/// the club word filter and the RLS gates (locked / archived / slow mode / muted
/// / banned), which all surface as policy denials.
String friendlyPostError(Object e) {
  final s = e.toString();
  if (s.contains('BLOCKED_WORD')) {
    return 'Your post contains a word that isn\'t allowed in this club.';
  }
  if (s.contains('row-level security') ||
      s.contains('violates') ||
      s.contains('42501')) {
    return 'You can\'t post right now — the club may be locked or in slow mode, '
        'or you may be muted.';
  }
  return 'Could not post. Please try again.';
}
