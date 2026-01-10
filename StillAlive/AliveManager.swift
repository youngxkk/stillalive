import SwiftUI
import UserNotifications

class AliveManager: ObservableObject {
    // MARK: - Persistent Storage
    @AppStorage("lastCheckInTime") private var lastCheckInTimeTimestamp: Double = Date().timeIntervalSince1970
    
    @AppStorage("checkInIntervalHours") var checkInIntervalHours: Int = 24
    
    @AppStorage("contactEmail") var contactEmail: String = ""
    @AppStorage("emailSubject") var emailSubject: String = "Emergency Alert: I haven't checked in"
    @AppStorage("emailBody") var emailBody: String = "I haven't checked in on my Still Alive app. Please contact me to ensure I am safe. \n\n(Default message: 我住在xxx，今天可能出事了，快来找我)"
    
    @AppStorage("isMonitoringEnabled") var isMonitoringEnabled: Bool = true

    // MARK: - Published State
    @Published var timeRemaining: TimeInterval = 0
    @Published var status: AliveStatus = .safe
    
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
    
    func checkIn() {
        lastCheckInTimeTimestamp = Date().timeIntervalSince1970
        updateStatus()
        scheduleNotifications()
        // Here calls to backend would happen
    }
    
    private func startTimer() {
        // Update every second for real-time countdown display
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }
    
    func updateStatus() {
        let now = Date()
        let diff = dueDate.timeIntervalSince(now)
        timeRemaining = diff
        
        if diff > 3600 {
            status = .safe
        } else if diff > 0 {
            status = .warning
        } else {
            status = .danger
        }
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
    }
}
