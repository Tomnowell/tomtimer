//
//  WristApp.swift
//  Wrist Watch App
//
//  Created by Tom on 2025/03/18.
//  Copyright © 2025 I. All rights reserved.
//

import SwiftUI

@main
struct TomTimerWatchApp: App {
    
    init() {
            WatchConnectivityManager.shared.setupSession()
        }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
