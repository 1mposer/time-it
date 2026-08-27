import SwiftUI

/// Beta suggestion sheet: type, Send. A non-204 keeps the typed text with
/// Send as retry (never discarded); success briefly confirms, then dismisses.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FeedbackViewModel

    @MainActor
    init(deviceId: String) {
        _viewModel = StateObject(wrappedValue: FeedbackViewModel(sender: Self.makeSender(),
                                                                 deviceId: deviceId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.phase == .sent {
                    confirmation
                } else {
                    editor
                }
            }
            .background(Theme.appBackground)
            .navigationTitle("Send a suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.phase == .sending)
                }
            }
        }
        // Blocks swipe-to-dismiss mid-send — an orphaned in-flight POST would
        // have no visible outcome; editing text stays cancellable.
        .interactiveDismissDisabled(viewModel.phase == .sending)
        .onChange(of: viewModel.phase) { _, phase in
            guard phase == .sent else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $viewModel.message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 160)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
                .accessibilityIdentifier("feedback.editor")
            HStack {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.badRed)
                        .accessibilityIdentifier("feedback.error")
                }
                Spacer()
                Text("\(viewModel.message.count)/\(FeedbackViewModel.messageLimit)")
                    .font(.system(size: 13))
                    .foregroundStyle(viewModel.isOverLimit ? Theme.badRed : Theme.secondaryText)
                    .accessibilityIdentifier("feedback.counter")
            }
            Button {
                Task { await viewModel.send() }
            } label: {
                Group {
                    if viewModel.phase == .sending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Theme.accentInteractive))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .opacity(viewModel.canSend ? 1 : 0.4)
            .accessibilityIdentifier("feedback.send")
            Spacer()
        }
        .padding(14)
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.perfectGreen)
            Text("Suggestion sent — thank you!")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .accessibilityIdentifier("feedback.success")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// UI-test mock runs get the hermetic feedback route; everyone else the
    /// real client (same seam pattern as elsewhere).
    @MainActor
    private static func makeSender() -> SuggestionSending {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return UITestFeedbackAPI(
                fails: ProcessInfo.processInfo.arguments.contains("UITEST_FEEDBACK_FAIL"))
        }
        #endif
        return FeedbackClient.shared
    }
}

#if DEBUG
#Preview("Send a suggestion") {
    FeedbackView(deviceId: "preview-device")
}
#endif
