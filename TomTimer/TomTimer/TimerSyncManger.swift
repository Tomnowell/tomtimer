//
//  TimerSyncManager.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/18.
//  Copyright © 2025 I. All rights reserved.
//
import Foundation

class TimerSyncManager {
    static let shared = TimerSyncManager()
    private let store = NSUbiquitousKeyValueStore.default

    func saveCompletedSessions(_ count: Int) {
        store.set(count, forKey: "completedSessions")
        store.synchronize()
    }

    func getCompletedSessions() -> Int {
        return store.object(forKey: "completedSessions") as? Int ?? 0
    }
}

