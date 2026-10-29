import SwiftUI
import UserNotifications

@MainActor
class AliveManager: ObservableObject {
    // MARK: - Persistent Storage
    @AppStorage("lastCheckInTime") private var lastCheckInTimeTimestamp: Double = Date().timeIntervalSince1970
    
    @AppStorage("checkInIntervalHours") var checkInIntervalHours: Int = 24 {
        didSet {
            checkIn()
        }
    }
    
    @AppStorage("contactEmail") var contactEmail: String = ""
    @AppStorage("emailSubject") var emailSubject: String = ""
    @AppStorage("emailBody") var emailBody: String = ""
    
    @AppStorage("isMonitoringEnabled") var isMonitoringEnabled: Bool = true
    @AppStorage("lastTestEmailSentTime") private var lastTestEmailSentTimeInterval: Double = 0
    
    @AppStorage("dailyReminderEnabled") var dailyReminderEnabled: Bool = false {
        didSet {
            scheduleNotifications()
        }
    }
    
    @AppStorage("dailyReminderTime") var dailyReminderTime: Double = 32400 // Default to 9:00 AM (9 * 3600)
    {
        didSet {
            scheduleNotifications()
        }
    }

    // Outing guard: 0 means no active outing
    @AppStorage("outingDeadline") private var outingDeadlineTimestamp: Double = 0
    @AppStorage("outingNote") var outingNote: String = ""

    // MARK: - Published State
    @Published var timeRemaining: TimeInterval = 0
    @Published var outingTimeRemaining: TimeInterval = 0
    @Published var status: AliveStatus = .safe
    @Published var syncStatus: SyncStatus = .idle

    enum SyncStatus {
        case idle
        case syncing
        case success
        case allClearSent
        case failed
        case noEmail
    }

    enum OutingResult {
        case success
        case allClearSent
        case noEmail
        case failed
    }

    var outingDeadline: Date? {
        outingDeadlineTimestamp > 0 ? Date(timeIntervalSince1970: outingDeadlineTimestamp) : nil
    }

    var isOutingActive: Bool {
        outingDeadline != nil
    }
    
    var lastCheckInDate: Date {
        Date(timeIntervalSince1970: lastCheckInTimeTimestamp)
    }
    
    var dueDate: Date {
        if checkInIntervalHours == -1 {
            return lastCheckInDate.addingTimeInterval(10)
        } else if checkInIntervalHours == -2 {
            return lastCheckInDate.addingTimeInterval(3600)
        }
        return lastCheckInDate.addingTimeInterval(TimeInterval(checkInIntervalHours * 3600))
    }
    
    enum AliveStatus {
        case safe
        case warning // e.g. last hour
        case danger // expired
    }
    
    private var timer: Timer?
    
