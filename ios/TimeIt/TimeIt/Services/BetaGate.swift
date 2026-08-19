import Foundation

/// The beta-build runtime gate (beta-feedback spec §3). One archive serves
/// TestFlight and the App Store, so beta surfaces key off the install
/// receipt's name — "sandboxReceipt" on dev + TestFlight installs, "receipt"
/// on App Store installs. Controls BOTH the dashboard disclaimer banner and
/// the suggestion entry point. The App Store release-candidate build flips
/// this off in code (guideline 2.2 — item 9's release-submission step: the
/// banner goes, the button relocates to Settings).
enum BetaGate {

    /// The pure rule, seamed for tests: a sandbox receipt marks a beta install.
    static func isBetaInstall(receiptURL: URL?) -> Bool {
        receiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// The shipped gate. UI-test mock runs pin it explicitly both ways
    /// (UITEST_BETA present/absent) — the simulator's receipt name must never
    /// decide what a hermetic test sees.
    static var isActive: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return ProcessInfo.processInfo.arguments.contains("UITEST_BETA")
        }
        #endif
        return isBetaInstall(receiptURL: Bundle.main.appStoreReceiptURL)
    }
}
