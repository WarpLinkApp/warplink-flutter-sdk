import 'package:flutter/material.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

/// Shows the Tether handoff: the system paste button, a plain button that
/// skips it without reading the clipboard, and what the last read ended on.
class TetherDemo extends StatefulWidget {
  /// Creates the demo.
  const TetherDemo({super.key});

  @override
  State<TetherDemo> createState() => _TetherDemoState();
}

class _TetherDemoState extends State<TetherDemo> {
  String _status = 'Copy your invitation text, then paste.';

  void _show(TetherReadResult result) {
    setState(() => _status = describe(result));
  }

  /// Skips Tether. Nothing reads the clipboard, so iOS shows no paste alert.
  void _continueWithoutPasting() {
    setState(() => _status = 'Continuing without a code.');
  }

  /// A short sentence for each way a read can end.
  static String describe(TetherReadResult result) => switch (result) {
    TetherMatched(:final link) => 'Matched ${link.linkId}',
    TetherNoCode(:final reason) => 'No code (${reason?.wireValue ?? 'none'})',
    TetherTest(:final receipt) => 'Test code (${receipt ?? 'no receipt'})',
    TetherUnusable() => 'The code could not be used',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        WarpLinkPasteButton(
          onResult: _show,
          onError: (error) => setState(() => _status = error.message),
        ),
        OutlinedButton(
          onPressed: _continueWithoutPasting,
          child: const Text('Continue without pasting'),
        ),
        Text(_status, textAlign: TextAlign.center),
      ],
    );
  }
}
