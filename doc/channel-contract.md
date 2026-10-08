# Platform channel contract

This file is the contract between the Dart layer (`lib/src/`) and the native plugins (`ios/warplink_flutter/Sources/warplink_flutter/WarpLinkFlutterPlugin.swift` and `android/src/main/kotlin/app/warplink/flutter/WarpLinkFlutterPlugin.kt`). The Dart side is final. Both native plugins implement exactly what is written here. Names and shapes live in `lib/src/channel.dart` and `lib/src/arrival.dart`; tests in `test/` pin them.

Architecture (revision 2, dispatch v2): **Dart owns all link dispatch.** The native SDKs keep the HTTP, retry, attribution, and once-per-install work. The native plugins never dispatch a link on their own: native automatic deep links and automatic deferred deep links are always off. Each native plugin keeps one process-wide **arrival ledger**: it records every URL the host app receives, holds it until Dart claims its delivery, and resolves it once when Dart resolves it. Dart classifies, orders, dedupes, supersedes, resolves through the ledger, fans one result out to `onLink` and `onDeepLink`, and runs the deferred check itself after cold dispatch. This replaces the earlier architecture where the native automatic handlers dispatched and the plugin joined their results with the manual feed. Revision 1 sections that no longer hold are marked SUPERSEDED and kept for reference.

The wire identity stays native: `User-Agent: WarpLink-iOS/<v>` or `WarpLink-Android/<v>`, `sdk_version` is the native version, and `platform` is `ios` or `android`. The plugin adds no new signal and no new identity. Native code uses the public native API only.

## 1. Channels

| Channel | Type | Name | Direction |
|---------|------|------|-----------|
| Methods | `MethodChannel` (standard codec) | `app.warplink/flutter` | Dart to native |
| Arrivals | `EventChannel` (standard codec) | `app.warplink/flutter/arrivals` | native to Dart |

The links channel (`app.warplink/flutter/links`) and the URLs channel (`app.warplink/flutter/urls`) are removed. Native must not register them.

Dart opens the arrivals channel at most once per engine, while at least one Dart consumer wants arrivals (`SharedStream`): the automatic path is on, or an `onDeepLink` subscriber exists. Native may rely on this: `onListen` and `onCancel` pair up. Native should still tolerate a second `onListen` without an `onCancel` by replacing the sink.

Native emits `{ "type": "ready" }` as the first event after every `onListen`, once its listener is open (section 4.2).

## 2. Methods

All methods are asynchronous. Native replies on the platform (main) thread. Arguments arrive as a `Map<String, Object?>` (absent when the method takes none). Results use only standard codec types.

| Method | Arguments | Success result |
|--------|-----------|----------------|
| `configure` | see 2.1 | `null` |
| `handleDeepLink` | `{ "url": String }` | deep link map (section 3.1), or `null` if native resolves nothing. An independent manual request (section 10.5) |
| `isWarpLinkUrl` | `{ "url": String }` | `bool`. An unparsable string is `false` |
| `checkDeferredDeepLink` | none | deep link map, or `null` for a confirmed no-match |
| `getAttributionResult` | none | attribution map (section 3.2), or `null` for no match |
| `isConfigured` | none | `bool` |
| `isAttributionComplete` | none | `bool` |
| `getSdkVersion` | none | `String`: the NATIVE SDK constant (`"1.1.0"`), never the pub package version |
| `getPendingArrivals` | none | `List<Map>` of ledger entries, oldest first (section 4.3) |
| `resolveArrival` | `{ "arrivalId": String }` | deep link map, or `null`. Claims the arrival; join semantics (section 4.4) |
| `claimDelivery` | `{ "arrivalId": String }` | `bool`. `true` to the first claim only (section 4.5) |

`getInitialUrl` is removed. `getInitialDeepLink` is a Dart operation over the launch arrival (section 10.4); it has no native method.

An unknown method answers `notImplemented`.

### 2.1 `configure` arguments

