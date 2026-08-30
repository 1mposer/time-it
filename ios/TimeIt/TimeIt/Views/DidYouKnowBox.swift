import SwiftUI

/// The wizard's dismissible tip box (§8): tinted rounded box, lightbulb icon,
/// "Did you know?" header, bullet body, ✕ button. Dismissal is permanent via
/// `@AppStorage("didYouKnow.<key>")`.
struct DidYouKnowBox: View {
    private let body_: String
    @AppStorage private var dismissed: Bool

    init(key: String, body: String) {
        body_ = body
        _dismissed = AppStorage(wrappedValue: false, "didYouKnow.\(key)")
    }

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accentOrange)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Did you know?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(body_)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(19)
            .background(Theme.accentOrange.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

#if DEBUG
#Preview("Did you know — metric modes") {
    VStack(spacing: 16) {
        DidYouKnowBox(key: "metricModes",
                      body: "If 'Priority' is selected for a metric, it will be considered more in the calculation.")
        DidYouKnowBox(key: "nightRange",
                      body: "This activity is rated per night.")
    }
    .padding()
    .background(Theme.appBackground)
}
#endif
