import XCTest
@testable import TimeIt

/// The beta-feedback spec §3 gate rule, pinned both ways: a sandbox receipt
/// (dev + TestFlight install) opens the gate; an App Store receipt — or no
/// receipt at all — keeps it shut.
final class BetaGateTests: XCTestCase {

    func testSandboxReceiptMarksABetaInstall() {
        let url = URL(fileURLWithPath: "/data/Application/X/StoreKit/sandboxReceipt")
        XCTAssertTrue(BetaGate.isBetaInstall(receiptURL: url))
    }

    func testAppStoreReceiptIsNotABetaInstall() {
        let url = URL(fileURLWithPath: "/data/Application/X/StoreKit/receipt")
        XCTAssertFalse(BetaGate.isBetaInstall(receiptURL: url))
    }

    func testMissingReceiptIsNotABetaInstall() {
        XCTAssertFalse(BetaGate.isBetaInstall(receiptURL: nil))
    }
}
