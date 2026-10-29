import Foundation
#if os(iOS)
import WatchConnectivity
#endif

/// Relays check-ins from the Apple Watch app and keeps the watch's countdown in sync.
/// The watch never talks to the server itself: the phone does the real check-in.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    private weak var manager: AliveManager?

    func start(manager: AliveManager) {
        self.manager = manager
        #if os(iOS)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #endif
    }

    /// Pushes the latest check-in state; the watch picks it up the next time it runs.
    func sendState() {
        #if os(iOS)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(currentState())
        #endif
    }

    private func currentState() -> [String: Any] {
        guard let manager else { return [:] }
        return [
            "dueDate": manager.dueDate.timeIntervalSince1970,
            "hasContact": !manager.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ]
    }
}

#if os(iOS)
extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another paired watch
        session.activate()
    }

    /// Messages from the watch: "checkIn" checks in; anything else just asks for the current state.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let action = message["action"] as? String
        Task { @MainActor in
            if action == "checkIn" {
                self.manager?.checkIn()
            }
            replyHandler(self.currentState())
        }
    }
}
#endif
