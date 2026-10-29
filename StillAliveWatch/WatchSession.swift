import Foundation
import WatchConnectivity

/// Talks to the iPhone app, which does the real check-in and server sync.
@MainActor
final class WatchSession: NSObject, ObservableObject {
    /// nil until the iPhone app has sent its state at least once
    @Published private(set) var dueDate: Date?
    @Published private(set) var hasContact = true
    @Published private(set) var isSending = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Returns false when the iPhone can't be reached.
    func checkIn() async -> Bool {
        isSending = true
        defer { isSending = false }
        guard let reply = await send(["action": "checkIn"]) else { return false }
        apply(reply)
        return true
    }

    func refresh() async {
        if let reply = await send(["action": "state"]) {
            apply(reply)
        }
    }

    private func send(_ message: [String: Any]) async -> [String: Any]? {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return nil }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                message,
                replyHandler: { continuation.resume(returning: $0) },
                errorHandler: { _ in continuation.resume(returning: nil) }
            )
        }
    }

    private func apply(_ state: [String: Any]) {
        if let due = state["dueDate"] as? Double {
            dueDate = Date(timeIntervalSince1970: due)
        }
        if let contact = state["hasContact"] as? Bool {
            hasContact = contact
        }
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.apply(context)
            await self.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}
