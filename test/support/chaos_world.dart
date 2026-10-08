import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'fake_native.dart';

/// One recipient and what it received, in order.
final class Recipient {
  Recipient(this.name, {required this.arrivalsBefore});

  final String name;
  final List<String> received = <String>[];

  /// Whether the host still expects deliveries: a subscriber until it cancels,
  /// an `onLink` until a newer configuration or a disposal replaces it.
  bool isActive = true;

  /// How many arrivals had been recorded when the recipient was created.
  final int arrivalsBefore;

  /// How many granted claims had been answered to Dart when the recipient
  /// stopped expecting deliveries, or null while it still does.
  int? answersWhenStopped;

  /// Whether the recipient still expected deliveries when Dart handled the
  /// granted claim at [answerIndex] of [ChaosWorld.answered].
  bool wasActiveAtAnswer(int answerIndex) =>
      isActive || answerIndex < answersWhenStopped!;

  /// Whether native `configure` finished for an `onLink` recipient.
  bool isConfigured = true;
}

/// The URLs the arrivals pick from, so repeats and supersedes happen.
const List<String> chaosUrls = <String>[
  'https://aplnk.to/u0',
  'https://aplnk.to/u1',
  'https://aplnk.to/u2',
];

/// A random host driving the SDK against a [FakeNative] with delayed
/// resolves, claims, and native configures, and a disposal in the middle.
final class ChaosWorld {
  ChaosWorld(int seed, this.native) : random = Random(seed) {
    native.handlers[WarpLinkMethod.resolveArrival] = _resolveArrival;
    final claim = native.handlers[WarpLinkMethod.claimDelivery]!;
    native.handlers[WarpLinkMethod.claimDelivery] = (args) async {
      final id = args['arrivalId']! as String;
      _claimsInFlight.add(id);
      try {
        final granted = await Future<Object?>.value(claim(args));
        if (granted == true) answered.add(id);
        return granted;
      } finally {
        _claimsInFlight.remove(id);
      }
    };
  }

  final FakeNative native;
  final Random random;

  /// Every recipient ever created, in creation order.
  final List<Recipient> recipients = <Recipient>[];

  /// Reasons a delivery broke a rule, found while the run went on.
  final List<String> violations = <String>[];

  /// Arrivals whose delivery claim was in flight at the disposal, or that
  /// native had granted and the old runtime still held. The old runtime is
  /// gone, so they may reach no recipient.
  final Set<String> exempt = <String>{};

  /// Arrivals native had granted when the runtime was disposed. The new
  /// runtime keeps no memory of them, so they cannot break a repeat window it
  /// sees.
  final Set<String> claimedBeforeDispose = <String>{};

  /// Ids of granted claims, in the order their answers reached Dart. A
  /// subscriber owes nothing for an answer that arrived after it cancelled.
  final List<String> answered = <String>[];

  /// The position of each native resolve start and finish, in the order they
  /// happened. A resolve that started before another finished was claimed
  /// before it, which is what makes the finished one stale.
  final Map<String, int> resolveStartedAt = <String, int>{};
  final Map<String, int> resolveFinishedAt = <String, int>{};

  /// Counts configurations and disposals, and stamps each arrival with the
  /// count when it was recorded.
  int epoch = 0;
  final Map<String, int> arrivalEpochs = <String, int>{};

  final Map<Recipient, StreamSubscription<WarpLinkEvent>> _subs =
      <Recipient, StreamSubscription<WarpLinkEvent>>{};
  final Queue<Recipient> _configures = Queue<Recipient>();
  final List<Completer<void>> _gates = <Completer<void>>[];
  final List<Future<void>> _calls = <Future<void>>[];
  final Set<String> _claimsInFlight = <String>{};
  int _resolveSteps = 0;
  int _arrivals = 0;
  int _clockMs = 0;

  /// Whether the runtime was disposed once during the run.
  bool isDisposed = false;

  Iterable<Recipient> get _activeSubscribers =>
      _subs.keys.where((sub) => sub.isActive);