| Key | Type | Meaning |
|-----|------|---------|
| `apiKey` | `String` | Already validated in Dart against `^wl_(live\|test)_[a-zA-Z0-9]{32}$`. Native still validates and answers `E_INVALID_API_KEY_FORMAT` on a mismatch |
| `apiEndpoint` | `String` | Default `https://api.warplink.app/v1` |
| `debugLogging` | `bool` | Native `debugLogging` |
| `linkDomains` | `List<String>` | Forwarded verbatim. Native normalizes (trim, lowercase, URL to host, keep `www.`) and tolerates a non-string element by dropping it |
| `automaticDeepLinks` | `bool` | Always `false`. Maps to iOS `autoDeepLinkHandling` and Android `automaticDeepLinks`. Native must never call iOS `open` or `continue`, or Android `onNewIntent`, from the plugin |
| `automaticDeferredDeepLinks` | `bool` | Always `false`. Maps to iOS `autoDeferredCheck` and Android `automaticDeferredDeepLinks`. Dart runs the check itself (section 10.6) |

`hasOnLink` and `generation` are removed. Native installs no `onLink` sink and writes no `generation`. The generation is Dart-only (section 10.7).

`configure` replies `null` when native configure completes. It does not wait for the launch link or the deferred check. A native configure error answers a normal error reply (section 5); Dart delivers it to `onLink` when one exists, else throws it.

Configure keeps the ledger. A second `configure` never clears entries. Native reuses an identical native configuration across engine replacement. When the configuration changes, native settles or deliberately supersedes ledger work that is in flight before it runs the new `configure`. A malformed key never changes the earlier configuration (B04 in the parity contract).

## 3. Payload shapes

### 3.1 Deep link map

| Key | Type | Notes |
|-----|------|-------|
| `linkId` | `String` | |
| `destination` | `String` | |
| `deepLinkUrl` | `String?` | `null` or absent when the link has no in-app URL |
| `customParams` | `Map<String, Object?>` | JSON values only: `String`, `bool`, `int`, `double`, `null`, nested `Map`, nested `List`. Always present, `{}` when empty. Android builds it by recursion over `JSONObject` and `JSONArray` (`JSONObject.NULL` becomes `null`); iOS uses `JSONValue.foundationValue` |
| `isDeferred` | `bool` | |
| `matchType` | `String?` | `"deterministic"`, `"probabilistic"`, or `null`. Lowercase |
| `matchConfidence` | `num?` | `int` or `double`; Dart converts to `double` |
| `matchGuaranteed` | `bool` | Native-owned. Never derived in Dart. Dart reads an absent value as `false` |

A link resolved by a tap has `isDeferred: false`, `matchType: "deterministic"`, `matchConfidence: 1.0`, `matchGuaranteed: true`.

### 3.2 Attribution map

`linkId`, `matchType`, `matchConfidence`, `matchGuaranteed`, `isDeferred`, same types as above. `matchType` and `matchConfidence` must be present: Dart throws `decodingError` when either is missing. Native answers `null`, not an empty map, when there is no match.

## 4. Arrivals

### 4.1 Ledger entry and event payload

An entry and an arrivals event carry the same map:

| Key | Type | Meaning |
|-----|------|---------|
| `arrivalId` | `String` | Opaque. Native's identity for one OS delivery. Unique per process. Two taps on the same URL have two ids. One OS delivery has one id however often native reports it |
| `url` | `String` | The URL as the OS delivered it |
| `source` | `String` | Diagnostic label of the OS entry point, for example `universal_link`, `custom_scheme`, `app_link`, `intent`. Dart never branches on it |
| `isLaunch` | `bool` | `true` for the arrival that launched this process |
| `seq` | `int` | Native's recording order. Starts at 0 and rises by one per recorded entry, per process. Dart admits arrivals in `seq` order |
| `arrivedAtMs` | `int` | When native recorded the entry, in milliseconds on a native monotonic clock. Comparable only within one process |

`arrivedAtMs` is read when native records the entry, never when it replies or sends the event. Android uses `SystemClock.elapsedRealtime()`. iOS uses `DispatchTime.now().uptimeNanoseconds / 1_000_000`. `ProcessInfo.systemUptime` and `mach_absolute_time` are on Apple's required-reason API list, so the iOS bridge must not call them, and it adds no privacy manifest entry for this. Dart applies supersede and the 1.5 s dedupe window to these timestamps, never to the time it received the entry.

An entry has a native-side state: `pending` (recorded, not resolved), `resolving` (resolve started, native request in flight), `settled` (answer stored). It also has a delivery flag: `delivered` once a `claimDelivery` answered `true`. Neither is on the wire. Dart learns the state by resolving, and the flag by the answer of `claimDelivery`.

