import XCTest
@testable import TimeIt

// MARK: - Fakes

final class FakeSuggestionAPI: SuggestionSending {
    private(set) var bodies: [FeedbackBody] = []
    var error: Error?

    func send(_ body: FeedbackBody) async throws {
        bodies.append(body)
        if let error { throw error }
    }
}

// MARK: - Tests

/// The suggestion sheet's state machine (beta-feedback spec §4): the exact
/// five-field body on the wire, the never-discard-typed-text rule on any
/// non-204 (Send stays as the retry), the 429 throttle copy, and the client
/// mirror of the route's message rules (trimmed non-empty, 1000-char cap).
@MainActor
final class FeedbackViewModelTests: XCTestCase {

    private var api: FakeSuggestionAPI!

    override func setUp() {
        super.setUp()
        api = FakeSuggestionAPI()
    }

    private func makeViewModel() -> FeedbackViewModel {
        FeedbackViewModel(sender: api,
                          deviceId: "install-uuid",
                          appVersion: "1.0",
                          build: "7",
                          iosVersion: "17.5")
    }

    // MARK: happy path

    func testSendPostsTheFullFiveFieldBodyAndLandsSent() async {
        let viewModel = makeViewModel()
        viewModel.message = "Add wind direction to the dashboard cards."

        await viewModel.send()

        XCTAssertEqual(api.bodies, [FeedbackBody(deviceId: "install-uuid",
                                                 message: "Add wind direction to the dashboard cards.",
                                                 appVersion: "1.0",
                                                 build: "7",
                                                 iosVersion: "17.5")])
        XCTAssertEqual(viewModel.phase, .sent)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: non-204 — the typed text is never discarded

    func testFailureKeepsTheTypedTextAndSurfacesARetryableError() async {
        api.error = APIError.serverError(statusCode: 500)
        let viewModel = makeViewModel()
        viewModel.message = "My typed suggestion"

        await viewModel.send()

        XCTAssertEqual(viewModel.message, "My typed suggestion", "a typed suggestion is never discarded")
        XCTAssertEqual(viewModel.phase, .editing, "back to editing — Send is the retry")
        XCTAssertEqual(viewModel.errorMessage,
                       "Couldn't send your suggestion. Check your connection and try again.")
        XCTAssertTrue(viewModel.canSend, "the retained text is immediately re-sendable")
    }

    func testRetryAfterFailureSucceedsAndClearsTheError() async {
        api.error = APIError.serverError(statusCode: 500)
        let viewModel = makeViewModel()
        viewModel.message = "My typed suggestion"
        await viewModel.send()

        api.error = nil
        await viewModel.send()

        XCTAssertEqual(api.bodies.count, 2, "the retry re-POSTs the same retained text")
        XCTAssertEqual(api.bodies.last?.message, "My typed suggestion")
        XCTAssertEqual(viewModel.phase, .sent)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testThrottled429SurfacesTheThrottleMessage() async {
        api.error = APIError.serverError(statusCode: 429)
        let viewModel = makeViewModel()
        viewModel.message = "One suggestion too many"

        await viewModel.send()

        XCTAssertEqual(viewModel.errorMessage, "Too many suggestions today — try again tomorrow.")
        XCTAssertEqual(viewModel.message, "One suggestion too many", "429 keeps the text too")
        XCTAssertEqual(viewModel.phase, .editing)
    }

    // MARK: the client mirror of the route's message rules (ADR-0007)

    func testWhitespaceOnlyMessageCannotSend() {
        let viewModel = makeViewModel()
        viewModel.message = "   \n  "

        XCTAssertFalse(viewModel.canSend, "whitespace-only is a server 400 — never POSTed")
    }

    func testMessageAtExactlyTheCapSendsButOneOverCannot() {
        let viewModel = makeViewModel()

        viewModel.message = String(repeating: "a", count: 1000)
        XCTAssertTrue(viewModel.canSend, "exactly 1000 chars is within the cap")
        XCTAssertFalse(viewModel.isOverLimit)

        viewModel.message = String(repeating: "a", count: 1001)
        XCTAssertFalse(viewModel.canSend, "the mirror blocks what the server would 400")
        XCTAssertTrue(viewModel.isOverLimit)
    }

    func testGuardedSendNeverHitsTheWire() async {
        let viewModel = makeViewModel()
        viewModel.message = "  "

        await viewModel.send()

        XCTAssertTrue(api.bodies.isEmpty, "an invalid message never reaches the route")
        XCTAssertEqual(viewModel.phase, .editing)
    }
}