    init() {
        // Request notification permissions on launch
        requestNotificationPermission()
        updateStatus()
        startTimer()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private let backendBaseURL = URL(string: "https://api.maxc.cc")!

    func checkIn() {
        lastCheckInTimeTimestamp = Date().timeIntervalSince1970
        // The server ends an outing whose expected return time has passed on check-in
        if let deadline = outingDeadline, deadline <= Date() {
            clearOuting()
        }
        updateStatus()
        scheduleNotifications()
        WatchBridge.shared.sendState()
        
        // Sync with backend server
        Task {
            await syncWithServer()
        }
    }
    
    private func syncWithServer() async {
        guard !contactEmail.isEmpty else {
            print("Server Sync Skipped: No contact email set")
            self.syncStatus = .noEmail
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.syncStatus == .noEmail { self.syncStatus = .idle }
            return
        }
        
        self.syncStatus = .syncing

        let (statusCode, json) = await request(path: "checkin", payload: configPayload())

        if statusCode == 200 {
            print("Server Sync Success")
            let finalStatus: SyncStatus = (json?["allClearSent"] as? Bool == true) ? .allClearSent : .success
            self.syncStatus = finalStatus
            // Reset to idle after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.syncStatus == finalStatus { self.syncStatus = .idle }
        } else {
            print("Server Sync Failed: Status code \(statusCode ?? 0)")
            self.syncStatus = .failed
        }
    }

    /// Push contact/message changes to the server without resetting the timer.
    /// Clearing the contact email stops server-side monitoring entirely.
    func syncContactSettings() async {
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        WatchBridge.shared.sendState()

        if trimmedEmail.isEmpty {
            let statusCode = await post(path: "deregister", payload: credentials())
            print("Server Deregister: Status code \(statusCode ?? 0)")
            return
        }

        let statusCode = await post(path: "update", payload: configPayload())
        if statusCode == 404 {
            // Never checked in from this device yet: register now
            await syncWithServer()
        } else {
            print("Server Update: Status code \(statusCode ?? 0)")
        }
    }

    private func credentials() -> [String: Any] {
        [
            "deviceId": DeviceIdentity.deviceId,
            "deviceSecret": DeviceIdentity.deviceSecret
        ]
    }

    private func configPayload() -> [String: Any] {
        // Use localized defaults if empty
        let finalSubject = emailSubject.isEmpty ? NSLocalizedString("Default_Email_Subject", comment: "") : emailSubject
        let finalBody = emailBody.isEmpty ? NSLocalizedString("Default_Email_Body", comment: "") : emailBody

        let normalizedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Calculate actual interval in hours (the server enforces a 1 hour minimum)
        let interval: Double
        if checkInIntervalHours == -1 {
            interval = 10.0 / 3600.0 // 10 seconds for testing
        } else if checkInIntervalHours == -2 {
            interval = 1.0 // 1 hour for testing
        } else {
            interval = Double(checkInIntervalHours)
        }

        return credentials().merging([
            "email": normalizedEmail,
            "intervalHours": interval,
            "subject": finalSubject,
            "body": finalBody,
            // Sent to the contact if this check-in follows an alert
            "allClearSubject": NSLocalizedString("All_Clear_Email_Subject", comment: ""),
            "allClearBody": NSLocalizedString("All_Clear_Email_Body", comment: "")
        ]) { _, new in new }
    }

    // MARK: - Outing Guard

    /// Starts an outing guard: the contact is alerted if it isn't ended within `minutes`.
    /// Starting an outing also counts as a check-in.
    func startOuting(minutes: Int, note: String) async -> OutingResult {
        guard !contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noEmail }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let payload = configPayload().merging([
            "outingMinutes": minutes,
            "outingSubject": NSLocalizedString("Outing_Email_Subject", comment: ""),
            "outingBody": outingEmailBody(note: trimmedNote, deadline: deadline)
        ]) { _, new in new }

        let (statusCode, json) = await request(path: "outing/start", payload: payload)
        guard statusCode == 200 else { return .failed }

        let serverDeadline = (json?["deadline"] as? Double).map { $0 / 1000 }
        outingDeadlineTimestamp = serverDeadline ?? deadline.timeIntervalSince1970
        outingNote = trimmedNote
        lastCheckInTimeTimestamp = Date().timeIntervalSince1970
        updateStatus()
        scheduleNotifications()
        WatchBridge.shared.sendState()
        return (json?["allClearSent"] as? Bool == true) ? .allClearSent : .success
    }

    /// Pushes the expected return time back by `minutes`, keeping the same note.
    func extendOuting(by minutes: Int) async -> OutingResult {
        let remainingMinutes = max(0, Int(ceil(outingTimeRemaining / 60)))
        return await startOuting(minutes: remainingMinutes + minutes, note: outingNote)
    }

    /// Ends the outing guard ("I'm back safe"). Also counts as a check-in.
    func endOuting() async -> OutingResult {
        guard !contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Without a contact the server never knew about this outing
            clearOuting()
            return .success
        }

        let (statusCode, json) = await request(path: "outing/end", payload: configPayload())
        guard statusCode == 200 else { return .failed }