### 4.2 Arrivals channel (`app.warplink/flutter/arrivals`)

The first event after `onListen` is `{ "type": "ready" }`. It tells Dart that native's listener is open, so every entry recorded from then on is also announced. Dart requests `getPendingArrivals` only after it received `ready`, and holds the replay and the events that arrive meanwhile until the replay answered. It then joins them by `arrivalId` and admits them in `seq` order.

After `ready`, native writes one event per newly recorded entry, after it recorded the entry in the ledger, while Dart listens. The event is a notification, not the only copy. Events are not queued: the ledger is the queue. A map without `type` `ready` is an entry. A malformed event reaches Dart as an error and is reported, not thrown.

### 4.3 `getPendingArrivals`

Returns every entry the ledger holds that is not `delivered`, whatever its state, in recording order. A `delivered` entry is never returned, so no engine, restart, or replay can deliver it again. Dart calls it after native signalled `ready`, so an entry recorded between the snapshot and the listener cannot be missed: it appears in the list, the event, or both. Dart joins the duplicate by `arrivalId`.

Native must not reply before it knows whether this process has a launch arrival. It never answers early with a list that lacks a launch entry still coming. The rule for the verdict (section 11.7):

- A fresh-launch verdict, once reached, holds for the whole process. A second engine in the process answers at once.
- Android: before the first verdict, `getPendingArrivals` waits until an Activity attaches and the plugin evaluated its Intent and saved state. The absence of an Activity is never a verdict, because a pre-warmed engine attaches its Activity later. A pre-warmed engine with no Activity therefore never answers early. One positive signal ends the wait for a single engine: the plugin's `ServiceAware.onAttachedToService`, which Flutter calls for an engine that runs inside a service. That engine gets an immediate answer with no launch entry. The answer is that engine's alone: it never sets the process-wide launch verdict, so a later Activity engine still reaches its own verdict. Any other headless engine, which never reports `onAttachedToService` and has no Activity, waits until an Activity attaches. A host that needs `getInitialDeepLink` or the replay in such an engine must attach an Activity first. This adds no public API.
- iOS: before the first verdict, the call waits until the launch callback (`application(_:didFinishLaunchingWithOptions:)`, or the first scene connection when scenes are used) was processed and any launch URL recorded.

### 4.4 `resolveArrival` (with join semantics)

The first call for an `arrivalId` starts exactly one native resolve of the entry's URL through the public native manual path (iOS `WarpLink.handleDeepLink`, Android `WarpLink.handleDeepLink`), and stores the future. Every later call for the same id, from the same engine or from a later one, joins the stored future or the stored settled answer. Each call replies from the stored outcome: the deep link map, `null`, or the same error reply. Only the first call calls the native SDK; a second native call for one tap could mint a second tap id and bill a second click.

The native callback attaches to the ledger entry, not to a channel result closure. An engine detach closes channels only: it must not strand a result, and the next engine reads the stored answer through `getPendingArrivals` and `resolveArrival`.

An id the ledger does not hold (never recorded, or dropped by the bound) replies `null`. A `delivered` entry still replies its stored answer while native holds it.

### 4.5 `claimDelivery`

Claims the one delivery of an arrival. Native decides atomically: the first claim of an id that the ledger holds marks the entry `delivered` and replies `true`. Every later claim replies `false`, from the same engine, a later engine, or after a Dart hot restart. An id the ledger does not hold, or dropped by the bound (section 11.10), replies `false`.

Dart claims before it delivers, and delivers to `onLink` and to every `onDeepLink` subscriber only when the answer is `true`. Delivery is at most once per arrival, across engines and hot restarts. Dart also claims an arrival it deliberately suppresses (a foreign URL, a repeat inside the dedupe window, a superseded answer, a no-match), and ignores the answer, so the replay does not offer it again. A claim for an entry in `resolving` marks it `delivered`; native lets the request finish and discards the answer.

When the call fails, Dart reports the failure and delivers nothing. The entry stays undelivered, and the next replay offers it again. Dart keeps no list of claims it still owes.

### 4.6 Links channel and URLs channel

