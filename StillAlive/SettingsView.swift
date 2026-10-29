import SwiftUI
import StoreKit

enum AppLinks {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6757640166")!
    static let reviewURL = appStoreURL.appending(queryItems: [
        URLQueryItem(name: "action", value: "write-review")
    ])
    static let privacyPolicyURL = URL(string: "https://invsi.notion.site/Privacy-Policy-8d66f4dc92754ad0a43399e905493095")!
    static let termsOfUseURL = URL(string: "https://invsi.notion.site/Terms-of-Use-40314ef1b43c444183b30a938602cb9d")!
    static let xiaohongshuURL = URL(string: "https://www.xiaohongshu.com/user/profile/5777e1583460946ad6894dc4")!
    static let xURL = URL(string: "https://x.com/invisilab_x")!
    static let feedbackEmail = "invisilab@gmail.com"
}

private let settingsOptionTextColor = Color.primary.opacity(0.5)

struct SettingsView: View {
    @ObservedObject var manager: AliveManager
    @AppStorage("appAppearance") var appAppearance: Int = 0 // 0: Auto, 1: Light, 2: Dark
    @AppStorage("hapticsEnabled") var hapticsEnabled = true
    @Environment(\.colorScheme) private var colorScheme

    var intervals: [Int] {
        #if DEBUG
        return [-1, -2, 12, 16, 24, 48, 72]
        #else
        return [12, 16, 24, 48, 72]
        #endif
    }

