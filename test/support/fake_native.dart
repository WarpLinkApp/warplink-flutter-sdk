import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';

import 'fixtures.dart';

export 'fixtures.dart';

typedef MethodHandler = Object? Function(Map<String, Object?> arguments);

/// One arrival in the fake native ledger.
final class LedgerEntry {
  LedgerEntry({
    required this.arrivalId,
    required this.url,
    required this.source,
    required this.isLaunch,
    required this.seq,
    required this.arrivedAtMs,
  });

  final String arrivalId;
  final String url;
  final String source;
  final bool isLaunch;
  final int seq;
  final int arrivedAtMs;

  /// The stored answer. Set by the first claim, joined by every later one.
  Future<Object?>? answer;

  /// Whether a delivery claim succeeded. Native no longer offers the entry.
  bool delivered = false;

  Map<String, Object?> toMap() => <String, Object?>{
    'arrivalId': arrivalId,
    'url': url,
    'source': source,
    'isLaunch': isLaunch,
    'seq': seq,
    'arrivedAtMs': arrivedAtMs,
  };
}

/// A scriptable stand-in for the native side of the plugin.
///
/// It keeps an arrival ledger the way a real bridge does: entries survive a
/// Dart restart, a claim starts one resolve and later claims join it, and the
/// first delivery claim wins.
final class FakeNative {
  FakeNative() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(methodChannelName),
      _onCall,
    );
    messenger.setMockStreamHandler(
      const EventChannel(arrivalsChannelName),
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          arrivalsSink = sink;
          arrivalsListens++;
          if (readyOnListen) {
            sendReady();
          }
        },
        onCancel: (arguments) {
          arrivalsSink = null;
          arrivalsCancels++;
        },
      ),
    );
    handlers[WarpLinkMethod.configure] = (_) => null;
    handlers[WarpLinkMethod.getPendingArrivals] = (_) async {
      await pendingGate?.future;
      return ledger.map((entry) => entry.toMap()).toList();
    };
    handlers[WarpLinkMethod.resolveArrival] = _resolveArrival;
    handlers[WarpLinkMethod.claimDelivery] = _claimDelivery;
    handlers[WarpLinkMethod.isWarpLinkUrl] = (args) =>
        isWarpLink(args['url']! as String);
    handlers[WarpLinkMethod.handleDeepLink] = (args) =>
        resolveUrl(args['url']! as String);
    handlers[WarpLinkMethod.isAttributionComplete] = (_) => true;
  }

  final Map<String, MethodHandler> handlers = <String, MethodHandler>{};
  final List<MethodCall> calls = <MethodCall>[];

  /// Every entry native recorded, delivered or not.
  final List<LedgerEntry> entries = <LedgerEntry>[];

  /// Ids whose delivery claim succeeded, in order.
  final List<String> claimed = <String>[];

  /// The entries native still offers for delivery.
  List<LedgerEntry> get ledger =>
      entries.where((entry) => !entry.delivered).toList();

  /// URLs of the resolves native started: one per first claim of an arrival.
  final List<String> resolveStarts = <String>[];

  /// Holds a URL's resolve until the completer completes.
  final Map<String, Completer<void>> gates = <String, Completer<void>>{};

  /// Holds an arrival's delivery claim until the completer completes.
  final Map<String, Completer<void>> claimGates = <String, Completer<void>>{};

  /// Delays `getPendingArrivals`, as a pre-warmed engine does while native
  /// has no launch verdict.
  Completer<void>? pendingGate;

  /// Classifies a URL. Default: every `aplnk.to` URL.
  bool Function(String url) isWarpLink = (url) =>
      Uri.parse(url).host == 'aplnk.to';

  /// Answers a resolve. Default: a link for a WarpLink URL, else
  /// `E_INVALID_URL`.
  late Future<Object?> Function(String url) resolver = _defaultResolver;

  /// Whether native signals `ready` as soon as Dart listens. Turn it off to
  /// hold the handshake and call [sendReady] by hand.
  bool readyOnListen = true;

  /// The native monotonic clock, in milliseconds. Move it with [advanceClock].
  int clockMs = 0;

  MockStreamHandlerEventSink? arrivalsSink;
  int arrivalsListens = 0;
  int arrivalsCancels = 0;
  int _nextId = 0;
  int _nextSeq = 0;

  Future<Object?> _onCall(MethodCall call) async {
    calls.add(call);
    final handler = handlers[call.method];
    if (handler == null) {
      throw MissingPluginException(call.method);
    }
    final arguments = call.arguments;
    return handler(
      arguments is Map ? arguments.cast<String, Object?>() : const {},
    );
  }

  Future<Object?> _defaultResolver(String url) async {
    final gate = gates[url];
    if (gate != null) {
      await gate.future;
    }
    if (!isWarpLink(url)) {
      throw PlatformException(code: 'E_INVALID_URL', message: 'foreign');
    }
    return linkMap(linkId: Uri.parse(url).pathSegments.last);
  }

  Future<Object?> resolveUrl(String url) => resolver(url);

  Object? _resolveArrival(Map<String, Object?> args) {
    final entry = entries
        .where((e) => e.arrivalId == args['arrivalId'])
        .firstOrNull;
    if (entry == null) {
      return null;
    }
    return entry.answer ??= () {
      resolveStarts.add(entry.url);
      return resolver(entry.url);
    }();
  }

  Future<bool> _claimDelivery(Map<String, Object?> args) async {
    await claimGates[args['arrivalId']]?.future;
    return claimDeliveryNow(args);
  }

  /// The native claim: the first claim of a held id wins.
  bool claimDeliveryNow(Map<String, Object?> args) {
    final id = args['arrivalId']! as String;
    final entry = entries.where((e) => e.arrivalId == id).firstOrNull;
    if (entry == null || entry.delivered) {
      return false;
    }
    entry.delivered = true;
    claimed.add(id);
    return true;
  }

  /// Moves the native clock forward.
  void advanceClock(Duration by) => clockMs += by.inMilliseconds;

  /// Signals that native opened its listener.
  void sendReady() => arrivalsSink?.success(<String, Object?>{'type': 'ready'});

  /// Records an arrival and announces it, as the bridge does for an OS
  /// delivery. A repeated [id] is the same OS delivery reported again. The
  /// arrival is stamped with [atMs], or the native clock when absent.
  LedgerEntry arrive(
    String url, {
    String? id,
    bool isLaunch = false,
    String source = 'universal_link',
    int? atMs,
  }) {
    final arrivalId = id ?? 'a${_nextId++}';
    var entry = entries.where((e) => e.arrivalId == arrivalId).firstOrNull;
    if (entry == null) {
      entry = LedgerEntry(
        arrivalId: arrivalId,
        url: url,
        source: source,
        isLaunch: isLaunch,
        seq: _nextSeq++,
        arrivedAtMs: atMs ?? clockMs,
      );
      entries.add(entry);
    }
    arrivalsSink?.success(entry.toMap());
    return entry;
  }

  /// Calls to [method], in order.
  List<MethodCall> callsTo(String method) =>
      calls.where((call) => call.method == method).toList();

  /// Arguments of the only call to [method].
  Map<String, Object?> argumentsOf(String method) {
    final matching = callsTo(method);
    expect(matching, hasLength(1));
    return (matching.single.arguments as Map).cast<String, Object?>();
  }

  void dispose() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(methodChannelName),
      null,
    );
    messenger.setMockStreamHandler(
      const EventChannel(arrivalsChannelName),
      null,
    );
  }
}
