import XCTest

@testable import warplink_flutter

final class ArrivalLedgerTests: XCTestCase {
    private let host = TestHost()

    private func record(_ text: String = "https://aplnk.to/a", launch: Bool = false) -> ArrivalEntry {
        host.ledger.record(url: link(text), source: .universalLink, isLaunch: launch)
    }

    func testSeqStartsAtZeroAndRisesByOne() {
        let seqs = (0..<4).map { _ in record().seq }
        XCTAssertEqual(seqs, [0, 1, 2, 3])
    }

    func testEntryPayloadCarriesTheContractKeys() {
        let entry = record("https://aplnk.to/abc", launch: true)
        let payload = entry.payload
        XCTAssertEqual(
            Set(payload.keys),
            ["arrivalId", "url", "source", "isLaunch", "seq", "arrivedAtMs"]
        )
        XCTAssertEqual(payload["url"] as? String, "https://aplnk.to/abc")
        XCTAssertEqual(payload["source"] as? String, "universal_link")
        XCTAssertEqual(payload["isLaunch"] as? Bool, true)
    }

    func testArrivedAtIsReadWhenTheEntryIsRecordedAndNeverGoesBack() {
        let stamps = (0..<3).map { _ in record().arrivedAtMs }
        XCTAssertEqual(stamps, stamps.sorted())
        XCTAssertEqual(Set(stamps).count, 3)
    }

    func testTwoTapsOnTheSameURLAreTwoArrivals() {
        let first = record("https://aplnk.to/same")
        let second = record("https://aplnk.to/same")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.seq, first.seq + 1)
        XCTAssertEqual(host.ledger.pending().count, 2)
    }

    func testEntryIsInTheLedgerBeforeAnyListenerHearsOfIt() {
        var heard: [Bool] = []
        host.ledger.addListener(UUID()) { [ledger = host.ledger] payload in
            let ids = ledger.pending().compactMap { $0["arrivalId"] as? String }
            heard.append(ids.contains(payload["arrivalId"] as? String ?? ""))
        }
        _ = record()
        XCTAssertEqual(heard, [true])
    }

    func testRemovedListenerHearsNothing() {
        let token = UUID()
        var count = 0
        host.ledger.addListener(token) { _ in count += 1 }
        _ = record()
        host.ledger.removeListener(token)
        _ = record()
        XCTAssertEqual(count, 1)
    }

    func testPendingListsUndeliveredEntriesOldestFirst() {
        let first = record()
        let second = record()
        XCTAssertTrue(host.ledger.claimDelivery(first.id))
        let ids = host.ledger.pending().compactMap { $0["arrivalId"] as? String }
        XCTAssertEqual(ids, [second.id])
    }

    func testOnlyTheFirstClaimWins() {
        let entry = record()
        XCTAssertTrue(host.ledger.claimDelivery(entry.id))
        XCTAssertFalse(host.ledger.claimDelivery(entry.id))
        XCTAssertFalse(host.ledger.claimDelivery("unknown"))
    }

    func testConcurrentClaimsGiveExactlyOneTrue() {
        let entry = record()
        let lock = NSLock()
        var wins = 0
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if host.ledger.claimDelivery(entry.id) {
                lock.lock()
                wins += 1
                lock.unlock()
            }
        }
        XCTAssertEqual(wins, 1)
    }
}
