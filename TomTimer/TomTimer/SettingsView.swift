//
//  SettingsView.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/18.
//  Copyright © 2025 I. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("timerDuration") private var timerDuration = 1500  // Default 25 mins

    var body: some View {
        Form {
            Section(header: Text("Timer Settings")) {
                Stepper(value: $timerDuration, in: 300...3600, step: 60) {
                    Text("Pomodoro Duration: \(timerDuration / 60) min")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
