import SwiftUI

/// Chat sheet for the AI dietitian. The assistant has access to the user's
/// recent meal history (sent server-side per request) and acts as a friendly
/// food coach.
///
/// Conversation is session-local — closing the sheet wipes the transcript.
/// This is intentional: feels like asking a quick question, not opening a
/// thread you have to maintain.
struct CoachChatView: View {
    @EnvironmentObject var history: ScanHistory
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    /// When true, shows a "Done" toolbar button that dismisses the view
    /// (used when presented as a sheet). When false (tab destination),
    /// dismissal is via the tab bar.
    var isModal: Bool = false

    @State private var transcript: [ChatMessage] = [
        ChatMessage(
            role: .assistant,
            text: "Hi! I'm your Nyam coach. I can see what you've been eating. Ask me anything — nutrition patterns, what to add to your day, or how a specific meal looked."
        )
    ]
    @State private var draft: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messages
                composer
            }
            .background(Color.NyamSurface.background.ignoresSafeArea())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(transcript) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if isSending {
                        TypingBubble()
                            .id("typing")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: transcript.count) { _, _ in
                if let last = transcript.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: isSending) { _, sending in
                if sending {
                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask your coach…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.NyamSurface.card)
                )
                .overlay(
                    Capsule()
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                )
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit(send)
                .disabled(isSending)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(canSend ? Color.NyamSage.shade5 : Color.NyamSage.shade5.opacity(0.35))
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            Color.NyamSurface.background
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color(.separator)), alignment: .top)
        )
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let userMsg = ChatMessage(role: .user, text: text)
        transcript.append(userMsg)
        draft = ""
        errorMessage = nil
        isSending = true

        Task {
            do {
                let reply = try await CoachAPI.sendMessage(
                    transcript: transcript,
                    historyEntries: history.entries,
                    identityToken: auth.identityToken
                )
                await MainActor.run {
                    transcript.append(ChatMessage(role: .assistant, text: reply))
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }
}

// MARK: - Bubbles

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                CoachAvatar()
            } else {
                Spacer(minLength: 36)
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .overlay(bubbleStroke)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Spacer(minLength: 0).frame(width: 0)
            } else {
                Spacer(minLength: 36)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.NyamSage.shade5)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.NyamSurface.card)
        }
    }

    @ViewBuilder
    private var bubbleStroke: some View {
        if message.role == .assistant {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
        }
    }
}

private struct TypingBubble: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CoachAvatar()
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.NyamSage.shade4)
                        .frame(width: 7, height: 7)
                        .opacity(opacityForDot(i))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.NyamSurface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
            )
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func opacityForDot(_ index: Int) -> Double {
        let offset = Double(index) * 0.25
        let v = sin((Double(phase) - offset) * .pi) * 0.5 + 0.5
        return 0.35 + 0.65 * v
    }
}

private struct CoachAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.NyamSage.shade5)
                .frame(width: 28, height: 28)
            Image(systemName: "fork.knife")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    CoachChatView()
        .environmentObject(ScanHistory())
        .environmentObject(AuthManager())
}
