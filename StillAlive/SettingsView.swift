import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: AliveManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("appAppearance") var appAppearance: Int = 0 // 0: Auto, 1: Light, 2: Dark
    
    var intervals: [Int] {
        #if DEBUG
        return [-1, -2, 12, 16, 24, 48, 72]
        #else
        return [12, 16, 24, 48, 72]
        #endif
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Check-In Configuration")) {
                    Picker("Timeout Duration", selection: $manager.checkInIntervalHours) {
                        ForEach(intervals, id: \.self) { hour in
                            if hour == -1 {
                                Text("Test_10s").tag(hour)
                            } else if hour == -2 {
                                Text("Test_1h").tag(hour)
                            } else {
                                Text(String(format: NSLocalizedString("X_Hours", comment: ""), hour)).tag(hour)
                            }
                        }
                    }
                    .onChange(of: manager.checkInIntervalHours) {
                        manager.updateStatus() // Update logic immediately on change
                    }
                }
                
                Section(header: Text(NSLocalizedString("Notifications", comment: ""))) {
                    Toggle(NSLocalizedString("Daily Reminder", comment: ""), isOn: $manager.dailyReminderEnabled)
                    
                    if manager.dailyReminderEnabled {
                        DatePicker(NSLocalizedString("Reminder Time", comment: ""), selection: Binding(
                            get: {
                                let totalSeconds = Int(manager.dailyReminderTime)
                                let hour = totalSeconds / 3600
                                let minute = (totalSeconds % 3600) / 60
                                return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
                            },
                            set: { newDate in
                                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                manager.dailyReminderTime = Double((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60)
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                }
                
                Section(header: Text("Appearance")) {
                    Picker("Appearance", selection: $appAppearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                }
                
                Section(header: Text("Language")) {
                    Button(action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            if UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }) {
                        HStack {
                            Text("Language")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("System Default")
                                .foregroundColor(.gray)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section(header: Text("About Us")) {
                    Button(action: {
                        if let url = URL(string: "https://invsi.notion.site/Privacy-Policy-8d66f4dc92754ad0a43399e905493095") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Button(action: {
                        if let url = URL(string: "https://invsi.notion.site/Terms-of-Use-40314ef1b43c444183b30a938602cb9d") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("Terms of Use")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(appAppearance == 0 ? nil : (appAppearance == 1 ? .light : .dark))
    }
}

#Preview {
    SettingsView(manager: AliveManager())
}
