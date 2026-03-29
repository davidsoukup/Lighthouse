import Foundation
import SwiftUI
import Combine

enum MessageContent {
    case text(String)
    case view(AnyView)
    case timer(CountdownTimerModel)
    case stopwatch(StopwatchModel)

    var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

final class CountdownTimerModel: ObservableObject, Identifiable {
    let id = UUID()
    let duration: TimeInterval
    let label: String

    @Published var remaining: TimeInterval
    @Published var isRunning: Bool
    @Published var didNotify: Bool

    init(duration: TimeInterval, label: String) {
        let value = max(duration, 1)
        self.duration = value
        self.label = label
        self.remaining = value
        self.isRunning = true
        self.didNotify = false
    }
}

final class StopwatchModel: ObservableObject, Identifiable {
    let id = UUID()

    @Published var startDate: Date
    @Published var elapsed: TimeInterval
    @Published var isRunning: Bool

    init() {
        self.startDate = Date()
        self.elapsed = 0
        self.isRunning = true
    }
}

struct ChatMessage: Identifiable {
    let id   = UUID()
    let content: MessageContent
    let isUser:  Bool
    let date:    Date = Date()
}

final class HistoryStore {
    static let shared = HistoryStore()
    private init() {}

    private(set) var messages: [ChatMessage] = []

    func add(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > 60 { messages = Array(messages.suffix(60)) }
    }

    func clear() { messages = [] }
}
