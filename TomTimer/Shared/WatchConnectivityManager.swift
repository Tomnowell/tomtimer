//
//  WatchConnectivityManager.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/18.
//  Copyright © 2025 I. All rights reserved.
//

#if canImport(WatchConnectivity)
import WatchConnectivity

class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    
    #if os(iOS)  // These methods are ONLY available on iOS
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive.")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()  // Re-activate session on iOS
    }
    #endif
    
    
    static let shared = WatchConnectivityManager()

    override private init() {
        super.init()
        setupSession()
    }

    func setupSession() {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendTimerUpdate(_ timeRemaining: Int) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["timeRemaining": timeRemaining], replyHandler: nil, errorHandler: { error in
                print("Error sending timer update: \(error.localizedDescription)")
            })
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let newTime = message["timeRemaining"] as? Int {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .timerUpdated, object: newTime)
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("WCSession activated successfully.")
        }
    }
    
}

extension Notification.Name {
    static let timerUpdated = Notification.Name("timerUpdated")
}
#endif
