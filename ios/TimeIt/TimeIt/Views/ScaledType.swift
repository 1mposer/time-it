import SwiftUI

// MARK: Dynamic Type (owner ruling 8, 2026-10-06; ruling 9a, 2026-10-31)
//
// Every touched-surface text scales FROM its Figma size: the size is a
// `@ScaledMetric` relative to the nearest system text style
// (`Theme.Typography`), applied as `.system(size:weight:)`. At the default
// text size (`.large`) that is exactly the Figma size — nothing moves — and
// the text grows and shrinks with the user's setting in step with its style.

extension Theme {
    /// The Figma text styles → the system text style each scales with. The
    /// shipped-truth home for the font map (ADR-0009): the Figma file holds
    /// the sizes, this table holds how they scale.
    enum Typography {
        /// The nearest system text style to a Figma point size (by the
        /// styles' default sizes: caption2 11, caption 12, footnote 13,
        /// subheadline 15, callout 16, body 17, title3 20, title2 22,
        /// title 28, largeTitle 34). Figma's 10 and 14 land on the style
        /// below their size (Axis Label → caption2, Body 14 → subheadline);
        /// the hero's 24 numeral scales with title2.
        static func textStyle(forFigmaSize size: CGFloat) -> Font.TextStyle {
            switch size {
            case ..<11.75: return .caption2
            case ..<12.5: return .caption
            case ..<13.5: return .footnote
            case ..<15.5: return .subheadline
            case ..<16.5: return .callout
            case ..<18.5: return .body
            case ..<21: return .title3
            case ..<26: return .title2
            case ..<31: return .title
            default: return .largeTitle
            }
        }

        /// The Figma text styles in use on the touched surfaces (read live
        /// 2026-11-04, SF Pro, line height auto) — pinned by the tests.
        enum FigmaStyle: CaseIterable {
            case title          // Title 17 Semibold
            case cardTitle      // Card Title Medium 15
            case body           // Body 14
            case footnote       // Footnote 13
            case headerMeta     // Header Meta Regular 13
            case cardSubtitle   // Card Subtitle Regular 12
            case hourLabel      // Hour Label Regular 12
            case ratingBadge    // Rating Badge Semibold 12
            case chipSmall      // Chip Small Medium 11
            case axisLabel      // Axis Label Regular 10
            case heroNumeral    // the hero ring's Semibold 24
            case score          // Score Semibold 28

            var size: CGFloat {
                switch self {
                case .title: return 17
                case .cardTitle: return 15
                case .body: return 14
                case .footnote, .headerMeta: return 13
                case .cardSubtitle, .hourLabel, .ratingBadge: return 12
                case .chipSmall: return 11
                case .axisLabel: return 10
                case .heroNumeral: return 24
                case .score: return 28
                }
            }

            var textStyle: Font.TextStyle { Typography.textStyle(forFigmaSize: size) }
        }
    }
}

/// `.system(size:weight:)` scaled with the size's text style, optionally
/// capped (the hero ring numeral must still fit its fixed ring).
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let maxSize: CGFloat?

    init(size: CGFloat, weight: Font.Weight, maxSize: CGFloat?) {
        _size = ScaledMetric(wrappedValue: size,
                             relativeTo: Theme.Typography.textStyle(forFigmaSize: size))
        self.weight = weight
        self.maxSize = maxSize
    }

    func body(content: Content) -> some View {
        content.font(.system(size: maxSize.map { Swift.min(size, $0) } ?? size, weight: weight))
    }
}

extension View {
    /// The Figma size `size`, scaling with the user's text size through its
    /// nearest system text style (`Theme.Typography`). Identical to
    /// `.font(.system(size:weight:))` at the default text size.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, maxSize: CGFloat? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, maxSize: maxSize))
    }

    /// `AtLeastSquareLayout` around this view.
    func atLeastSquare() -> some View {
        AtLeastSquareLayout { self }
    }

    /// `MinHeightLayout` around this view.
    func minHeightFloor(_ minHeight: CGFloat) -> some View {
        MinHeightLayout(minHeight: minHeight) { self }
    }
}

/// A floor, not a fixed height: the child is laid out at least `minHeight`
/// tall (so a `Spacer` inside it still fills the floor — even in a lazy
/// stack, which proposes no height), and at its own taller height once the
/// text outgrows it. The dashboard card's name → strip block (65 at the
/// default text size) uses it.
struct MinHeightLayout: Layout {
    var minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: Swift.max(minHeight, ideal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for child in subviews {
            child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// At least square: as tall as it is wide (the detail's metric cards at the
/// default text size), taller once its scaled text needs the room.
struct AtLeastSquareLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let width = proposal.width ?? ideal.width
        return CGSize(width: width, height: Swift.max(width, ideal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for child in subviews {
            child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
