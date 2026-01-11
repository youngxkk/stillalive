//
//  AreYouOKApp.swift
//  AreYouOK
//
//  Created by deepsea on 2026/1/10.
//

import SwiftUI

@main
struct AreYouOKApp: App {
    @StateObject private var manager = AliveManager()
    @AppStorage("appAppearance") var appAppearance: Int = 0
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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