        clearOuting()
        lastCheckInTimeTimestamp = Date().timeIntervalSince1970
        updateStatus()
        scheduleNotifications()
        WatchBridge.shared.sendState()
        return (json?["allClearSent"] as? Bool == true) ? .allClearSent : .success
    }

    private func clearOuting() {
        outingDeadlineTimestamp = 0
        outingNote = ""
        outingTimeRemaining = 0
    }

    private func outingEmailBody(note: String, deadline: Date) -> String {
        let baseBody = emailBody.isEmpty ? NSLocalizedString("Default_Email_Body", comment: "") : emailBody
        let noteText = note.isEmpty ? NSLocalizedString("Outing_Email_No_Note", comment: "") : note
        let details = String(
            format: NSLocalizedString("Outing_Email_Details", comment: ""),
            noteText,
            deadline.formatted(date: .abbreviated, time: .shortened),
            TimeZone.current.identifier
        )
        return details + "\n\n" + baseBody
    }

    /// POSTs JSON to the backend and returns the HTTP status code, or nil on network failure.
    private func post(path: String, payload: [String: Any]) async -> Int? {
        await request(path: path, payload: payload).statusCode
    }

    /// POSTs JSON to the backend and returns the status code and decoded JSON response body.
    private func request(path: String, payload: [String: Any]) async -> (statusCode: Int?, json: [String: Any]?) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: backendBaseURL.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: request)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return ((response as? HTTPURLResponse)?.statusCode, json)
        } catch {
            print("Server Request Error (\(path)): \(error.localizedDescription)")
            return (nil, nil)
        }
    }
    
    private func startTimer() {
        // Update every second for real-time countdown display
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    func updateStatus() {
        let now = Date()
        let diff = dueDate.timeIntervalSince(now)
        timeRemaining = diff
        outingTimeRemaining = outingDeadline.map { $0.timeIntervalSince(now) } ?? 0

        if diff > 3600 {
            status = .safe
        } else if diff > 600 {
            status = .warning
        } else {
            status = .danger
        }
    }
    
    func sendTestEmailToServer() async {
        guard !contactEmail.isEmpty else {
            self.syncStatus = .noEmail
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.syncStatus == .noEmail { self.syncStatus = .idle }
            return
        }
        
        let now = Date().timeIntervalSince1970
        let twentyFourHours: Double = 24 * 3600
        
        #if !DEBUG
        if now - lastTestEmailSentTimeInterval < twentyFourHours {
            print("Test Email Skipped: Limit reached")
            return
        }
        #endif
        
        self.syncStatus = .syncing
        
        let finalSubject = emailSubject.isEmpty ? NSLocalizedString("Default_Email_Subject", comment: "") : "[TEST] \(emailSubject)"
        let finalBody = emailBody.isEmpty ? NSLocalizedString("Default_Email_Body", comment: "") : "[This is a test message from Are You OK]\n\n" + emailBody
        
        let normalizedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let payload = credentials().merging([
            "email": normalizedEmail,
            "subject": finalSubject,
            "body": finalBody
        ]) { _, new in new }

        let statusCode = await post(path: "test", payload: payload)

        if statusCode == 200 {
            lastTestEmailSentTimeInterval = now
            self.syncStatus = .success
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.syncStatus == .success { self.syncStatus = .idle }
        } else {
            if statusCode == 429 {
                // Server-side daily limit hit; keep the local limit in step
                lastTestEmailSentTimeInterval = now
            }
            self.syncStatus = .failed
        }
    }
    
    var timeUntilNextTestAllowed: TimeInterval {
        let nextAllowed = lastTestEmailSentTimeInterval + (24 * 3600)
        return max(0, nextAllowed - Date().timeIntervalSince1970)
    }
    
    func canSendTestEmail() -> Bool {
        #if DEBUG
        return true
        #else
        return timeUntilNextTestAllowed <= 0
        #endif
    }
    
    // MARK: - Notifications
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            if success {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        guard isMonitoringEnabled else { return }
        
        // 1. Warning Notification (1 hour before expiration)
        let warningDate = dueDate.addingTimeInterval(-3600)
        if warningDate > Date() {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Notification_Title_Warning", comment: "Warning Title")
            content.body = NSLocalizedString("Notification_Body_Warning", comment: "Warning Body")
            content.sound = .default
            
            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: warningDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            
            let request = UNNotificationRequest(identifier: "warning-notification", content: content, trigger: trigger)
            center.add(request)
        }
        
        // 2. Expiration Notification
        if dueDate > Date() {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Notification_Title_Expired", comment: "Expired Title")
            content.body = NSLocalizedString("Notification_Body_Expired", comment: "Expired Body")
            content.sound = .defaultCritical
            
            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dueDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            
            let request = UNNotificationRequest(identifier: "expired-notification", content: content, trigger: trigger)
            center.add(request)
        }
        
        // 3. Outing Guard Notifications (15 minutes before and at the expected return time)
        if let outingDeadline {
            let outingWarningDate = outingDeadline.addingTimeInterval(-15 * 60)
            if outingWarningDate > Date() {
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("Notification_Title_Outing_Warning", comment: "Outing Warning Title")
                content.body = NSLocalizedString("Notification_Body_Outing_Warning", comment: "Outing Warning Body")
                content.sound = .default

                let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: outingWarningDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
                center.add(UNNotificationRequest(identifier: "outing-warning-notification", content: content, trigger: trigger))
            }

            if outingDeadline > Date() {
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("Notification_Title_Outing_Expired", comment: "Outing Expired Title")
                content.body = NSLocalizedString("Notification_Body_Outing_Expired", comment: "Outing Expired Body")
                content.sound = .defaultCritical

                let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: outingDeadline)
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
                center.add(UNNotificationRequest(identifier: "outing-expired-notification", content: content, trigger: trigger))
            }
        }

        // 4. Daily Reminder Notification
        if dailyReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Notification_Title_Reminder", comment: "Daily Reminder Title")
            content.body = NSLocalizedString("Notification_Body_Reminder", comment: "Daily Reminder Body")
            content.sound = .default
            
            let totalSeconds = Int(dailyReminderTime)
            let hour = totalSeconds / 3600
            let minute = (totalSeconds % 3600) / 60
            
            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "daily-reminder-notification", content: content, trigger: trigger)
            center.add(request)
        }
    }
}