SUPERSEDED. Revision 1 section 4.1 (`app.warplink/flutter/links`, events with `generation`, native `onLink` sink, queue cap 20) and section 4.2 (`app.warplink/flutter/urls`, raw URLs, not queued) are removed. Their roles are the arrivals channel (4.2) and Dart's fan-out (section 10.3).

## 5. Errors

Errors reply as `FlutterError(code:, message:, details:)` on iOS and `result.error(code, message, details)` on Android. The error map is unchanged from revision 1.

| `code` | Native source |
|--------|---------------|
| `E_NOT_CONFIGURED` | call before configure |
| `E_INVALID_API_KEY_FORMAT` | key fails the format regex |
| `E_INVALID_API_KEY` | HTTP 401, or 403 without a password body |
| `E_NETWORK_ERROR` | transport failure after retries |
| `E_SERVER_ERROR` | any other status, and any unknown failure |
| `E_INVALID_URL` | host not in the known set, or path not exactly one segment |
| `E_LINK_NOT_FOUND` | HTTP 404 |
| `E_PASSWORD_REQUIRED` | HTTP 403 with `PASSWORD_REQUIRED` |
| `E_DECODING_ERROR` | malformed response or attribution payload |

- `message`: pass the native error text through unchanged.
- `details`: `null`, except `E_SERVER_ERROR`, where it is `{ "statusCode": int }` when native knows the status.
- A native failure that is not a WarpLink error must map to `E_SERVER_ERROR`. Dart also maps any unknown code to a server error, as a second guard.
- A settled entry that failed stores its error. Every `resolveArrival` of that id replies the same error while native holds the entry.

## 6. Launch link buffering and cold start

SUPERSEDED by sections 4, 10.4, and 11. Revision 1 buffered one raw launch URL (`getInitialUrl`), replayed it through `WarpLink.open` or `WarpLink.onNewIntent` when `automaticDeepLinks` was on, and tied `getInitialDeepLink` to that buffer. The launch URL is now an ordinary ledger entry with `isLaunch: true`. Native replays nothing and calls no automatic entry point.

## 7. Threading

- Method replies and event sink writes happen on the platform main thread on both OSes. Native callbacks already arrive on main.
- No background isolate support. `configure` must run in the root isolate.
- The ledger is shared static state, guarded by a lock on iOS and a synchronized block or atomic reference on Android.

## 8. Package constants

- Package version: `warplinkFlutterVersion` in `lib/src/version.dart` equals `pubspec.yaml` `version`, the top `CHANGELOG.md` heading, the Android pin (`app.warplink:sdk:<v>` in `android/build.gradle.kts`), and the iOS floor (`from:` in `ios/warplink_flutter/Package.swift`). `test/native_pins_test.dart` enforces it.
- Android namespace and plugin class: `app.warplink.flutter`, `WarpLinkFlutterPlugin`. iOS plugin class: `WarpLinkFlutterPlugin`. iOS integration is Swift Package Manager only (no podspec).

## 9. Accepted differences from the React Native SDK

1. Cold start and the deferred check are ordered, as in React Native: the deferred check starts after the launch link is delivered or dropped.
2. The dedupe window (1.5 s) and supersede are Dart's, shared by both platforms. The native 1.0 s and 1.5 s windows never see an automatic arrival.
3. `onDeepLink` subscribers get every warm URL, not deduplicated. The launch URL is not part of `onDeepLink`; read it with `getInitialDeepLink`.
4. No `matchWindowHours`.
5. `serverError` exposes `statusCode`.
6. The Flutter plugin needs no AppDelegate, SceneDelegate, or MainActivity edits.
7. `WarpLink.isWarpLinkUrl` is public.
8. The `configure` future completes when native configure completes. It does not wait for the first cold-start or deferred delivery, and an exception thrown by the host `onLink` surfaces as an uncaught error in the zone, not from the `configure` future. RN awaits the dispatch and rejects `configure`. The `onLink` call for a malformed key or a native configure error still runs inline.
9. A non-map, non-null payload from native for a deep link or attribution result throws `decodingError`. RN returned `null` for a non-object deep link.
10. Arrivals that reach the process before `configure` are retained in the native ledger and delivered after it. RN delivers a pre-configure arrival only through its own cold-start buffer and has no such retention for warm URLs.
11. A late `onDeepLink` subscriber receives the warm URLs the ledger still holds, because they were not delivered. RN has no process-wide replay.
12. `configure` completes before dispatch (difference 8), so the host's `onLink` can run after the returned future. RN awaits the dispatch inside `configure`.

