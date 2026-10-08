# Routing with go_router

How to navigate from WarpLink links with `go_router`. The same ideas apply to `Navigator` 2 and any other router.

## Two link handlers, one URL

A Flutter app can receive a link in two ways at once:

1. **WarpLink.** The plugin sees the URL, resolves it, and calls your `onLink` with the destination and custom parameters.
2. **Flutter's deep link handler.** Enabled by default. Flutter forwards the incoming URL to your router as a route, so `https://aplnk.to/abc123` becomes a route lookup for `/abc123`. On Android cold start the route can arrive without its host, so the router cannot recognize it as a WarpLink URL.

Use one setup: switch Flutter's handler off and route from `onLink` alone.

## Setup

Switch Flutter's handler off.

iOS, in `ios/Runner/Info.plist`:

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

Android, inside `<activity>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
```

Then route from `onLink`. Create the router once, outside any widget, with its own navigator key, and call `configure` from the `initState` of your root widget. A cold-start link can arrive before the first frame, when the router is not mounted yet, so `goTo` waits for it:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const Placeholder()), // your home screen
    GoRoute(
      path: '/product/:id',
      builder: (context, state) => Scaffold(
        body: Center(child: Text('Product ${state.pathParameters['id']}')),
      ), // your product screen
    ),
  ],
);

void goTo(String location) {
  if (rootNavigatorKey.currentContext != null) {
    router.go(location);
    return;
  }
  // The first frame has not mounted the router yet.
  WidgetsBinding.instance.addPostFrameCallback((_) => router.go(location));
}

void main() => runApp(const App());

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    unawaited(
      WarpLink.configure(
        apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
        onLink: (event) {
          switch (event) {
            case LinkEvent(:final deepLink):
              final productId = deepLink.customParams['product_id'];
              goTo(productId is String ? '/product/$productId' : '/');
            case ErrorEvent(:final error):
              debugPrint('WarpLink ${error.wireCode}: ${error.message}');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: router);
}
```

Put the route in a link's custom parameters in the dashboard (for example `product_id`) and your app decides where it goes. This keeps your URL structure out of the short link.

A deferred match on the first launch arrives the same way.

## If you need Flutter's own deep linking

If the app must keep Flutter's own deep linking for other, non-WarpLink domains, WarpLink cannot share the same links safely. Keep the WarpLink domains out of Flutter's route table, and do not rely on router-side host matching to recognize WarpLink URLs.

## Manual mode with go_router

With `automaticDeepLinks: false`, wire the stream and the launch link yourself. This widget sits under `MaterialApp.router`, so the router is mounted when it routes:

```dart
class LinkListener extends StatefulWidget {
  const LinkListener({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<LinkListener> createState() => _LinkListenerState();
}

class _LinkListenerState extends State<LinkListener> {
  StreamSubscription<WarpLinkEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_listen());
  }

  Future<void> _listen() async {
    await WarpLink.configure(
      apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
      automaticDeepLinks: false,
    );
    _subscription = WarpLink.onDeepLink.listen(_route);
    final link = await WarpLink.getInitialDeepLink();
    if (link != null) _route(LinkEvent(link));
  }

  void _route(WarpLinkEvent event) {
    if (event case LinkEvent(:final deepLink)) {
      widget.router.go(deepLink.deepLinkUrl ?? '/');
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

`deepLinkUrl` is the in-app URL set on the link for the current OS. Use a path your router understands (for example `/product/123`), or map the link to a route yourself from `customParams`.

## Other routers

The pattern is the same for `Navigator` 2, `auto_route`, and similar packages: keep a handle on the router, call it from `onLink` once the router is mounted, and keep Flutter's own handler off.

## Related Guides

- [Integration Guide](integration-guide.md#step-7-decide-on-flutters-deep-linking-flag)
- [Troubleshooting](troubleshooting.md#4-router-shows-an-unknown-route)
