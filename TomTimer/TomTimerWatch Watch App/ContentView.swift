//
//  ContentView.swift
//  Wrist Watch App
//
//  Created by Tom on 2025/03/18.
//  Copyright © 2025 I. All rights reserved.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @State private var timeRemaining = 1500
    @State private var timerActive = false
    @State private var timer: Timer?
    @State private var currentTaskTitle = "No Task Selected"

    var body: some View {
        VStack {
            Text(currentTaskTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
            
            Text(formatTime(timeRemaining)).font(.system(size: 40))
            
            HStack {
                Button(action: startTimer) {
                    Image(systemName: timerActive ? "pause.circle" : "play.circle")
                        .font(.system(size: 40))
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: resetTimer) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 40))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .onAppear {
            NotificationCenter.default.addObserver(forName: .timerUpdated, object: nil, queue: .main) { notification in
                if let newTime = notification.object as? Int {
                    timeRemaining = newTime
                }
            }
            NotificationCenter.default.addObserver(forName: .activeTaskUpdated, object: nil, queue: .main) { notification in
                if let title = notification.object as? String {
                    currentTaskTitle = title
                }
            }
            WatchConnectivityManager.shared.setupSession()
        }
    }
    func startTimer() {
        timerActive.toggle()
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining) // 🔹 Send to iPhone

        if timerActive {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                    WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining) // 🔹 Update iPhone in real-time
                } else {
                    timerExpired()
                }
            }
        } else {
            timer?.invalidate()
        }
    }

    func resetTimer() {
        timer?.invalidate()
        timeRemaining = 1500
        timerActive = false
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining) // 🔹 Send reset to iPhone
    }

    func timerExpired() {
        timer?.invalidate()
        timerActive = false
        WatchConnectivityManager.shared.sendTimerUpdate(0) // 🔹 Notify iPhone of completion
    }

    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

}

#Preview {
    ContentView()
}
