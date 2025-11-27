//
//  TomTimerApp.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/13.
//

import SwiftUI
import SwiftData

@main
struct TomTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [TodoItem.self, TomTimerSession.self])
        }
    }
}
