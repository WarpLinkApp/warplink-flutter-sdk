import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

const int runs = 600;
const int casesCount = 30;
const int seedsPerCase = runs ~/ casesCount;
const int stepsPerRun = 14;

/// One recipient and what it received, in order.
final class Sink {
  Sink(this.name);
  final String name;
  final List<String> received = <String>[];
  bool isActive = true;
}

/// A reference model of who must receive each arrival.
///
/// Resolves are instant and only claims are delayed, so the interleavings
/// under test are configure, subscribe, and cancel against pending claims.
final class Model {
  final Map<String, Completer<void>> pending = <String, Completer<void>>{};
  final List<String> unclaimed = <String>[];
  final List<String> held = <String>[];
  final List<Sink> subscribers = <Sink>[];
  Sink? onLink;
  final Map<String, List<String>> expected = <String, List<String>>{};

  bool get wantsArrivals => onLink != null || subscribers.isNotEmpty;

  void give(String id, String to) =>
      expected.putIfAbsent(to, () => <String>[]).add(id);

  void deliver(String id) {
    final sink = onLink;
    if (sink == null && subscribers.isEmpty) {
      held.add(id);
      return;
    }
    if (sink != null) give(id, sink.name);
    for (final sub in subscribers) {
      give(id, sub.name);
    }
  }

  void flush() {
    final ids = List<String>.of(held);
    held.clear();
    ids.forEach(deliver);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var c = 0; c < casesCount; c++) {
    final first = c * seedsPerCase;
    test(
      'random interleavings deliver each arrival once, to the recipients that exist when its claim is confirmed, seeds $first to ${first + seedsPerCase - 1}',
      () async {
        for (var seed = first; seed < first + seedsPerCase; seed++) {
          await _run(seed);
        }
      },
      // Each case stays well under the 30 s default on a loaded machine.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Future<void> _run(int seed) async {
  final random = Random(seed);
  final native = FakeNative();
  await WarpLink.resetForTesting();
  final model = Model();
  final sinks = <Sink>[];
  final subs = <Sink, StreamSubscription<WarpLinkEvent>>{};
  var arrivals = 0;
  var latestConfigure = -1;

  String describe() => 'seed $seed';

  Future<void> configure(bool auto) async {
    final sink = Sink('onLink${sinks.length}');
    final index = ++latestConfigure;
    sinks.add(sink);
    await WarpLink.configure(
      apiKey: validKey,
      automaticDeepLinks: auto,
      onLink: (event) {
        expect(index, latestConfigure, reason: '${describe()} stale onLink');
        sink.received.add((event as LinkEvent).deepLink.linkId);
      },
    );
    model.onLink = auto ? sink : null;
    if (auto) {
      model.flush();
    }
    _replay(model, native);
  }

  await configure(random.nextBool());
  for (var step = 0; step < stepsPerRun; step++) {
    switch (random.nextInt(6)) {
      case 0 || 1:
        final id = 'a${arrivals++}';
        native.arrive('https://aplnk.to/$id', id: id, atMs: arrivals * 2000);
        final gate = native.claimGates[id] = Completer<void>();
        await pump();
        if (model.wantsArrivals) {
          model.pending[id] = gate;
        } else {
          model.unclaimed.add(id);
        }
      case 2:
        await configure(random.nextBool());
      case 3:
        final sink = Sink('sub${sinks.length}');
        sinks.add(sink);
        final wasEmpty = model.subscribers.isEmpty;
        subs[sink] = WarpLink.onDeepLink.listen(
          (event) => sink.received.add((event as LinkEvent).deepLink.linkId),
        );
        model.subscribers.add(sink);
        await pump();
        if (wasEmpty) {
          model.flush();
          _replay(model, native);
        }
      case 4:
        if (model.subscribers.isNotEmpty) {
          final sink = model.subscribers.removeAt(
            random.nextInt(model.subscribers.length),
          );
          await subs.remove(sink)!.cancel();
          await pump();
        }
      default:
        if (model.pending.isNotEmpty) {
          final id = model.pending.keys.elementAt(
            random.nextInt(model.pending.length),
          );
          model.pending.remove(id)!.complete();
          await pump();
          model.deliver(id);
        }
    }
    await pump();
  }
  for (final id in model.pending.keys.toList()) {
    model.pending.remove(id)!.complete();
    await pump();
    model.deliver(id);
  }
  await pump();
  _check(seed, sinks, model, native);
  for (final sub in subs.values) {
    await sub.cancel();
  }
  await WarpLink.resetForTesting();
  native.dispose();
}

/// A replay offers every unclaimed arrival to the recipients now present.
void _replay(Model model, FakeNative native) {
  if (!model.wantsArrivals) return;
  for (final id in model.unclaimed) {
    model.pending[id] = native.claimGates[id]!;
  }
  model.unclaimed.clear();
}

void _check(int seed, List<Sink> sinks, Model model, FakeNative native) {
  for (final sink in sinks) {
    final got = sink.received;
    expect(got.toSet().length, got.length, reason: 'seed $seed duplicate');
    expect(
      got,
      model.expected[sink.name] ?? <String>[],
      reason: 'seed $seed ${sink.name}',
    );
  }
  for (final id in native.claimed) {
    final delivered = sinks.any((s) => s.received.contains(id));
    expect(
      delivered || model.held.contains(id),
      isTrue,
      reason: 'seed $seed: $id claimed but lost',
    );
  }
}
