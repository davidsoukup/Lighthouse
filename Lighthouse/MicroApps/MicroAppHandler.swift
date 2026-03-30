import SwiftUI

final class MicroAppHandler {
    static let shared = MicroAppHandler()
    private init() {}

    /// Routes slash-prefixed user input to the Micro Apps runtime.
    func handle(_ input: String) async -> MessageContent {
        if input.hasPrefix("/") {
            let microAppInvocation = String(input.dropFirst())
            return await MicroApps.execute(microAppInvocation)
        } else {
            return .text(lh("microapp.ai_not_connected"))
        }
    }
}
