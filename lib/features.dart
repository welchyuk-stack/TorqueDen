/// App-wide feature flags.
///
/// Flip one of these to turn a whole capability on or off at build time. Kept
/// deliberately dumb (compile-time constants) so the tree-shaker can drop the
/// disabled paths and there's no runtime state to reason about.
class Features {
  Features._();

  /// In-app video: recording, picking clips from the library, the trim/overlay
  /// editor, and uploading video.
  ///
  /// **Off for launch.** Video is served from Supabase Storage, where egress
  /// ($0.09/GB) is the dominant cost and outweighs ad income per user — so we
  /// ship photos-only to keep bandwidth costs near zero, then re-enable once
  /// there's traction (ideally alongside moving clip delivery to a CDN).
  ///
  /// This flag only gates the places video is *created*; the display widgets
  /// (feed/grid/viewer) are untouched, so flipping this back to `true` restores
  /// the full flow with nothing to migrate.
  static const bool video = false;
}
