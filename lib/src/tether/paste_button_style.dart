/// How `WarpLinkPasteButton` rounds its corners.
enum PasteButtonCornerStyle {
  /// The system picks the radius from the button height.
  system('dynamic'),

  /// A fixed radius.
  fixed('fixed'),

  /// A small radius.
  small('small'),

  /// A medium radius.
  medium('medium'),

  /// A large radius.
  large('large'),

  /// A fully rounded end on both sides.
  capsule('capsule');

  const PasteButtonCornerStyle(this.wireValue);

  /// The value used on the platform channel.
  final String wireValue;
}

/// What `WarpLinkPasteButton` shows. The system draws the words, so they are
/// localized.
enum PasteButtonDisplayMode {
  /// The paste icon and the word.
  iconAndLabel('iconAndLabel'),

  /// The paste icon only.
  iconOnly('iconOnly'),

  /// The word only.
  labelOnly('labelOnly');

  const PasteButtonDisplayMode(this.wireValue);

  /// The value used on the platform channel.
  final String wireValue;
}
