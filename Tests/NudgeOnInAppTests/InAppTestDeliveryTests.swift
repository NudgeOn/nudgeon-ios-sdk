import XCTest
@testable import NudgeOnInApp

final class InAppTestDeliveryTests: XCTestCase {
    enum TestError: Error { case offline, disk, http(Int) }
    @MainActor final class Store { var value: String?; var fail = false
        func make(_ notify: @escaping (InAppTestTransferStatus) -> Void = { _ in }) throws -> InAppTestDelivery {
            try InAppTestDelivery(read: { self.value }, write: { if self.fail { throw TestError.disk }; self.value = $0 }, changed: notify)
        }
    }
    private func code(_ error: Error) -> Int? { if case TestError.http(let value) = error { return value }; return nil }

    @MainActor func testOfflineEndRestartAndOrderedReceipts() async throws {
        let store = Store(); let client = try store.make()
        try client.begin("secret-a"); try client.active("run-a")
        for kind in ["presented", "impression", "dismiss"] { try client.append(run: "run-a", kind: kind, detail: "") }
        let ids = client.snapshot.events.map(\.id); try client.close()
        await client.flush(send: { _,_,_ in throw TestError.offline }, httpStatus: code)
        XCTAssertEqual(client.status.phase,.failed); XCTAssertEqual(client.status.pendingCount,3)
        let recovered = try store.make(); XCTAssertTrue(recovered.snapshot.closing)
        var sent: [String] = [], paths: [String] = []
        await recovered.flush(send: { path,body,token in
            XCTAssertEqual(token,"secret-a"); paths.append(path)
            if let id=body["event_id"] { sent.append(id) }
        }, httpStatus: code)
        XCTAssertEqual(sent,ids); XCTAssertEqual(paths.last,"end")
        XCTAssertEqual(recovered.status.phase,.acknowledged); XCTAssertTrue(recovered.status.canEndSafely)
        XCTAssertFalse(recovered.needsRecovery); XCTAssertEqual(recovered.status.acknowledgedCount,3)
    }
    @MainActor func testLostResponseRetriesSameIDWithoutDoubleCount() async throws {
        let store=Store(); let client=try store.make(); try client.begin("a")
        try client.append(run:"r",kind:"dismiss",detail:"close_button"); try client.close()
        var server=Set<String>(), first=true
        let send: InAppTestDelivery.Send = { _, body, _ in
            if let id=body["event_id"] { server.insert(id); if first { first=false; throw TestError.offline } }
        }
        await client.flush(send:send,httpStatus:code)
        XCTAssertEqual(client.status.acknowledgedCount,0)
        let restarted=try store.make(); await restarted.flush(send:send,httpStatus:code)
        XCTAssertEqual(server.count,1); XCTAssertEqual(restarted.status.acknowledgedCount,1)
    }
    @MainActor func testRejectedExpiredSessionNeverAcknowledgesOrEnds() async throws {
        let client=try Store().make(); try client.begin("a"); try client.append(run:"r",kind:"impression",detail:""); try client.close()
        for code in [401] {
            await client.flush(send:{ _,_,_ in throw TestError.http(code) },httpStatus:self.code)
        }
        XCTAssertEqual(client.status.phase,.failed); XCTAssertEqual(client.status.reason,"HTTP_401")
        XCTAssertEqual(client.snapshot.events.count,1); XCTAssertFalse(client.status.canEndSafely)
        XCTAssertThrowsError(try client.begin("other"))
        try client.discard(); XCTAssertEqual(client.status.phase,.idle); XCTAssertEqual(client.status.acknowledgedCount,0)
    }
    @MainActor func testStorageFailureCannotClaimReceiptAndCanRetryWrite() async throws {
        let store=Store(); let client=try store.make(); try client.begin("a")
        try client.append(run:"r",kind:"dismiss",detail:"")
        await client.flush(send:{ _,_,_ in store.fail=true },httpStatus:code)
        XCTAssertEqual(client.status.phase,.failed); XCTAssertEqual(client.status.reason,"STORAGE_ERROR")
        XCTAssertEqual(client.status.acknowledgedCount,0)
        store.fail=false; try client.retryStorage()
        XCTAssertEqual(client.status.acknowledgedCount,1)
    }
    @MainActor func testRestartInterruptsActiveRunWithoutResumingPresentation() throws {
        let store=Store(); let client=try store.make(); try client.begin("a"); try client.active("r")
        try client.append(run:"r",kind:"presented",detail:"")
        let restored=try store.make()
        XCTAssertNil(restored.snapshot.activeRun); XCTAssertTrue(restored.snapshot.closing)
        XCTAssertEqual(restored.snapshot.events.map(\.kind),["presented","failed"])
        XCTAssertEqual(restored.snapshot.events.last?.detail,"PROCESS_RESTARTED")
        let twice=try store.make(); XCTAssertEqual(twice.snapshot.events.count,2)
    }
    @MainActor func testCloseDuringInFlightEventWaitsForReceipt() async throws {
        let store=Store(); let client=try store.make(); try client.begin("a")
        try client.append(run:"r",kind:"dismiss",detail:"")
        var paths:[String]=[]
        await client.flush(send:{ path,_,_ in paths.append(path); if path != "end" { try client.close() } },httpStatus:code)
        XCTAssertEqual(paths,["runs/r/events","end"]); XCTAssertTrue(client.status.canEndSafely)
    }
    @MainActor func testDiscardInFlightDoesNotAcknowledgeAbandonedRecords() async throws {
        let client=try Store().make(); try client.begin("a"); try client.append(run:"r",kind:"dismiss",detail:"")
        await client.flush(send:{ _,_,_ in try client.discard() },httpStatus:code)
        XCTAssertEqual(client.status.phase,.idle); XCTAssertEqual(client.status.acknowledgedCount,0)
    }

