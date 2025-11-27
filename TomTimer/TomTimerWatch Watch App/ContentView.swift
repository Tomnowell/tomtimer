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
    @State private var showingCompleteAlert = false

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
        .alert("Pomodoro Complete! 🍅", isPresented: $showingCompleteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Great work! Time for a break.")
        }
        .onAppear {
            NotificationCenter.default.addObserver(forName: .timerUpdated, object: nil, queue: .main) { notification in
                if let newTime = notification.object as? Int {
                    timeRemaining = newTime
                }
            }
            NotificationCenter.default.addObserver(forName: .activeTaskUpdated, object: nil, queue: .main) { notification in
                if let title = notification.object as? String {
                    currentTaskTitle = title
                } else {
                    currentTaskTitle = "No Task Selected"
                }
            }
            NotificationCenter.default.addObserver(forName: .timerStatusUpdated, object: nil, queue: .main) { notification in
                guard let isRunning = notification.object as? Bool else { return }
                handleRemoteTimerStatusChange(isRunning)
            }
            WatchConnectivityManager.shared.setupSession()
        }
    }

    private func handleRemoteTimerStatusChange(_ isRunning: Bool) {
        if !isRunning {
            timer?.invalidate()
            timer = nil
        }
        timerActive = isRunning
    }

    func startTimer() {
        timerActive.toggle()
        WatchConnectivityManager.shared.sendTimerState(timeRemaining: timeRemaining, isRunning: timerActive)

        if timerActive {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                    WatchConnectivityManager.shared.sendTimerState(timeRemaining: timeRemaining, isRunning: true)
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
        WatchConnectivityManager.shared.sendTimerState(timeRemaining: timeRemaining, isRunning: false)
    }

    func timerExpired() {
        timer?.invalidate()
        timerActive = false
        
        // Trigger haptic feedback on watch
        WKInterfaceDevice.current().play(.notification)
        
        // Show alert
        showingCompleteAlert = true
        
        WatchConnectivityManager.shared.sendTimerState(timeRemaining: 0, isRunning: false)
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
