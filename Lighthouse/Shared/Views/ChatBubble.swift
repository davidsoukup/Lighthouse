import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    /// Chooses bubble type by message payload (text, generic card, timer, stopwatch).
    var body: some View {
        switch message.content {
        case .text(let text):
            textBubble(text)
        case .view(let v):
            cardBubble { v }
        case .timer(let model):
            cardBubble { MicroApps.CountdownTimerCard(model: model) }
        case .stopwatch(let model):
            cardBubble { MicroApps.StopwatchCard(model: model) }
        }
    }

    /// Standard text bubble layout for user/system plain messages.
    @ViewBuilder
    private func textBubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 80) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 3) {
                Text(text)
                    .font(message.isUser
                          ? .system(size: 14)
                          : .system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(message.isUser
                                ? Color.blue
                                : Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                timestamp
            }
            if !message.isUser { Spacer(minLength: 80) }
        }
    }

    /// Shared wrapper for card-like message content.
    @ViewBuilder
    private func cardBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            timestamp.padding(.horizontal, 4)
        }
    }

    private var timestamp: some View {
        Text(message.date, style: .time)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}
