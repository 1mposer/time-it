import SwiftUI

/// Beta feedback sheet, one per kind (the ⓘ menu's "Send a suggestion" /
/// "What have you liked?" — owner rulings 2026-11-11): the owner's note,
/// the editor, Send. Medium detent; on iOS 26 the sheet keeps the system
/// Liquid Glass background and its close control is the glass ✕ — below
/// iOS 26 it is opaque with a Cancel button. A non-204 keeps the typed text
/// with Send as retry (never discarded); success briefly confirms, then
/// dismisses.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FeedbackViewModel

    /// The editor's height — about four lines at 15pt (the round-2 frames).
    static let editorHeight: CGFloat = 112

    @MainActor
    init(kind: FeedbackKind, deviceId: String) {
        _viewModel = StateObject(wrappedValue: FeedbackViewModel(kind: kind,
                                                                 sender: Self.makeSender(),
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
            .modifier(OpaqueBelowGlass())
            .navigationTitle(viewModel.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                        .disabled(viewModel.phase == .sending)
                        .accessibilityIdentifier("feedback.cancel")
                }
            }
        }
        .presentationDetents([.medium])
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

    /// iOS 26: the system glass ✕ (`Button(role: .close)`). Earlier: "Cancel".
    @ViewBuilder private var closeButton: some View {
        if #available(iOS 26, *) {
            Button(role: .close) { dismiss() }
        } else {
            Button("Cancel") { dismiss() }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FeedbackViewModel.note)
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("feedback.note")
            TextEditor(text: $viewModel.message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: Self.editorHeight)
                .background(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground)
                        if viewModel.message.isEmpty {
                            Text(viewModel.kind.placeholder)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityLabel(viewModel.kind.title)
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
                            .tint(Theme.onFill)
                    } else {
                        Text("Send")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.onFill)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Theme.accentBrandFill))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .opacity(viewModel.canSend ? 1 : 0.4)
            .accessibilityIdentifier("feedback.send")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accentBrand)
                .accessibilityHidden(true)
            Text("Thanks, sent.")
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

/// Below iOS 26 the sheet content draws the app background; on iOS 26 it
/// stays transparent so the system Liquid Glass sheet shows through — except
/// in dark, where every screen shares the app's ground (owner ruling 18a,
/// 2026-11-11).
private struct OpaqueBelowGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *), colorScheme != .dark {
            content
        } else {
            content.background(Theme.appBackground.ignoresSafeArea())
        }
    }
}

#if DEBUG
#Preview("Send a suggestion") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FeedbackView(kind: .suggestion, deviceId: "preview-device")
    }
}

#Preview("What have you liked? — dark") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FeedbackView(kind: .liked, deviceId: "preview-device")
    }
    .preferredColorScheme(.dark)
}
#endif
