import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/sdk_calls.dart';
import 'package:warplink_flutter/src/tether/paste_button_events.dart';
import 'package:warplink_flutter/src/tether/paste_button_style.dart';
import 'package:warplink_flutter/src/tether/tether_route.dart';
import 'package:warplink_flutter/src/tether/tether_read_result.dart';

/// The platform view type of the native paste control.
const String pasteButtonViewType = 'app.warplink/flutter/paste_button';

/// The iOS system paste control. A tap reads the clipboard, sends a Tether
/// code and calls [onResult], and iOS shows no paste alert.
///
/// It shows on iOS 16 and later. On Android and below iOS 16 it takes no space,
/// so keep your own way to continue next to it. A tap that fails calls [onError] when you set it.
class WarpLinkPasteButton extends StatefulWidget {
  /// Creates the button.
  const WarpLinkPasteButton({
    required this.onResult,
    super.key,
    this.onError,
    this.width = 160,
    this.height = 44,
    this.baseBackgroundColor,
    this.baseForegroundColor,
    this.cornerStyle = PasteButtonCornerStyle.system,
    this.displayMode = PasteButtonDisplayMode.iconAndLabel,
  });

  /// Called with what the tap ended on.
  final ValueChanged<TetherReadResult> onResult;

  /// Called when the read failed.
  final ValueChanged<WarpLinkException>? onError;

  /// The width of the button in logical pixels.
  final double width;

  /// The height of the button in logical pixels.
  final double height;

  /// The background color. `null` keeps the system color.
  final Color? baseBackgroundColor;

  /// The icon and label color. `null` keeps the system color.
  final Color? baseForegroundColor;

  /// How the corners are rounded.
  final PasteButtonCornerStyle cornerStyle;

  /// What the button shows.
  final PasteButtonDisplayMode displayMode;

  @override
  State<WarpLinkPasteButton> createState() => _WarpLinkPasteButtonState();
}

class _WarpLinkPasteButtonState extends State<WarpLinkPasteButton> {
  late final Future<bool>? _supported = _askSupport();
  MethodChannel? _viewChannel;

  Future<bool>? _askSupport() {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    return SdkCalls(WarpLinkChannel())
        .flag(WarpLinkMethod.isPasteButtonSupported)
        .onError<WarpLinkException>((_, _) => false);
  }

  Map<String, Object?> get _params => <String, Object?>{
    'baseBackgroundColor': widget.baseBackgroundColor?.toARGB32(),
    'baseForegroundColor': widget.baseForegroundColor?.toARGB32(),
    'cornerStyle': widget.cornerStyle.wireValue,
    'displayMode': widget.displayMode.wireValue,
  };

  void _created(int id) {
    _viewChannel?.setMethodCallHandler(null);
    _viewChannel = MethodChannel('$pasteButtonViewType/$id')
      ..setMethodCallHandler(_onCall);
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'onTether' || !mounted) {
      return;
    }
    final event = decodePasteEvent(call.arguments);
    final error = event.error;
    if (error != null) {
      widget.onError?.call(error);
    } else if (event.result case final result?) {
      routeTetherResult(result);
      widget.onResult(result);
    }
  }

  @override
  void dispose() {
    _viewChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported = _supported;
    if (supported == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<bool>(
      future: supported,
      builder: (context, snapshot) {
        if (snapshot.data == false) {
          return const SizedBox.shrink();
        }
        final params = _params;
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: snapshot.hasData
              ? UiKitView(
                  key: ValueKey<String>(params.toString()),
                  viewType: pasteButtonViewType,
                  creationParams: params,
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _created,
                )
              : null,
        );
      },
    );
  }
}
