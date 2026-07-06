import SwiftUI

/// Gradient dashboard header: current wall-clock time plus `—` weather
/// placeholders (live header weather is deferred to a later issue). The
/// top-right control is the Settings gear — there is no sign-in (ADR-0001).
struct HeaderView: View {
    let onGearTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                TimelineView(.everyMinute) { context in
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 60, weight: .bold, design: .default))
                        .tracking(-2.5)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("headerTime")
                }

                Text("—°C")
                    .font(.system(size: 28, weight: .light))
                    .tracking(-0.5)
                    .foregroundStyle(.white.opacity(0.92))

                HStack(spacing: 24) {
                    HStack(spacing: 5) {
                        Image(systemName: "wind")
                            .font(.system(size: 12))
                            .accessibilityLabel("Wind")
                        Text("— km/h")
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "humidity.fill")
                            .font(.system(size: 12))
                            .accessibilityLabel("Humidity")
                        Text("—%")
                    }
                }
                .font(.system(size: 13))
                .tracking(0.1)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)

            Button(action: onGearTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 18)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsGear")
        }
        .fixedSize(horizontal: false, vertical: true)
        // Content stays in the safe area (a control under the status bar is
        // untappable); only the gradient extends behind it.
        .background(Theme.headerGradient.ignoresSafeArea(edges: .top))
    }
}