## 10. Dart dispatch (what native can rely on)

### 10.1 Calls Dart makes, and when

- `configure`: advances Dart's generation, opens the arrivals listener (when the automatic path or a subscriber wants arrivals), requests `getPendingArrivals` once native signalled `ready`, then calls native `configure`. No arrival is claimed before native `configure` replied.
- Per arrival, in recording order: `isWarpLinkUrl(url)`; then, for an arrival that resolves, `resolveArrival(arrivalId)`; then `claimDelivery(arrivalId)`, and only a `true` answer delivers. An arrival that does not resolve is claimed and discarded.
- After the launch arrival is delivered or dropped: `isAttributionComplete`, then `checkDeferredDeepLink` while attribution is open.
- `handleDeepLink(url)` for the public manual call. `isWarpLinkUrl` first, to decide the supersede claim (10.5).

### 10.2 Classify, dedupe, supersede

- Native `isWarpLinkUrl` decides whether an arrival is a WarpLink link, before the arrival stamps the dedupe window, supersedes anything, or reaches `onLink`. A classification that fails or takes over 2 s counts as a link; its own resolve then answers `E_INVALID_URL`.
- A foreign URL is delivered to explicit `onDeepLink` subscribers as an `invalidUrl` error, resolved through the ledger. It never claims automatic delivery, never supersedes, and never stamps the dedupe window. With no subscriber it is claimed and discarded without a resolve.
- The dedupe window is 1.5 s between the `arrivedAtMs` of distinct arrivals of the same URL. A negative gap is never a repeat. A repeat delivers nothing to `onLink`. With a subscriber attached it is still resolved for the subscriber alone.
- Every arrival that resolves supersedes older arrivals still resolving. A newer tap takes `onLink` delivery, and the older answer is dropped. Android also cancels the older request in flight. iOS cannot cancel it (section 12.2): Dart only drops the stale answer. A superseded answer that is an error, such as the `E_NETWORK_ERROR` of a request Android cancelled, reaches no recipient, because the supersede caused it. It is still claimed so a replay does not offer it again. A superseded answer that is a link still reaches `onDeepLink` subscribers, never `onLink`, and the held queue applies the same rule when it re-checks an answer. A failed resolve releases its dedupe stamp, so the user's own re-tap resolves.

### 10.3 One resolve, two feeds

`onLink` and every `onDeepLink` subscriber share one `resolveArrival` per arrival and see the same parsed result. A later claim of the same id joins.

### 10.4 Launch arrival and `getInitialDeepLink`

The launch arrival belongs to the automatic path when `onLink` is set and `automaticDeepLinks` is on; Dart delivers it after native `configure`. Otherwise it stays in the ledger until `getInitialDeepLink` takes it: Dart reads the launch entry from `getPendingArrivals`, resolves it with `resolveArrival`, and claims its delivery. The call returns the link only when the claim answers `true`. A failed claim throws and the next call retries. The second call returns `null`. With the automatic path on, `getInitialDeepLink` returns `null`.

### 10.5 `handleDeepLink`

An independent manual request, outside the ledger. It is never part of an arrival's delivery, and code that handles an arrival must use its `arrivalId`. The call always makes its own native `handleDeepLink` request, as React Native does. For a WarpLink URL, Dart records a silent claim first, so an open automatic tap is superseded, including the tap of an arrival of the same URL that is still resolving, as the shared native resolver cancels it. The superseded arrival is still claimed, and it delivers nothing to `onLink`. The answer is the caller's alone.

### 10.6 Deferred check

Dart runs the check itself; native is configured with `automaticDeferredDeepLinks: false`. A match reaches `onLink` once. A no-match delivers nothing. A failure reaches `onLink` as an error and leaves native's once-per-install gate open, so the next launch retries. Overlapping configurations share one check, and the answer goes to the newest configuration.

### 10.7 Generation

Each accepted `configure` is a generation. Only the newest generation delivers to `onLink`. An older generation's answer is silent. An older generation neither claims nor delivers once a newer generation exists. An arrival that no generation delivered stays undelivered, and the newest generation adopts it on its replay, joining the stored resolve. `onDeepLink` subscribers do not depend on the generation.