  /// Starts a configuration. Native may take its time to answer.
  void configure() {
    epoch++;
    for (final previous in recipients.where((r) => r.name.startsWith('on'))) {
      previous.isActive = false;
    }
    final sink = Recipient(
      'onLink${recipients.length}',
      arrivalsBefore: _arrivals,
    );
    recipients.add(sink);
    sink.isConfigured = false;
    _configures.add(sink);
    native.handlers[WarpLinkMethod.configure] = (_) async {
      final sink = _configures.removeFirst();
      await _maybeHold(0.35);
      sink.isConfigured = true;
      return null;
    };
    _calls.add(
      WarpLink.configure(
        apiKey: validKey,
        automaticDeepLinks: random.nextBool(),
        onLink: (event) => _record(sink, event),
      ),
    );
  }

  /// Attaches an `onDeepLink` subscriber.
  void subscribe() {
    final sink = Recipient(
      'sub${recipients.length}',
      arrivalsBefore: _arrivals,
    );
    recipients.add(sink);
    _subs[sink] = WarpLink.onDeepLink.listen((event) => _record(sink, event));
  }

  /// Cancels a random subscriber.
  Future<void> cancel() async {
    final live = _activeSubscribers.toList();
    if (live.isEmpty) return;
    final sink = live[random.nextInt(live.length)];
    sink.isActive = false;
    sink.answersWhenStopped = answered.length;
    await _subs[sink]!.cancel();
  }

  /// Records an arrival of a random URL, a repeat or a newer link.
  void arrive() {
    final id = 'a${_arrivals++}';
    _clockMs += random.nextBool() ? 300 : 2000;
    if (random.nextDouble() < 0.4) {
      native.claimGates[id] = _newGate();
    }
    final url = chaosUrls[random.nextInt(chaosUrls.length)];
    if (random.nextDouble() < 0.35) {
      native.gates.putIfAbsent(url, _newGate);
    }
    arrivalEpochs[id] = epoch;
    native.arrive(url, id: id, atMs: _clockMs);
  }

  /// Releases one held gate, or does nothing.
  void release() {
    if (_gates.isEmpty) return;
    _gates.removeAt(random.nextInt(_gates.length)).complete();
  }

  /// Disposes the runtime and starts a new one, once.
  Future<void> dispose() async {
    if (isDisposed) return;
    isDisposed = true;
    epoch++;
    claimedBeforeDispose.addAll(native.claimed);
    exempt.addAll(_claimsInFlight);
    exempt.addAll(
      native.entries
          .where((entry) => entry.delivered && !_hasReceived(entry.arrivalId))
          .map((entry) => entry.arrivalId),
    );
    for (final sink in recipients.where((r) => r.isActive)) {
      sink.isActive = false;
      sink.answersWhenStopped = answered.length;
    }
    _subs.clear();
    await WarpLink.resetForTesting();
    _configures.clear();
  }

  /// Releases every gate and lets all calls finish.
  Future<void> settle(Future<void> Function() pump) async {
    do {
      while (_gates.isNotEmpty) {
        _gates.removeLast().complete();
      }
      await pump();
    } while (_gates.isNotEmpty);
    await Future.wait(_calls);
    await pump();
  }

  bool _hasReceived(String id) =>
      recipients.any((r) => r.received.contains(id));

  Completer<void> _newGate() {
    final gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  Future<void> _maybeHold(double chance) async {
    if (random.nextDouble() < chance) {
      await _newGate().future;
    }
  }

  /// Answers with the arrival id as the link id, after the URL's gate.
  Object? _resolveArrival(Map<String, Object?> args) {
    final entry = native.entries
        .where((e) => e.arrivalId == args['arrivalId'])
        .firstOrNull;
    return entry?.answer ??= () async {
      native.resolveStarts.add(entry.url);
      resolveStartedAt[entry.arrivalId] = _resolveSteps++;
      await native.gates[entry.url]?.future;
      resolveFinishedAt[entry.arrivalId] = _resolveSteps++;
      return linkMap(linkId: entry.arrivalId);
    }();
  }

  void _record(Recipient sink, WarpLinkEvent event) {
    final id = (event as LinkEvent).deepLink.linkId;
    if (!sink.isActive || !sink.isConfigured) {
      violations.add(
        '${sink.name} received $id active=${sink.isActive} configured=${sink.isConfigured}',
      );
    }
    sink.received.add(id);
  }
}
