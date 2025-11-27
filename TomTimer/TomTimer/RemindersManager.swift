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
    private let metadataHeader = "TOMTIMER_DATA"
    private lazy var iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
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

    private struct ReminderMetadata: Codable {
        var estimatedMinutes: Int
        var remainingMinutes: Int
        var modifiedAt: Date
        var isActive: Bool
    }

    private func encodeMetadata(for task: TodoItem) -> String {
        [
            metadataHeader,
            "estimatedMinutes:\(task.estimatedMinutes)",
            "remainingMinutes:\(task.remainingMinutes)",
            "modifiedAt:\(iso8601Formatter.string(from: task.modifiedAt))",
            "isActive:\(task.isActive)"
        ].joined(separator: "\n")
    }

    private func decodeMetadata(from notes: String?) -> ReminderMetadata? {
        guard let notes,
              let headerRange = notes.range(of: metadataHeader) else {
            return nil
        }

        var payload = notes[headerRange.upperBound...]
        if payload.first == ":" {
            payload = payload.dropFirst()
        }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{") {
            if let data = trimmed.data(using: .utf8),
               let legacyMetadata = try? JSONDecoder().decode(ReminderMetadata.self, from: data) {
                return legacyMetadata
            }
        }

        var estimated = defaultEstimateMinutes
        var remaining = defaultEstimateMinutes
        var modified = Date()
        var isActive = false

        for line in trimmed.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0) }
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "estimatedMinutes":
                estimated = Int(value) ?? estimated
            case "remainingMinutes":
                remaining = Int(value) ?? remaining
            case "modifiedAt":
                if let date = iso8601Formatter.date(from: value) {
                    modified = date
                }
            case "isActive":
                isActive = Bool(value) ?? isActive
            default:
                break
            }
        }

        return ReminderMetadata(
            estimatedMinutes: estimated,
            remainingMinutes: remaining,
            modifiedAt: modified,
            isActive: isActive
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
                if existing.modifiedAt > metadata.modifiedAt {
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
                    }
                } else {
                    updateTask(existing, with: reminder, metadata: metadata)
                }
            } else {
                let newTask = TodoItem(
                    title: reminder.title ?? "Untitled",
                    estimatedMinutes: metadata.estimatedMinutes,
                    isActive: metadata.isActive,
                    createdAt: reminder.creationDate ?? Date(),
                    reminderIdentifier: reminderID
                )
                newTask.remainingMinutes = metadata.remainingMinutes
                newTask.modifiedAt = metadata.modifiedAt
                context.insert(newTask)
                processedIdentifiers.insert(reminderID)
            }
        }

        // Remove tasks whose reminders aren't in the selected list anymore
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
        task.modifiedAt = metadata.modifiedAt
    }

    func resolveConflict(_ conflict: SyncConflict, keepLocal: Bool, task: TodoItem, reminder: EKReminder) async throws {
        if keepLocal {
            try await createOrUpdateReminder(for: task)
        } else if let metadata = decodeMetadata(from: reminder.notes) {
            updateTask(task, with: reminder, metadata: metadata)
        }
    }

    private func reminderMetadata(for reminder: EKReminder) -> ReminderMetadata {
        if let decoded = decodeMetadata(from: reminder.notes) {
            return decoded
        }
        let timestamp = reminder.lastModifiedDate ?? reminder.creationDate ?? Date()
        return ReminderMetadata(
            estimatedMinutes: defaultEstimateMinutes,
            remainingMinutes: defaultEstimateMinutes,
            modifiedAt: timestamp,
            isActive: false
        )
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
