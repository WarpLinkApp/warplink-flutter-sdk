/// The closed sets of words the Tether handoff uses on the platform channel.
library;

/// How the SDK gets a Tether code from the clipboard.
///
/// Android reads no clipboard in any mode.
enum TetherReadMode {
  /// The SDK never reads the clipboard by itself. The person taps
  /// `WarpLinkPasteButton`, the system paste control, so iOS shows no paste
  /// alert. This is the default.
  pasteButton('paste_button'),

  /// iOS may show its paste alert once, during the first-launch attribution
  /// check.
  automatic('automatic'),

  /// The SDK reads the clipboard only when you call `WarpLink.readTether`.
  onCall('on_call');

  const TetherReadMode(this.wireValue);

  /// The value used on the platform channel and recorded by the server.
  final String wireValue;
}

/// Why no Tether code arrived.
///
/// The SDK reports [pasteNotAllowed], [clipboardEmpty] and [olderSdk]. The
/// server sets [expired], [otherApp] and [linkEnded] when it refuses a code it
/// was sent. [inAppBrowser] is set where the link opened, not on the device.
enum TetherMissReason {
  /// The person refused the paste, or the system did not allow it.
  pasteNotAllowed('paste_not_allowed'),

  /// The clipboard held no text.
  clipboardEmpty('clipboard_empty'),

  /// The link opened in an in-app browser, which cannot hand a code over.
  inAppBrowser('in_app_browser'),

  /// The code had expired.
  expired('expired'),

  /// The code belongs to another app.
  otherApp('other_app'),

  /// The link behind the code has ended.
  linkEnded('link_ended'),

  /// This build is older than the SDK version that reads the clipboard.
  olderSdk('older_sdk');

  const TetherMissReason(this.wireValue);

  /// The value used on the platform channel.
  final String wireValue;

  /// Parses a channel value. Returns `null` for anything unrecognized.
  static TetherMissReason? fromWire(Object? value) {
    for (final reason in values) {
      if (reason.wireValue == value) {
        return reason;
      }
    }
    return null;
  }
}