Dart dispatch is one serialized event queue. Every input is an event handled alone and in order: an arrival announced, a classification, resolve, or claim answered, a `configure` begun or finished, a subscriber added or removed. A handler reads and writes state synchronously and never waits. A native call starts from a handler and its answer returns as a new event. Host callbacks (`onLink`, subscriber listeners) run after the handler committed its state. A callback that calls `configure` queues a `configure` event; it never re-enters the running handler.

Recipients are decided only inside handlers, from the current state, never from a plan stored earlier:

- **Claim decision.** Dart issues `claimDelivery` only when an owner exists at that moment: the automatic path (`onLink` set, `automaticDeepLinks` on, native `configure` succeeded), or an `onDeepLink` subscriber for a warm arrival. With none, the arrival stays undelivered in the native ledger, and the next replay (a configure, a new subscriber, or `getInitialDeepLink`) offers it again. No claim is issued before native `configure` replied; an answer that arrives earlier waits.
- **Delivery.** A `true` claim answer goes to the recipients present when that answer is handled: `onLink` when the automatic path is on and the answer is not a deduped repeat, not superseded, and not an `invalidUrl` refusal, plus every current subscriber (warm arrivals only). A subscriber that cancelled before that event misses it, as a removed listener does in React Native. A launch answer goes to `onLink`, or is held for `getInitialDeepLink`.
- **Skip claims.** An arrival planned as skip (a foreign URL or a repeat with no subscriber) is claimed without a resolve. If a subscriber is present when the claim answers `true`, Dart resolves it then and delivers to the subscribers present at that answer.
- **Held queue.** With no recipient at that moment, the answer goes to one queue of at most 32 answers; the oldest is dropped with a debug log when it is full. Held answers name no recipient. Each is delivered once, to whoever is eligible when it is re-checked: an automatic `configure` (to `onLink`), a new `onDeepLink` subscriber (warm answers), or `getInitialDeepLink` (launch answers). A deduped repeat is never eligible for `onLink`. An answer no recipient could ever take is dropped with a debug log. The flush reads the current `onLink` for every answer and delivers one answer per event, so a callback that reconfigures changes where the rest go.
- **Generations.** Each accepted `configure` is a generation. Only the newest generation's `onLink` receives answers. An arrival in flight when a newer generation appears is not duplicated: the newest generation adopts it, and a claim already issued stands. `onDeepLink` subscribers do not depend on the generation.

## 11. Lifecycle rules for the native ledgers

1. **Process-wide.** The ledger is static state, not per plugin instance. A second Flutter engine, a `FlutterEngineGroup`, an engine detach, or a Dart hot restart must not lose or duplicate an entry. Engine detach closes only that engine's channels.
2. **Record before notify.** Native records an entry before it sends the event.
3. **Never drop, except by the bound.** An undelivered entry stays until its delivery is claimed, or until the bound in rule 10 drops it. Native keeps it when no engine listens, and when Dart is not configured.
4. **Never replace the launch entry.** A warm arrival never replaces or evicts the launch entry. The bound in rule 10 never drops the launch entry while it is undelivered. Once the launch entry is delivered, the bound may drop it first, like any other delivered entry.
5. **Same-delivery dedupe by OS delivery identity.** Two reports of one OS delivery share an `arrivalId`. On iOS the identity is the callback kind and URL within one main run-loop turn (section 11.1). A second tap on the same URL is a new arrival.
6. **iOS: one source per delivery.** With scenes, scene ingress (`scene(_:willConnectTo:options:)`, `scene(_:continue:)`, `scene(_:openURLContexts:)`) is the only source for a delivery a scene handles. App-delegate ingress is the source only when no scene handles it.
7. **Android: fresh-launch verdict.** Only a fresh launch records a launch arrival. The plugin writes its own marker key into Flutter's plugin state bundle in `onSaveInstanceState`, so a restored Activity always reports a non-null bundle that contains the marker; no marker means a fresh launch. An Intent with `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY` is not an arrival. A restored Activity or a recreation is not an arrival. Native holds `getPendingArrivals` until it has this verdict. No host `MainActivity` code is allowed; if the marker proves unreliable in a test, stop and report.
8. **No native auto handler.** Native never calls iOS `open` or `continue`, or Android `onNewIntent`, and installs no native `onLink`. It keeps no timed auto-versus-manual join.
9. **Request counter.** Native tests count native resolve requests per tap: one per admitted arrival that Dart claims.
10. **Bounded ledger.** The ledger holds at most 32 entries, `delivered` ones included. When a new entry would exceed the cap, native drops exactly one entry, the first that applies in this order, and logs a debug line naming the dropped `arrivalId` and its state:
    1. the oldest `delivered` entry, launch or not;
    2. the oldest undelivered entry that is not the launch entry and whose URL native classifies as not a WarpLink link;
    3. the oldest undelivered entry that is not the launch entry.

    The launch entry is never dropped while it is undelivered; once delivered, item 1 applies to it as to any delivered entry. `seq` keeps rising and is never reused. A `resolveArrival` or `claimDelivery` of a dropped id replies `null` or `false`, which Dart reads as a no-match and a lost claim. Dart keeps no list of its own that grows with the ledger: it remembers 256 finished ids and holds no claim debt.

