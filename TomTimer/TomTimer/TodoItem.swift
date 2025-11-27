//  TodoItem.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/13.
//

import Foundation
import SwiftData

@Model
final class TodoItem {
    var title: String
    var estimatedMinutes: Int
    var remainingMinutes: Int
    var isActive: Bool
    var modifiedAt: Date
    var reminderIdentifier: String? = nil

    init(title: String, estimatedMinutes: Int, isActive: Bool = false, reminderIdentifier: String? = nil) {
        self.title = title
        self.estimatedMinutes = max(0, estimatedMinutes)
        self.remainingMinutes = max(0, estimatedMinutes)
        self.isActive = isActive
        self.modifiedAt = Date()
        self.reminderIdentifier = reminderIdentifier
    }

    func applyCompletion(minutes: Int) {
        let delta = max(0, minutes)
        remainingMinutes = max(0, remainingMinutes - delta)
        modifiedAt = Date()
    }

    func updateEstimates(estimated: Int, remaining: Int) {
        let newEstimated = max(0, estimated)
        estimatedMinutes = newEstimated
        remainingMinutes = min(max(0, remaining), newEstimated)
        modifiedAt = Date()
    }
}
