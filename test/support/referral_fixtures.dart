import 'fixtures.dart';

const String reopenMessage =
    'This invitation cannot be used right now. Open the invitation link again.';
const String pendingMessage =
    'We could not confirm this invitation yet. Try again in a minute.';

/// A native deep link map as the 1.2.0 native SDKs send it: the six evidence
/// fields are set.
Map<String, Object?> matchMap({Map<String, Object?> overrides = const {}}) =>
    <String, Object?>{
      ...linkMap(),
      'isDeferred': true,
      'attributionId': 'attr-1',
      'matchMethod': 'install_token',
      'evidenceClass': 'exact',
      'replayState': 'original',
      'capturedParams': <Object?, Object?>{'utm_source': 'friend'},
      'tappedAt': '2026-10-20T10:00:00Z',
      ...overrides,
    };

/// A native claim map.
Map<String, Object?> claimMap({Map<String, Object?> overrides = const {}}) =>
    <String, Object?>{
      'status': 'claimed',
      'referralId': 'ref-1',
      'linkId': 'link-123',
      'linkUrl': 'https://acme.aplnk.to/invite',
      'matchMethod': 'install_token',
      'isExact': true,
      'matchConfidence': 1,
      'flags': <Object?>[],
      'duplicateOf': null,
      'updated': false,
      'replayState': 'original',
      ...overrides,
    };