### 11.1 iOS notes

- **Delivery identity.** Every engine registers its own plugin instance, and Flutter hands a callback to the instances of the engines it concerns. Every instance that receives a callback reports it, with no primary instance. Flutter fans one OS callback out to every instance synchronously inside one main run-loop turn, and two taps never share a turn. The process-wide ledger therefore records a delivery once per turn: the same callback kind (open, continue, or scene connect) with the same normalized URL string, seen again in the same turn, is the same delivery. The application delegate and the scene delegate share a kind, so one URL reported by both is one delivery. A set of URLs is normalized by sorting the URL strings, never by set iteration order. The seen set is cleared when the next turn starts (`DispatchQueue.main.async`). The same URL on a later turn is a new arrival. An engine outside the scene that received a callback therefore cannot hide that delivery from the ledger.
- **Reconfigure with a resolve in flight.** A changed native `configure` advances a configuration epoch after native took the new configuration. Each running resolve carries the epoch it started under. A resolve that settles under an older epoch is discarded and sent again, so the stored answer comes from the configuration in force when it settles. The cost is at most one extra native resolve per changed `configure`. An identical `configure` is a no-op and keeps the request in flight.
- **Scene connection without options.** When another plugin handles the scene connection first, Flutter passes nil connection options, and the launch URL may already be consumed. The bridge then leaves the launch verdict open and the first app activation ends the wait, so `getPendingArrivals` is delayed until activation instead of answering "no launch" early. A connection with options and no URL ends the launch window at once. A URL consumed by another plugin is not visible to this plugin, so it records no launch arrival: this is a Flutter platform limit.
- **Activation before a launch follow-up.** Activation ends the launch window. If it comes before a non-scene launch follow-up (`open` or `continue` after `didFinishLaunchingWithOptions` carried a URL), the follow-up is recorded as a warm arrival. The tap is kept and offered to `onLink` and `onDeepLink`, but `getInitialDeepLink` cannot return it.

### 11.2 Android notes

- **Reconfigure with a resolve in flight.** A changed native `configure` advances a configuration epoch after native took the new configuration; the first `configure` advances it too. Each running resolve carries the epoch it started under. A resolve that settles under an older epoch is discarded: with no replies waiting the entry returns to pending. With replies waiting it is sent again under the new epoch, unless a later arrival (a higher `seq`) has started resolving since. A restart would make the native resolver cancel that newer request, reversing the supersede order in section 10.2, so the older entry settles instead with the failure a superseded request gets, and Dart drops it as superseded. The stored answer comes from the configuration in force when it settles. The cost is at most one extra native resolve per changed `configure`. An identical `configure` is a no-op, advances nothing, and keeps the request in flight. Native `configure` does not cancel a resolve in flight (it only abandons a deferred check), so the stale answer always arrives and is discarded. A resolve cancelled by a newer tap settles with a failure that gets the same treatment.

## 12. Accepted limitations

