//
//  AreYouOKApp.swift
//  AreYouOK
//
//  Created by deepsea on 2026/1/10.
//

import SwiftUI

@main
struct AreYouOKApp: App {
    @StateObject private var manager: AliveManager
    @AppStorage("appAppearance") var appAppearance: Int = 0

    init() {
        // Created here (not lazily) so check-ins from the watch work even when the app is launched in the background
        let manager = AliveManager()
        _manager = StateObject(wrappedValue: manager)
        WatchBridge.shared.start(manager: manager)
    }
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(manager)
                .preferredColorScheme(appAppearance == 0 ? nil : (appAppearance == 1 ? .light : .dark))
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        manager.updateStatus()
                    }
                }
        }
    }
}
