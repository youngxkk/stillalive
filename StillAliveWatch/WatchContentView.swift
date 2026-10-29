import SwiftUI
import WatchKit

struct WatchContentView: View {
    @EnvironmentObject var session: WatchSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                status(now: context.date)
            }

            Button {
                Task { await checkIn() }
            } label: {
                Text("Watch_CheckIn_Button")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(session.isSending)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await session.refresh() }
            }
        }
    }

    @ViewBuilder
    private func status(now: Date) -> some View {
        if !session.hasContact {
            hint("Watch_No_Contact")
        } else if let dueDate = session.dueDate {
            let remaining = dueDate.timeIntervalSince(now)
            if remaining > 0 {
                VStack(spacing: 2) {
                    Text("Watch_Time_Left")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(Duration.seconds(remaining).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.title2.monospacedDigit().bold())
                        // Same thresholds as the iPhone app
                        .foregroundStyle(remaining > 3600 ? Color.green : (remaining > 600 ? Color.orange : Color.red))
                }
            } else {
                Text("Watch_Overdue")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        } else {
            hint("Watch_Open_Phone")
        }
    }

    private func hint(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func checkIn() async {
        let success = await session.checkIn()
        WKInterfaceDevice.current().play(success ? .success : .failure)
        message = success ? "Watch_Checked_In" : "Watch_Phone_Unreachable"

        try? await Task.sleep(for: .seconds(3))
        message = nil
    }
}
