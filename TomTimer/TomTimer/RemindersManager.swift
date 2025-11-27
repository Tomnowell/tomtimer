//
//  RemindersManager.swift
//  TomTimer
//
//  Created by Tom on 2025/03/21.
//

import Foundation
import EventKit
import SwiftData

@MainActor
final class RemindersManager: ObservableObject {
    private static let selectedListDefaultsKey = "selectedRemindersList"
    private let defaultEstimateMinutes = 25
    private let friendlyHeader = "TicketyPom Task"
    static let shared = RemindersManager()

    private let eventStore = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var availableLists: [EKCalendar] = []
    @Published var selectedListIdentifier: String? {
        didSet {
            guard selectedListIdentifier != oldValue else { return }
            if let identifier = selectedListIdentifier {
                UserDefaults.standard.set(identifier, forKey: Self.selectedListDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedListDefaultsKey)
            }
        }
    }

    private init() {
        selectedListIdentifier = UserDefaults.standard.string(forKey: Self.selectedListDefaultsKey)
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            if granted {
                await loadAvailableLists()
            }
            return granted
        } catch {
            print("Reminders access error: \(error)")
            return false
        }
    }

    // MARK: - Calendar Lists

    func loadAvailableLists() async {
        let calendars = eventStore.calendars(for: .reminder)
        availableLists = calendars

        if let currentID = selectedListIdentifier,
           calendars.first(where: { $0.calendarIdentifier == currentID }) == nil {
            selectedListIdentifier = nil
        }

        if selectedListIdentifier == nil,
           let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
            selectedListIdentifier = defaultCalendar.calendarIdentifier
        }
    }

    var selectedList: EKCalendar? {
        guard let id = selectedListIdentifier else { return nil }
        return eventStore.calendar(withIdentifier: id)
    }

    // MARK: - Metadata

    struct ReminderMetadata: Codable, Equatable {
        var estimatedMinutes: Int
        var remainingMinutes: Int
        var isActive: Bool
    }

    func encodeMetadata(for task: TodoItem) -> String {
        [
            friendlyHeader,
            "Estimated Total Time: \(task.estimatedMinutes) minutes",
            "Remaining Time: \(task.remainingMinutes) minutes",
            "Active: \(task.isActive)"
        ].joined(separator: "\n")
    }

    private func reminderMetadata(for reminder: EKReminder) -> ReminderMetadata {
        guard let notes = reminder.notes else {
            return ReminderMetadata(
                estimatedMinutes: defaultEstimateMinutes,
                remainingMinutes: defaultEstimateMinutes,
                isActive: false
            )
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

        return ReminderMetadata(
            estimatedMinutes: estimated,
            remainingMinutes: remaining,
            isActive: active
        )
    }

    // MARK: - Fetch / Save

    func fetchReminders() async -> [EKReminder] {
        guard let calendar = selectedList else { return [] }
        let predicate = eventStore.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    func createOrUpdateReminder(for task: TodoItem) async throws {
        guard let calendar = selectedList else {
            throw RemindersError.noListSelected
        }

        let reminder: EKReminder
        if let identifier = task.reminderIdentifier,
           let existing = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
        }

        reminder.title = task.title
        reminder.isCompleted = (task.remainingMinutes == 0)
        reminder.notes = encodeMetadata(for: task)

        try eventStore.save(reminder, commit: true)
        task.reminderIdentifier = reminder.calendarItemIdentifier
    }

    func deleteReminder(for task: TodoItem) async throws {
        guard let identifier = task.reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }
        try eventStore.remove(reminder, commit: true)
        task.reminderIdentifier = nil
    }

    // MARK: - Sync

    func syncFromReminders(to context: ModelContext, tasks: [TodoItem]) async -> [SyncConflict] {
        let reminders = await fetchReminders()
        var conflicts: [SyncConflict] = []
        var processedIdentifiers = Set<String>()

        for reminder in reminders {
            let metadata = reminderMetadata(for: reminder)
            let reminderID = reminder.calendarItemIdentifier

            if let existing = tasks.first(where: { $0.reminderIdentifier == reminderID }) {
                processedIdentifiers.insert(reminderID)
                if reminder.title != existing.title ||
                    metadata.estimatedMinutes != existing.estimatedMinutes ||
                    metadata.remainingMinutes != existing.remainingMinutes {
                    conflicts.append(SyncConflict(
                        task: existing,
                        reminder: reminder,
                        reminderId: reminderID,
                        localTitle: existing.title,
                        remoteTitle: reminder.title ?? "",
                        localEstimate: existing.estimatedMinutes,
                        remoteEstimate: metadata.estimatedMinutes,
                        localRemaining: existing.remainingMinutes,
                        remoteRemaining: metadata.remainingMinutes
                    ))
                } else {
                    updateTask(existing, with: reminder, metadata: metadata)
                }
            } else {
                let newTask = TodoItem(
                    title: reminder.title ?? "Untitled",
                    estimatedMinutes: metadata.estimatedMinutes,
                    isActive: metadata.isActive,
                    reminderIdentifier: reminderID
                )
                newTask.remainingMinutes = metadata.remainingMinutes
                context.insert(newTask)
                processedIdentifiers.insert(reminderID)
            }
        }

        for task in tasks {
            guard let identifier = task.reminderIdentifier else { continue }
            if !processedIdentifiers.contains(identifier) {
                context.delete(task)
            }
        }

        return conflicts
    }

    private func updateTask(_ task: TodoItem, with reminder: EKReminder, metadata: ReminderMetadata) {
        task.title = reminder.title ?? task.title
        task.estimatedMinutes = metadata.estimatedMinutes
        task.remainingMinutes = metadata.remainingMinutes
        task.isActive = metadata.isActive
    }

    func resolveConflict(_ conflict: SyncConflict, keepLocal: Bool, task: TodoItem, reminder: EKReminder) async throws {
        if keepLocal {
            try await createOrUpdateReminder(for: task)
        } else {
            let metadata = reminderMetadata(for: reminder)
            updateTask(task, with: reminder, metadata: metadata)
        }
    }
}

struct SyncConflict: Identifiable {
    let id = UUID()
    let task: TodoItem
    let reminder: EKReminder
    let reminderId: String
    let localTitle: String
    let remoteTitle: String
    let localEstimate: Int
    let remoteEstimate: Int
    let localRemaining: Int
    let remoteRemaining: Int
}

enum RemindersError: Error {
    case noListSelected
    case accessDenied
}
