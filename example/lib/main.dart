import 'package:flutter/material.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

// Replace with an SDK key from Keys > SDK keys in the dashboard.
const String _sdkKey = 'wl_live_00000000000000000000000000000000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WarpLink.configure(apiKey: _sdkKey, onLink: _onLink);
  runApp(const ExampleApp());
}

void _onLink(WarpLinkEvent event) {
  switch (event) {
    case LinkEvent(:final deepLink):
      debugPrint('Link ${deepLink.linkId}: ${deepLink.destination}');
    case ErrorEvent(:final error):
      debugPrint('WarpLink ${error.wireCode}: ${error.message}');
  }
}

/// A single screen that shows the version the native SDK reports.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('WarpLink example')),
        body: Center(
          child: FutureBuilder<String>(
            future: WarpLink.sdkVersion(),
            builder: (context, snapshot) =>
                Text('Native SDK: ${snapshot.data ?? snapshot.error ?? '...'}'),
          ),
        ),
      ),
    );
  }
}
