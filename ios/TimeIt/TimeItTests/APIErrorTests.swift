import XCTest
@testable import TimeIt

/// The 400 backstop (#5b §7): a structured { errors: [{ path, message }] } body
/// must surface a non-crashing message that names the offending Activity.
final class APIErrorTests: XCTestCase {

    private let labels = ["Cycling", "Stargazing"]

    func testValidationBodyMapsPathIndexToActivityLabel() throws {
        let body = Data("""
        { "errors": [ { "path": "activities[1].thresholds.temp", "message": "min greater than max" } ] }
        """.utf8)

        let error = try XCTUnwrap(APIError.validationRejection(body: body, activityLabels: labels))

        guard case let .validationRejected(message) = error else {
            return XCTFail("expected validationRejected, got \(error)")
        }
        XCTAssertTrue(message.contains("Stargazing"), "path activities[1] → the second activity's label")
        XCTAssertTrue(message.contains("min greater than max"), "the server's message is surfaced")
        XCTAssertFalse(error.isTransient, "a validation 400 is not retryable")
    }

    func testValidationBodyWithoutPathStillSurfacesMessage() throws {
        let body = Data(#"{ "errors": [ { "message": "Malformed JSON in request body" } ] }"#.utf8)

        let error = try XCTUnwrap(APIError.validationRejection(body: body, activityLabels: labels))

        guard case let .validationRejected(message) = error else {
            return XCTFail("expected validationRejected, got \(error)")
        }
        XCTAssertTrue(message.contains("Malformed JSON in request body"))
    }

    func testUnparseableBodyReturnsNil() {
        XCTAssertNil(APIError.validationRejection(body: Data("<html>".utf8), activityLabels: labels),
                     "caller falls back to the generic serverError mapping")
    }
}
