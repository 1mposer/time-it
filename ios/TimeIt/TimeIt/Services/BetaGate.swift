import Foundation

/// The beta-build runtime gate: one archive serves TestFlight and the App
/// Store, so beta surfaces (disclaimer banner + suggestion entry point) key
/// off the install receipt's name — "sandboxReceipt" marks a beta install.
enum BetaGate {

    /// The pure rule, seamed for tests: a sandbox receipt marks a beta install.
    static func isBetaInstall(receiptURL: URL?) -> Bool {
        receiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// The shipped gate. UI-test mock runs pin it explicitly via UITEST_BETA —
    /// the simulator's receipt name must never decide what a hermetic test sees.
    static var isActive: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return ProcessInfo.processInfo.arguments.contains("UITEST_BETA")
        }
        #endif
        return isBetaInstall(receiptURL: Bundle.main.appStoreReceiptURL)
    }
}
