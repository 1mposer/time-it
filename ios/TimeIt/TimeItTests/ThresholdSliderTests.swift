import XCTest
@testable import TimeIt

/// Pins the slider-facing catalog additions (the settled per-metric table),
/// the preset → threshold mapping (one tap = a working Must-have threshold),
/// and the legacy escape hatch (a bound outside the declared boundStyle
/// renders dual-thumb so no data is hidden or lost).
final class ThresholdSliderTests: XCTestCase {

    private let catalog = StaticMetricCatalog()

    private func descriptor(_ key: String) -> MetricDescriptor {
        guard let descriptor = catalog.descriptor(for: key) else {
            fatalError("\(key) missing from catalog")
        }
        return descriptor
    }

    // MARK: the settled per-metric table

    func testPerMetricTableIsExactlyAsSettled() {
        let expected: [(key: String, style: BoundStyle, gradient: GradientSemantic,
                        presetMin: Double?, presetMax: Double?)] = [
            ("temp", .range, .dangerBothEnds, 15, 32),
            ("humidity", .maxOnly, .dangerHigh, nil, 70),
            ("windSpeed", .maxOnly, .dangerHigh, nil, 25),
            ("rainFall", .maxOnly, .dangerHigh, nil, 0.2),
            ("cloudCover", .maxOnly, .dangerHigh, nil, 40),
            ("visibility", .minOnly, .dangerLow, 8, nil),
            ("uV", .maxOnly, .dangerHigh, nil, 8),
        ]
        for row in expected {
            let descriptor = descriptor(row.key)
            XCTAssertEqual(descriptor.boundStyle, row.style, "\(row.key) boundStyle")
            XCTAssertEqual(descriptor.gradient, row.gradient, "\(row.key) gradient")
            XCTAssertEqual(descriptor.presetMin, row.presetMin, "\(row.key) presetMin")
            XCTAssertEqual(descriptor.presetMax, row.presetMax, "\(row.key) presetMax")
        }
    }

    func testNonNumericMetricsCarryNoSliderTable() {
        for key in ["moon", "dustAlert"] {
            XCTAssertNil(descriptor(key).boundStyle, "\(key) has no slider")
            XCTAssertNil(descriptor(key).gradient)
            XCTAssertNil(descriptor(key).presetMin)
            XCTAssertNil(descriptor(key).presetMax)
        }
    }

    func testUVRangeIsTheCatalogZeroToTwelve() {
        // Settled: 0…12 / 1, NOT 1–9 — the catalog is the source of truth.
        XCTAssertEqual(descriptor("uV").range, MetricRange(min: 0, max: 12, step: 1))
    }

    // MARK: preset → threshold values

    func testPresetThresholdPrefillsBothBoundsForTemp() {
        let draft = ThresholdDraft(preset: descriptor("temp"))
        XCTAssertEqual(draft.minText, "15")
        XCTAssertEqual(draft.maxText, "32")
        XCTAssertTrue(draft.required, "one tap = a working Must-have threshold")
        XCTAssertFalse(draft.isFlag)
    }

    func testPresetThresholdPrefillsMaxOnlyForRainFall() {
        let draft = ThresholdDraft(preset: descriptor("rainFall"))
        XCTAssertEqual(draft.minText, "")
        XCTAssertEqual(draft.maxText, "0.2", "the half-step preset survives formatting")
        XCTAssertTrue(draft.required)
    }

    func testPresetThresholdPrefillsMinOnlyForVisibility() {
        let draft = ThresholdDraft(preset: descriptor("visibility"))
        XCTAssertEqual(draft.minText, "8")
        XCTAssertEqual(draft.maxText, "")
        XCTAssertTrue(draft.required)
    }

    func testPresetThresholdForTheFlagMetricIsAFlag() {
        let draft = ThresholdDraft(preset: descriptor("dustAlert"))
        XCTAssertTrue(draft.isFlag)
        XCTAssertTrue(draft.required)
        XCTAssertEqual(draft.minText, "")
        XCTAssertEqual(draft.maxText, "")
    }

    // MARK: escape hatch — legacy bound outside boundStyle → dual-thumb

    func testLegacyMinOnAMaxOnlyMetricRendersDualThumb() {
        var draft = ThresholdDraft()
        draft.minText = "5"
        draft.maxText = "25"
        XCTAssertEqual(ThresholdSlider.effectiveBoundStyle(for: descriptor("windSpeed"), draft: draft),
                       .range, "a pre-redesign windSpeed min must stay visible and editable")
    }

    func testLegacyMaxOnAMinOnlyMetricRendersDualThumb() {
        var draft = ThresholdDraft()
        draft.maxText = "15"
        XCTAssertEqual(ThresholdSlider.effectiveBoundStyle(for: descriptor("visibility"), draft: draft),
                       .range)
    }

    func testDeclaredStyleHoldsWhenOnlyItsOwnBoundExists() {
        var maxOnly = ThresholdDraft()
        maxOnly.maxText = "25"
        XCTAssertEqual(ThresholdSlider.effectiveBoundStyle(for: descriptor("windSpeed"), draft: maxOnly),
                       .maxOnly)

        var minOnly = ThresholdDraft()
        minOnly.minText = "8"
        XCTAssertEqual(ThresholdSlider.effectiveBoundStyle(for: descriptor("visibility"), draft: minOnly),
                       .minOnly)

        XCTAssertEqual(ThresholdSlider.effectiveBoundStyle(for: descriptor("temp"), draft: ThresholdDraft()),
                       .range, "a dual-thumb metric is dual-thumb regardless of bounds")
    }

    // MARK: snapping

    func testThumbValuesSnapToTheMetricStep() {
        let humidity = MetricRange(min: 0, max: 100, step: 5)
        XCTAssertEqual(ThresholdSlider.snap(52.4, to: humidity), 50)
        XCTAssertEqual(ThresholdSlider.snap(53, to: humidity), 55)
        XCTAssertEqual(ThresholdSlider.snap(-3, to: humidity), 0, "clamped to the range floor")
        XCTAssertEqual(ThresholdSlider.snap(104, to: humidity), 100, "clamped to the range ceiling")

        let rain = MetricRange(min: 0, max: 20, step: 0.5)
        XCTAssertEqual(ThresholdSlider.snap(0.3, to: rain), 0.5)
    }
}
