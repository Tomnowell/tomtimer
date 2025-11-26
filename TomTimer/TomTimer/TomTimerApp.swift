//
//  TomTimerApp.swift
//  TomTimer
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

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct TomTimerApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
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
            print("ModelContainer creation failed: \(error)")
            print("Attempting to delete old store and recreate...")
            
            // Delete old stores
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeURL = appSupport.appendingPathComponent("default.store")
                try? FileManager.default.removeItem(at: storeURL)
                
                let storeURLShm = appSupport.appendingPathComponent("default.store-shm")
                try? FileManager.default.removeItem(at: storeURLShm)
                
                let storeURLWal = appSupport.appendingPathComponent("default.store-wal")
                try? FileManager.default.removeItem(at: storeURLWal)
                
                print("Deleted old store files")
            }
            
            // Try creating with in-memory fallback
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                print("Still failed, using in-memory container: \(error)")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: memoryConfig)
                } catch {
                    fatalError("Cannot create ModelContainer even in-memory: \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