    @MainActor func testReviewContextAndClocksSurviveRecovery() async throws {
        var saved: String?; var time = Date(timeIntervalSince1970: 100)
        func make() throws -> InAppTestDelivery {
            try InAppTestDelivery(read: { saved }, write: { saved = $0 }, changed: { _ in }, now: { time })
        }
        let client = try make()
        try client.begin("secret", sessionExpiresAt: "2026-09-19T13:30:00Z")
        try client.updateSessionExpiry("2026-09-19T13:35:00Z")
        try client.active("run-a", revisionID: "revision-a", expiresAt: "2026-09-19T13:05:00Z")
        try client.append(run: "run-a", kind: "dismiss", detail: "")
        await client.flush(send: { _,_,_ in throw TestError.offline }, httpStatus: code)
        XCTAssertEqual(client.status.review?.lastAttemptAt, time)
        XCTAssertNil(client.status.review?.lastReceivedAt)
        let recovered = try make()
        XCTAssertEqual(recovered.status.review, client.status.review)
        time = Date(timeIntervalSince1970: 200)
        await recovered.flush(send: { _,_,_ in }, httpStatus: code)
        let detail = recovered.status.review
        XCTAssertEqual(detail?.runID, "run-a"); XCTAssertEqual(detail?.revisionID, "revision-a")
        XCTAssertEqual(detail?.sessionExpiresAt, "2026-09-19T13:35:00Z")
        XCTAssertEqual(detail?.runExpiresAt, "2026-09-19T13:05:00Z")
        XCTAssertEqual(detail?.lastAttemptAt, time); XCTAssertEqual(detail?.lastReceivedAt, time)
        XCTAssertEqual(try make().status.review, detail)
        try recovered.discard(); XCTAssertNil(recovered.status.review)
    }
    @MainActor func testOldJournalAndNewRunDoNotInventMetadata() throws {
        let store = Store()
        store.value = "{\"events\":[],\"closing\":false,\"acknowledged\":1}"
        let old = try store.make(); XCTAssertNil(old.status.review)
        try old.begin("secret"); try old.active("r1", revisionID: "v1", expiresAt: "expiry")
        try old.active("r2", revisionID: "v2")
        XCTAssertEqual(old.status.review?.runID, "r2"); XCTAssertNil(old.status.review?.runExpiresAt)
        XCTAssertNil(old.status.review?.lastReceivedAt)
    }
    @MainActor func testAttemptStorageFailureDoesNotSend() async throws {
        let store = Store()
        let delivery = try store.make(); try delivery.begin("a"); try delivery.append(run: "r", kind: "dismiss", detail: "")
        store.fail = true
        await delivery.flush(send: { _,_,_ in XCTFail("must persist attempt before transport") }, httpStatus: code)
        XCTAssertEqual(delivery.status.reason, "STORAGE_ERROR"); XCTAssertNil(delivery.status.review?.lastReceivedAt)
    }
}
