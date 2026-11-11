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

/// The suggestion sheet's state machine: the five-field wire body, typed text
/// never discarded on failure, the 429 throttle copy, the message-rule mirror.
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

    func testSendPostsTheFullBodyWithItsKindAndLandsSent() async {
        let viewModel = makeViewModel()
        viewModel.message = "Add wind direction to the dashboard cards."

        await viewModel.send()

        XCTAssertEqual(api.bodies, [FeedbackBody(deviceId: "install-uuid",
                                                 message: "Add wind direction to the dashboard cards.",
                                                 appVersion: "1.0",
                                                 build: "7",
                                                 iosVersion: "17.5",
                                                 kind: .suggestion)])
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
                       "Couldn't send. Check your connection and try again.")
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

    func testTheLikedSheetSendsKindLiked() async {
        let viewModel = FeedbackViewModel(kind: .liked,
                                          sender: api,
                                          deviceId: "install-uuid",
                                          appVersion: "1.0",
                                          build: "9",
                                          iosVersion: "26.5")
        viewModel.message = "The week dots."

        await viewModel.send()

        XCTAssertEqual(api.bodies.map(\.kind), [.liked])
    }

    func testEachKindHasItsOwnTitleAndPlaceholderButTheSameNote() {
        XCTAssertEqual(FeedbackKind.suggestion.title, "Send a suggestion")
        XCTAssertEqual(FeedbackKind.liked.title, "What have you liked?")
        XCTAssertEqual(FeedbackKind.suggestion.menuTitle, "Send a suggestion")
        XCTAssertEqual(FeedbackKind.liked.menuTitle, "What you liked",
                       "the menu row stays on one line; the sheet keeps the full title")
        XCTAssertNotEqual(FeedbackKind.suggestion.placeholder, FeedbackKind.liked.placeholder)
        XCTAssertEqual(FeedbackViewModel.note,
                       "Please explain what it is you like, dislike, or would suggest.",
                       "the owner's line, verbatim, on both sheets")
    }

    func testGuardedSendNeverHitsTheWire() async {
        let viewModel = makeViewModel()
        viewModel.message = "  "

        await viewModel.send()

        XCTAssertTrue(api.bodies.isEmpty, "an invalid message never reaches the route")
        XCTAssertEqual(viewModel.phase, .editing)
    }
}
