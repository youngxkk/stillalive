import SwiftUI

enum AppTab: Hashable {
    case home
    case outing
    case contact
    case settings
}

struct MainTabView: View {
    @EnvironmentObject var manager: AliveManager
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Tab_Home", systemImage: "heart.fill", value: .home) {
                HomeView(onShowOuting: { selectedTab = .outing })
            }

            Tab("Tab_Outing", systemImage: "figure.walk", value: .outing) {
                OutingView(manager: manager)
            }

            Tab("Tab_Contact", systemImage: "person.crop.circle", value: .contact) {
                ContactView(manager: manager)
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView(manager: manager)
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AliveManager())
}
