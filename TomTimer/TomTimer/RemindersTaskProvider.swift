//
//  RemindersTaskProvider.swift
//  TomTimer
//
//  Created by AI Assistant on 2025/11/27.
//

import Foundation
import EventKit
import SwiftData

/// TaskProvider implementation for Apple Reminders
@MainActor
class RemindersTaskProvider: TaskProvider {
    let identifier = "com.tomtimer.provider.reminders"
    let displayName = "Apple Reminders"
    let icon = "checklist"
    let requiresAuthentication = true
    
    private let eventStore = EKEventStore()
    private let friendlyHeader = "TicketyPom Task"
    private let defaultEstimateMinutes = 25
    
    var selectedListIdentifier: String?
    var availableLists: [EKCalendar] = []
    
    var isAuthenticated: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return (status == .fullAccess || status == .writeOnly) && selectedListIdentifier != nil
    }
    
    var selectedList: EKCalendar? {
        guard let identifier = selectedListIdentifier else { return nil }
        return eventStore.calendar(withIdentifier: identifier)
    }
    
    // MARK: - TaskProvider Protocol
    
    func authenticate() async throws {
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else {
            throw TaskProviderError.authorizationDenied
        }
        await loadAvailableLists()
    }
    
    func fetchTasks() async throws -> [TaskProviderItem] {
        guard let list = selectedList else {
            throw TaskProviderError.notConfigured
        }
        
        let predicate = eventStore.predicateForReminders(in: [list])
        
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).compactMap { reminder -> TaskProviderItem? in
                    guard let metadata = self.decodeMetadata(from: reminder) else { return nil }
                    
                    return TaskProviderItem(
                        id: UUID(),
                        remoteID: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        estimatedMinutes: metadata.estimatedMinutes,
                        remainingMinutes: metadata.remainingMinutes,
                        isActive: metadata.isActive,
                        isCompleted: reminder.isCompleted,
                        modifiedAt: reminder.lastModifiedDate ?? Date()
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }
    
    func createTask(_ item: TaskProviderItem) async throws -> String {
        guard let list = selectedList else {
            throw TaskProviderError.notConfigured
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = item.title
        reminder.notes = encodeFriendlyMetadata(
            estimated: item.estimatedMinutes,
            remaining: item.remainingMinutes,
            isActive: item.isActive
        )
        
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
    
    func updateTask(_ item: TaskProviderItem) async throws {
        guard let remoteID = item.remoteID,
              let reminder = eventStore.calendarItem(withIdentifier: remoteID) as? EKReminder else {
            throw TaskProviderError.taskNotFound
        }
        
        reminder.title = item.title
        reminder.notes = encodeFriendlyMetadata(
            estimated: item.estimatedMinutes,
            remaining: item.remainingMinutes,
            isActive: item.isActive
        )
        reminder.isCompleted = item.isCompleted
        
        try eventStore.save(reminder, commit: true)
    }
    
    func deleteTask(remoteID: String) async throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: remoteID) as? EKReminder else {
            throw TaskProviderError.taskNotFound
        }
        
        try eventStore.remove(reminder, commit: true)
    }
    
    // MARK: - Helper Methods
    
    func loadAvailableLists() async {
        availableLists = eventStore.calendars(for: .reminder)
    }
    
    func setSelectedList(_ identifier: String?) {
        selectedListIdentifier = identifier
    }
    
    // MARK: - Metadata Encoding/Decoding
    
    private func encodeFriendlyMetadata(estimated: Int, remaining: Int, isActive: Bool) -> String {
        return [
            friendlyHeader,
            "Estimated Total Time: \(estimated) minutes",
            "Remaining Time: \(remaining) minutes",
            "Active: \(isActive)"
        ].joined(separator: "\n")
    }
    
    private func decodeMetadata(from reminder: EKReminder) -> (estimatedMinutes: Int, remainingMinutes: Int, isActive: Bool)? {
        guard let notes = reminder.notes else {
            return (defaultEstimateMinutes, defaultEstimateMinutes, false)
        }
        
        var estimated = defaultEstimateMinutes
        var remaining = defaultEstimateMinutes
        var active = false
        
        for line in notes.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Estimated Total Time:") {
                estimated = Int(trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? estimated
            } else if trimmed.hasPrefix("Remaining Time:") {
                remaining = Int(trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? remaining
            } else if trimmed.hasPrefix("Active:") {
                active = Bool(trimmed.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "false") ?? active
            }
        }
        
        return (estimated, remaining, active)
    }
}
