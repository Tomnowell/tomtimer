//
//  PomodoroApp.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/13.
//
import SwiftUI
import SwiftData
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Allow notifications to display in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct TomTimerApp: App {
    
    // Corrected initializer
    init() {
        
        // Register app delegate for notification delegate
            @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { success, error in
            if success {
                print("Notifications allowed!")
            } else if let error = error {
                print("Error requesting notifications: \(error.localizedDescription)")
            }
        }
    }
    
    var sharedModelContainer: ModelContainer = {
            let schema = Schema([TomTimerSession.self, TodoItem.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            do {
                print("Creating ModelContainer")
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
