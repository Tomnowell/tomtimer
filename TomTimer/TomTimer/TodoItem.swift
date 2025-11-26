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
    var createdAt: Date

    init(title: String, estimatedMinutes: Int, isActive: Bool = false, createdAt: Date = Date()) {
        self.title = title
        self.estimatedMinutes = max(0, estimatedMinutes)
        self.remainingMinutes = max(0, estimatedMinutes)
        self.isActive = isActive
        self.createdAt = createdAt
    }

    func applyCompletion(minutes: Int) {
        let delta = max(0, minutes)
        remainingMinutes = max(0, remainingMinutes - delta)
    }

    func updateEstimates(estimated: Int, remaining: Int) {
        let newEstimated = max(0, estimated)
        estimatedMinutes = newEstimated
        remainingMinutes = min(max(0, remaining), newEstimated)
    }
}
