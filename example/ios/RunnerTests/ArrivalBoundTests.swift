import XCTest

@testable import warplink_flutter

final class ArrivalBoundTests: XCTestCase {
    private let host = TestHost()
    private let linkURL = "https://aplnk.to/a"
    private let foreignURL = "https://example.com/a"

    @discardableResult
    private func record(_ text: String, launch: Bool = false) -> ArrivalEntry {
        host.ledger.record(url: link(text), source: .universalLink, isLaunch: launch)
    }

    private func fill(_ count: Int, _ text: String) -> [ArrivalEntry] {
        (0..<count).map { _ in record(text) }
    }

    private var heldIds: [String] {
        host.ledger.slots.map(\.entry.id)
    }

    func testTheLedgerHoldsAtMostThirtyTwoAndSeqKeepsRising() {
        let entries = fill(40, linkURL)
        XCTAssertEqual(host.ledger.slots.count, 32)
        XCTAssertEqual(entries.last?.seq, 39)
        XCTAssertEqual(heldIds, entries.suffix(32).map(\.id))
    }

    func testADeliveredEntryGoesFirst() {
        let entries = fill(32, linkURL)
        XCTAssertTrue(host.ledger.claimDelivery(entries[10].id))
        let newest = record(linkURL)
        XCTAssertFalse(heldIds.contains(entries[10].id))
        XCTAssertTrue(heldIds.contains(entries[0].id))
        XCTAssertEqual(heldIds.last, newest.id)
    }

    func testADeliveredLaunchEntryMayGoFirst() {
        let launch = record(linkURL, launch: true)
        _ = fill(31, linkURL)
        XCTAssertTrue(host.ledger.claimDelivery(launch.id))
        record(linkURL)
        XCTAssertFalse(heldIds.contains(launch.id))
    }

    func testAForeignUndeliveredEntryGoesBeforeOlderWarpLinkEntries() {
        let first = record(linkURL)
        let foreign = record(foreignURL)
        _ = fill(30, linkURL)
        record(linkURL)
        XCTAssertTrue(heldIds.contains(first.id))
        XCTAssertFalse(heldIds.contains(foreign.id))
    }

    func testOtherwiseTheOldestUndeliveredNonLaunchEntryGoes() {
        let launch = record(linkURL, launch: true)
        let second = record(linkURL)
        _ = fill(30, linkURL)
        record(linkURL)
        XCTAssertTrue(heldIds.contains(launch.id))
        XCTAssertFalse(heldIds.contains(second.id))
    }

    func testAnUndeliveredLaunchEntryIsNeverDropped() {
        let launch = record(foreignURL, launch: true)
        _ = fill(100, foreignURL)
        XCTAssertTrue(heldIds.contains(launch.id))
        XCTAssertEqual(host.ledger.slots.count, 32)
    }

    func testTheDropIsLoggedWithIdAndState() {
        let first = record(linkURL)
        _ = fill(31, linkURL)
        host.ledger.resolve(first.id, using: host.native) { _ in }
        record(linkURL)
        let line = host.logs.first { $0.contains(first.id) }
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("settled") ?? false)
        XCTAssertEqual(host.logs.count, 1)
    }

    func testADroppedIdAnswersNoMatchAndALostClaim() {
        let first = record(linkURL)
        _ = fill(32, linkURL)
        var answer: ArrivalOutcome?
        host.ledger.resolve(first.id, using: host.native) { answer = $0 }
        guard case .success(let map)? = answer else { return XCTFail("expected a no-match") }
        XCTAssertNil(map)
        XCTAssertFalse(host.ledger.claimDelivery(first.id))
        XCTAssertTrue(host.native.resolveCalls.isEmpty)
    }

    func testAWaiterOfADroppedEntryGetsNoMatchNotSilence() {
        host.native.holdResolves = true
        let first = record(linkURL)
        var answer: ArrivalOutcome?
        host.ledger.resolve(first.id, using: host.native) { answer = $0 }
        _ = fill(32, linkURL)
        guard case .success(let map)? = answer else { return XCTFail("waiter was stranded") }
        XCTAssertNil(map)
        host.native.finishHeldResolve(.success(sampleLink()))
    }
}
