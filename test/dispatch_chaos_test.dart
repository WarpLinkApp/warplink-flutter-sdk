import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/tap_policy.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/chaos_world.dart';
import 'support/fake_native.dart';

const int runs = 600;
const int casesCount = 30;
const int seedsPerCase = runs ~/ casesCount;
const int stepsPerRun = 16;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var c = 0; c < casesCount; c++) {
    final first = c * seedsPerCase;
    test(
      'delayed resolves, claims, configures, repeats, supersedes, and a disposal never break a delivery rule, seeds $first to ${first + seedsPerCase - 1}',
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
  final native = FakeNative();
  await WarpLink.resetForTesting();
  final world = ChaosWorld(seed, native)..configure();
  final disposeAt = seed.isEven ? -1 : seed % stepsPerRun;
  for (var step = 0; step < stepsPerRun; step++) {
    if (step == disposeAt) {
      await world.dispose();
      world.configure();
    }
    await _act(world);
    await pump();
  }
  await world.settle(pump);
  // A last subscriber collects what the run left held.
  world.subscribe();
  await world.settle(pump);
  _check(seed, world);
  await WarpLink.resetForTesting();
  native.dispose();
}

Future<void> _act(ChaosWorld world) async {
  switch (world.random.nextInt(8)) {
    case 0 || 1 || 2:
      world.arrive();
    case 3:
      world.configure();
    case 4:
      world.subscribe();
    case 5:
      await world.cancel();
    default:
      world.release();
  }
}

void _check(int seed, ChaosWorld world) {
  expect(world.violations, isEmpty, reason: 'seed $seed');
  for (final sink in world.recipients) {
    expect(
      sink.received.toSet(),
      hasLength(sink.received.length),
      reason: 'seed $seed ${sink.name} duplicate',
    );
  }
  _checkRepeats(seed, world);
  _checkSupersedes(seed, world);
  _checkSubscribers(seed, world);
  final delivered = world.recipients.expand((r) => r.received).toSet();
  for (final entry in world.native.entries) {
    final isLost =
        entry.answer != null &&
        entry.delivered &&
        !delivered.contains(entry.arrivalId) &&
        !_isDiscardable(world, entry);
    expect(isLost, isFalse, reason: 'seed $seed ${entry.arrivalId} lost');
  }
}

/// Whether native granted the entry and no recipient owes it a delivery: the
/// disposal took it, or it repeats an earlier arrival of its URL with no other
/// URL between them, and nobody who wanted every event was there.
bool _isDiscardable(ChaosWorld world, LedgerEntry entry) =>
    world.exempt.contains(entry.arrivalId) ||
    world.native.entries.any(
      (earlier) =>
          earlier.seq < entry.seq &&
          !_isForgotten(world, earlier, entry) &&
          earlier.url == entry.url &&
          entry.arrivedAtMs - earlier.arrivedAtMs <
              dedupeWindow.inMilliseconds &&
          !world.native.entries.any(
            (between) =>
                between.seq > earlier.seq &&
                between.seq < entry.seq &&
                between.url != entry.url &&
                !_isForgotten(world, between, entry),
          ),
    );

/// Whether the runtime that handled [entry] cannot have seen [earlier]: the
/// disposal ended the runtime that handled [earlier], not the one of [entry].
bool _isForgotten(ChaosWorld world, LedgerEntry earlier, LedgerEntry entry) =>
    world.claimedBeforeDispose.contains(earlier.arrivalId) &&
    !world.claimedBeforeDispose.contains(entry.arrivalId);

/// A subscriber that was there before an arrival gets the answer of every
/// arrival native granted to a living runtime, if the subscriber still
/// listened when Dart handled the answer. That includes repeats and stale
/// answers, which only `onLink` refuses.
void _checkSubscribers(int seed, ChaosWorld world) {
  final subscribers = world.recipients.where((r) => r.name.startsWith('sub'));
  for (final sub in subscribers) {
    for (final entry in world.native.entries.skip(sub.arrivalsBefore)) {
      final answerIndex = world.answered.indexOf(entry.arrivalId);
      final isOwed =
          entry.delivered &&
          entry.answer != null &&
          !world.exempt.contains(entry.arrivalId) &&
          answerIndex >= 0 &&
          sub.wasActiveAtAnswer(answerIndex);
      expect(
        isOwed && !sub.received.contains(entry.arrivalId),
        isFalse,
        reason: 'seed $seed ${sub.name} missed ${entry.arrivalId}',
      );
    }
  }
}

/// The arrivals the newest configuration saw, in arrival order. Earlier ones
/// may be replayed under a new configuration that forgets what came before.
List<LedgerEntry> _lastEpoch(ChaosWorld world) => world.native.entries
    .where((entry) => world.arrivalEpochs[entry.arrivalId] == world.epoch)
    .toList();

Iterable<Recipient> _onLinks(ChaosWorld world) =>
    world.recipients.where((r) => r.name.startsWith('on'));

/// A repeat never reaches `onLink`, unless it took over from the tap that
/// owned the window, which then went stale. So of the same URL arriving again
/// inside the window, with no other URL between, `onLink` gets at most one.
void _checkRepeats(int seed, ChaosWorld world) {
  final received = _onLinks(world).expand((r) => r.received).toSet();
  LedgerEntry? first;
  var inWindow = <LedgerEntry>[];
  void close() {
    final reached = inWindow.where((e) => received.contains(e.arrivalId));
    expect(
      reached.length,
      lessThanOrEqualTo(1),
      reason: 'seed $seed repeats ${reached.map((e) => e.arrivalId)}',
    );
  }

  for (final entry in _lastEpoch(world)) {
    final isRepeat =
        first != null &&
        entry.url == first.url &&
        entry.arrivedAtMs - first.arrivedAtMs < dedupeWindow.inMilliseconds;
    if (!isRepeat) {
      close();
      first = entry;
      inWindow = <LedgerEntry>[];
    }
    inWindow.add(entry);
  }
  close();
}

/// A resolve that started before another finished was claimed first, so the
/// finished one is stale and never reaches `onLink`.
void _checkSupersedes(int seed, ChaosWorld world) {
  final entries = _lastEpoch(world);
  final received = _onLinks(world).expand((r) => r.received).toSet();
  for (final stale in entries) {
    final finished = world.resolveFinishedAt[stale.arrivalId];
    final isSuperseded =
        finished != null &&
        entries.any((newer) {
          final started = world.resolveStartedAt[newer.arrivalId];
          return newer.seq > stale.seq && started != null && started < finished;
        });
    expect(
      isSuperseded && received.contains(stale.arrivalId),
      isFalse,
      reason: 'seed $seed ${stale.arrivalId} stale answer reached onLink',
    );
  }
}