    private var currentLanguageName: String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.current.localizedString(forIdentifier: language) ?? language
    }

    private func intervalTitle(_ hour: Int) -> String {
        switch hour {
        case -1: return NSLocalizedString("Test_10s", comment: "")
        case -2: return NSLocalizedString("Test_1h", comment: "")
        default: return String(format: NSLocalizedString("X_Hours", comment: ""), hour)
        }
    }

    private var appearanceTitle: String {
        switch appAppearance {
        case 1: return NSLocalizedString("Light", comment: "")
        case 2: return NSLocalizedString("Dark", comment: "")
        default: return NSLocalizedString("System", comment: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Check-In Configuration") {
                    Group {
                        SettingsPicker(selection: $manager.checkInIntervalHours,
                                       value: intervalTitle(manager.checkInIntervalHours)) {
                            ForEach(intervals, id: \.self) { hour in
                                Text(verbatim: intervalTitle(hour)).tag(hour)
                            }
                        } label: {
                            Label {
                                Text("Timeout Duration")
                            } icon: {
                                Image(systemName: "timer").foregroundStyle(.primary)
                            }
                            .foregroundStyle(.primary)
                        }
                        .onChange(of: manager.checkInIntervalHours) {
                            manager.updateStatus() // Update logic immediately on change
                        }
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }

                Section("Notifications") {
                    Group {
                        Toggle(isOn: $manager.dailyReminderEnabled) {
                            Label {
                                Text("Daily Reminder")
                            } icon: {
                                Image(systemName: "bell.badge").foregroundStyle(.primary)
                            }
                            .foregroundStyle(.primary)
                        }
                        .tint(.blue)

                        if manager.dailyReminderEnabled {
                            DatePicker(selection: Binding(
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
                            ), displayedComponents: .hourAndMinute) {
                                Label {
                                    Text("Reminder Time")
                                } icon: {
                                    Image(systemName: "clock").foregroundStyle(.primary)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }

                Section("Display") {
                    Group {
                        SettingsPicker(selection: $appAppearance, value: appearanceTitle) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        } label: {
                            Label("Appearance", systemImage: "circle.lefthalf.filled")
                                .foregroundStyle(.primary)
                        }

                        Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                            HStack {
                                Label {
                                    Text("Language")
                                } icon: {
                                    Image(systemName: "globe").foregroundStyle(.primary)
                                }
                                .foregroundStyle(.primary)
                                Spacer()
                                Text(currentLanguageName)
                                    .foregroundStyle(settingsOptionTextColor)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tint(.primary)
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }

                Section("General") {
                    Group {
                        Toggle(isOn: $hapticsEnabled) {
                            Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                                .foregroundStyle(.primary)
                        }
                        .tint(.blue)

                        ShareLink(item: AppLinks.appStoreURL, subject: Text("App_Title")) {
                            HStack {
                                Label("Share with Friends", systemImage: "square.and.arrow.up")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tint(.primary)

                        Link(destination: AppLinks.reviewURL) {
                            HStack {
                                Label("Rate Us", systemImage: "star")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tint(.primary)

                        NavigationLink {
                            AboutView()
                        } label: {
                            Label {
                                Text("About_Title")
                            } icon: {
                                Image(systemName: "info.circle").foregroundStyle(.primary)
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }

                Section {
                    Group {
                        recommendedApps
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }
            }
            .environment(\.defaultMinListRowHeight, 60)
            .listSectionSpacing(32)
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(
                colorScheme == .light
                    ? Color(white: 0.97)
                    : Color(uiColor: .systemGroupedBackground)
            )
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(appAppearance == 0 ? nil : (appAppearance == 1 ? .light : .dark))
    }

    private var recommendedApps: some View {
        VStack(spacing: 12) {
            Text("More Apps")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    recommendedApp(icon: "RecommendedNexPaste", name: "NexPaste", detail: "OTHERAPPINFO_NexPaste", appID: "6761368515")
                    recommendedApp(icon: "RecommendedPixie", name: "OTHERAPP_Pixie", detail: "OTHERAPPINFO_Pixie", appID: "6446266063")
                    recommendedApp(icon: "RecommendedKiddo", name: "OTHERAPP_Kiddo", detail: "OTHERAPPINFO_Kiddo", appID: "6451401303")
                    recommendedApp(icon: "RecommendedInvsi", name: "invsi", detail: "OTHERAPPINFO_Invsi", appID: "6444667120")
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func recommendedApp(icon: String, name: LocalizedStringKey, detail: LocalizedStringKey, appID: String) -> some View {
        Link(destination: URL(string: "https://apps.apple.com/app/id\(appID)")!) {
            HStack(spacing: 8) {
                Image(icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(width: 220, alignment: .leading)
            .frame(minHeight: 68)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPicker<Selection: Hashable, Options: View, RowLabel: View>: View {
    @Binding var selection: Selection
    let value: String
    let options: Options
    let rowLabel: RowLabel

    init(selection: Binding<Selection>, value: String,
         @ViewBuilder content: () -> Options, @ViewBuilder label: () -> RowLabel) {
        _selection = selection
        self.value = value
        options = content()
        rowLabel = label()
    }

    var body: some View {
        HStack {
            rowLabel
            Spacer()
            Menu {
                Picker(selection: $selection) {
                    options
                } label: {
                    rowLabel
                }
                .pickerStyle(.inline)
            } label: {
                HStack {
                    Text(verbatim: value).foregroundStyle(settingsOptionTextColor)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .menuStyle(.borderlessButton)
            .tint(settingsOptionTextColor)
            .fixedSize()
        }
    }
}

private struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var storefrontAllowsX = false

    private var version: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        #if DEBUG
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (Build \(build))"
        #else
        return version
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Group {
                        VStack(spacing: 12) {
                            Image("AboutIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 30))
                                .accessibilityHidden(true)
                            Text("App_Title").font(.title2.bold())
                            Text("About_Description")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }
                .listRowBackground(Color.clear)

                Section("Contact the Developer") {
                    Group {
                        aboutLink("Feedback", detail: AppLinks.feedbackEmail, url: feedbackURL)
                        aboutLink("Xiaohongshu", url: AppLinks.xiaohongshuURL)
                        if storefrontAllowsX {
                            aboutLink("X", url: AppLinks.xURL)
                        }
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }

                Section("Terms and Privacy") {
                    Group {
                        aboutLink("Privacy Policy", url: AppLinks.privacyPolicyURL)
                        aboutLink("Terms of Use", url: AppLinks.termsOfUseURL)
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }

                Section {
                    Group {
                        Text("\(NSLocalizedString("Version", comment: "")): \(version)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listRowSeparatorTint(.primary.opacity(0.05))
                }
            }
            .environment(\.defaultMinListRowHeight, 60)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(
            colorScheme == .light
                ? Color(white: 0.97)
                : Color(uiColor: .systemGroupedBackground)
        )
        .navigationTitle("About_Title")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
        .task {
            #if DEBUG
            storefrontAllowsX = true
            #else
            if let storefront = await Storefront.current {
                storefrontAllowsX = storefront.countryCode != "CHN"
            }
            #endif
        }
    }

    private func aboutLink(_ title: LocalizedStringKey, detail: String? = nil, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                Spacer()
                if let detail {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.automatic)
    }

    private var feedbackURL: URL {
        var deviceInfo = utsname()
        uname(&deviceInfo)
        let machineCapacity = MemoryLayout.size(ofValue: deviceInfo.machine)
        let device = withUnsafePointer(to: &deviceInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: machineCapacity) {
                String(cString: $0)
            }
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let body = """



        ---------------------------------------
        App Version: \(info["CFBundleShortVersionString"] as? String ?? "—")
        App Build: \(info["CFBundleVersion"] as? String ?? "—")
        Country: \(Locale.current.identifier)
        Device: \(UIDevice.current.model) (\(device))
        ID: \(DeviceIdentity.deviceId)
        Language: \(Bundle.main.preferredLocalizations.first ?? "en")
        OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppLinks.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Are You OK - \(NSLocalizedString("Feedback", comment: ""))"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url!
    }
}

#Preview {
    SettingsView(manager: AliveManager())
}
