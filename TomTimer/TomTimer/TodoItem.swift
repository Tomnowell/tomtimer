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
    
    // Generic remote ID for any provider (replaces reminderIdentifier over time)
    var remoteID: String? = nil
    var providerIdentifier: String? = nil

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

// MARK: - TaskProvider Integration

extension TodoItem {
    /// Convert to TaskProviderItem for sync with external providers
    func toProviderItem() -> TaskProviderItem {
        // Generate a stable UUID from the persistent model ID
        let uuidString = String(describing: self.persistentModelID)
        let uuid = UUID(uuidString: uuidString) ?? UUID()
        
        return TaskProviderItem(
            id: uuid,
            remoteID: self.remoteID ?? self.reminderIdentifier,
            title: self.title,
            estimatedMinutes: self.estimatedMinutes,
            remainingMinutes: self.remainingMinutes,
            isActive: self.isActive,
            isCompleted: self.remainingMinutes == 0,
            modifiedAt: self.modifiedAt
        )
    }
    
    /// Update this TodoItem from a TaskProviderItem
    func updateFrom(providerItem: TaskProviderItem) {
        self.title = providerItem.title
        self.estimatedMinutes = providerItem.estimatedMinutes
        self.remainingMinutes = providerItem.remainingMinutes
        self.isActive = providerItem.isActive
        self.modifiedAt = providerItem.modifiedAt
        self.remoteID = providerItem.remoteID
    }
    
    /// Create a new TodoItem from a TaskProviderItem
    static func from(providerItem: TaskProviderItem, providerID: String) -> TodoItem {
        let item = TodoItem(
            title: providerItem.title,
            estimatedMinutes: providerItem.estimatedMinutes,
            isActive: providerItem.isActive
        )
        item.remainingMinutes = providerItem.remainingMinutes
        item.modifiedAt = providerItem.modifiedAt
        item.remoteID = providerItem.remoteID
        item.providerIdentifier = providerID
        return item
    }
}