1. **Process death mid-request.** "Never loses a tap" covers arrivals recorded during a live process. If the process dies after the server recorded a click and before the SDK got the answer, the pinned 1.1.0 native APIs accept no caller-supplied tap id, and the ledger is not persisted. A relaunch is a new launch with a new tap id, and may bill a second click.
2. **Crash between claim and delivery.** Dart claims before it delivers, so a crash, or a host `onLink` that throws before it navigates, after a `true` claim loses that one delivery. Native does not offer a delivered entry again. This is the price of at-most-once delivery.
3. **Disposal while a claim is in flight or an answer is held.** Delivery is at most once. An engine disposal or a hot restart can lose a delivery in two cases. A delivery claim is in flight: the old runtime's claim may still win in native, and the old runtime drops its result silently. An answer is held: native granted its claim and the old runtime held it because no eligible recipient existed at delivery time, whether none had appeared yet or the last one had left. Native does not offer a claimed entry again, so the new runtime cannot deliver it.
4. **iOS supersede is navigation parity.** The iOS public `handleDeepLink` always answers and cannot be cancelled, and its retries continue. Dart drops the stale answer, so the host sees one navigation, but the stale request can still complete and bill. Android's manual path shares the resolver and cancels older work. Request cancellation parity on iOS needs a public native resolve API with cancellation, a follow-up for a future native release.

## 13. Contract change log

- Revision 2, Android epoch-safe reconfigure: added the Android notes (section 11.2), matching the iOS rule.
- Revision 2, review round 8: a superseded answer that is an error is delivered to no recipient and is still claimed. A superseded link still reaches `onDeepLink` subscribers (section 10.2).
- Revision 2, iOS delivery identity and epoch-safe reconfigure: removed the primary-instance rule, added the iOS notes (section 11.1).
- Revision 2, review round 7: subscribers receive answers synchronously inside the handler's post-commit phase, so a subscriber that reconfigures or cancels redirects the remaining held answers. Added the disposal limitation for a claim in flight and for a held answer (section 12.3).
- Revision 2, review round 6: dispatch is one serialized event queue, so recipients cannot change under a handler (section 10.7). Held answers name no recipient and are re-checked at flush. A skip claim that a subscriber outlives resolves and delivers to it. A `configure` called from a host callback is queued behind the running handler.
- Revision 2, review round 4: Dart chooses recipients at claim time from the current configuration and subscribers, not from a plan. With no recipient it does not claim. An answer that loses its recipients during the claim goes into one bounded held queue for the next recipient (section 10.7).
- Revision 2, review round 3: a manual `handleDeepLink` always starts its own request and supersedes an automatic tap of the same URL, as in React Native (section 10.5). A configuration change during a delivery claim hands the answer to the newest configuration (section 10.7). The launch entry is never dropped while undelivered; once delivered it may drop first (section 11).
- Revision 2, review round 2: `ackArrival` is replaced by `claimDelivery`. Dart claims, then delivers only on `true`, so delivery is at most once across engines and hot restarts, and Dart keeps no acknowledgement debt. `getPendingArrivals` omits delivered entries. The bound drops delivered entries first and never an undelivered launch entry (section 11.10). Android names `ServiceAware.onAttachedToService` as the one engine-local no-launch signal (section 4.3). Added the crash-window limitation (section 12.2).
- Revision 2, review round 1: entries carry `seq` and `arrivedAtMs` from a native monotonic clock, and Dart orders admission and times the dedupe window by them. Native emits `{ "type": "ready" }` first after `onListen`, and Dart replays only after it. A failed delivery claim is retried on the next replay. The ledger is bounded at 32 entries (section 11.10). Added the pre-warmed engine verdict rule (section 4.3), the accepted differences 10 to 12, and corrected the iOS cancellation wording in section 10.2.
- Revision 2 (dispatch v2): Dart owns link dispatch. Added `getPendingArrivals`, `resolveArrival`, and `ackArrival` (replaced by `claimDelivery` in review round 2), and the arrivals channel `app.warplink/flutter/arrivals` with `{arrivalId, url, source, isLaunch}`. Removed `getInitialUrl`, the links channel, the URLs channel, the `configure` arguments `hasOnLink` and `generation`, and the `generation` field on events. `configure` always sends `automaticDeepLinks: false` and `automaticDeferredDeepLinks: false`. `getInitialDeepLink` works through the launch arrival claim. Native bridges become process-wide arrival ledgers (section 11). Added the accepted limitations (section 12).
- Revision 1: `configure` gained an int `generation` argument, and automatic-path events on the links channel carried `generation`. Native stamped each event with the generation captured by the configure call that installed the emitting sink. SUPERSEDED by revision 2.
