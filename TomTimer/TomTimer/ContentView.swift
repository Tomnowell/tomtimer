//
//  ContentView.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/13.
//

import SwiftUI
import SwiftData
import UserNotifications
import WatchConnectivity

struct ContentView: View {
    @AppStorage("timerDuration") private var timerDuration = 1500
    @State private var showSettings = false  // Controls the settings modal
    @State private var timeRemaining = 1500
    @State private var timerActive: Bool = false
    @State private var timer: Timer?
    
    @Environment(\.modelContext) private var context
    var body: some View {
        NavigationView {
            ZStack{
                VStack(spacing: 40) {

                    Spacer()
                    // Timer display text
                    Text(formatTime(timeRemaining)).font(.system(size: 96))
                    
                    // Primary Start Button
                    Button(action: startTimer) {
                        Text(timerActive ? "Running..." : "Start")
                            .frame(width: 220, height: 50)
                            .background(timerActive ? Color.gray : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(timerActive) // Disable while running
                    
                    // Secondary Controls
                    HStack(spacing: 20) {
                        Button("Pause") {
                            pauseTimer()
                        }
                        .frame(width: 100, height: 44)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .disabled(!timerActive) // Only enable when running
                        
                        Button("Reset") {
                            resetTimer()
                        }
                        .frame(width: 100, height: 44)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    HStack {
                        Spacer()
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                                .padding()
                                .background(Color.clear)
                        }
                    }
                }
            }
            .padding()
            .onAppear {
                timeRemaining = timerDuration
                WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)

                // 🔹 Listen for updates from the watch
                NotificationCenter.default.addObserver(forName: .timerUpdated, object: nil, queue: .main) { notification in
                    if let newTime = notification.object as? Int {
                        timeRemaining = newTime
                    }
                }
            }
        }
            
}

    // Helper to format seconds into mm:ss
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    func startTimer() {
        timerActive.toggle()
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining) // 🔹 Send to watch

        if timerActive {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                    WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining) // 🔹 Update watch in real-time
                } else {
                    timerExpired()
                }
            }
        } else {
            timer?.invalidate()
        }
    }
    
    func timerExpired() {
        timer?.invalidate()
        timerActive = false
        notifyTimerFinished()
        WatchConnectivityManager.shared.sendTimerUpdate(0)  // Notify watch of expiration
        saveCompletedSession()
        
    }
    
    private func pauseTimer() {
        timer?.invalidate()
        timerActive.toggle()
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining) // 🔹 Send to watch
    }
    
    private func resetTimer() {
        timer?.invalidate()
        timerActive = false
        timeRemaining = timerDuration
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)  // Reset on watch
    }
    
    func notifyTimerFinished() {
        let content = UNMutableNotificationContent()
        content.title = "🍅 Pomodoro Finished!"
        content.body = "Nice job! Time for a short break."
        content.sound = UNNotificationSound.default

        // Immediate notification
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification scheduling error: \(error.localizedDescription)")
            } else {
                print("Notification scheduled successfully")
            }
        }
    }
    
    func saveCompletedSession() {
        let session = TomTimerSession(duration: 1500)
        context.insert(session)
        
        let newCount = TimerSyncManager.shared.getCompletedSessions() + 1
        TimerSyncManager.shared.saveCompletedSessions(newCount)

        do {
            try context.save()
            print("Session saved and synced!")
        } catch {
            print("Error saving session: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}

