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

    // MARK: - Published State
    @Published var timeRemaining: TimeInterval = 0
    @Published var status: AliveStatus = .safe
    @Published var syncStatus: SyncStatus = .idle
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case failed
        case noEmail
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
    
    private let backendURL = URL(string: "https://api.maxc.cc/checkin")!

    func checkIn() {
        lastCheckInTimeTimestamp = Date().timeIntervalSince1970
        updateStatus()
        scheduleNotifications()
        
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
        
        // Use localized defaults if empty
        let finalSubject = emailSubject.isEmpty ? NSLocalizedString("Default_Email_Subject", comment: "") : emailSubject
        let finalBody = emailBody.isEmpty ? NSLocalizedString("Default_Email_Body", comment: "") : emailBody
        
        self.syncStatus = .syncing
        
        let normalizedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Calculate actual interval in hours
        let interval: Double
        if checkInIntervalHours == -1 {
            interval = 10.0 / 3600.0 // 10 seconds for testing
        } else if checkInIntervalHours == -2 {
            interval = 1.0 // 1 hour for testing
        } else {
            interval = Double(checkInIntervalHours)
        }
        
        let payload: [String: Any] = [
            "email": normalizedEmail,
            "intervalHours": interval,
            "subject": finalSubject,
            "body": finalBody
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: backendURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Server Sync Success")
                self.syncStatus = .success
                // Reset to idle after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if self.syncStatus == .success { self.syncStatus = .idle }
            } else {
                print("Server Sync Failed: Status code \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                self.syncStatus = .failed
            }
        } catch {
            print("Server Sync Error: \(error.localizedDescription)")
            self.syncStatus = .failed
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

        let payload: [String: Any] = [
            "email": normalizedEmail,
            "intervalHours": 0, // 0 can signify an immediate test on backend
            "subject": finalSubject,
            "body": finalBody,
            "isTest": true
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: backendURL)
            request.httpMethod = .init("POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                lastTestEmailSentTimeInterval = now
                self.syncStatus = .success
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if self.syncStatus == .success { self.syncStatus = .idle }
            } else {
                self.syncStatus = .failed
            }
        } catch {
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
        
        // 3. Daily Reminder Notification
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
