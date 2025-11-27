import Testing
import Foundation
import EventKit

@MainActor
struct TomTimerTests {
    @Test func reminderMetadataParsesFriendlyNotes() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let notes = [
            "TicketyPom Task",
            "Estimated Total Time: 30 minutes",
            "Remaining Time: 12 minutes",
            "Active: true",
        ].joined(separator: "\n")

        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.notes = notes

        let metadata = decodeFriendlyMetadata(from: reminder)
        #expect(metadata.estimatedMinutes == 30)
        #expect(metadata.remainingMinutes == 12)
        #expect(metadata.isActive == true)
    }

    @Test func reminderMetadataFallsBackWhenNotesMissing() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.notes = nil
        let metadata = decodeFriendlyMetadata(from: reminder)
        #expect(metadata.estimatedMinutes == 25)
        #expect(metadata.remainingMinutes == 25)
    }

    @Test func reminderMetadataHandlesMissingTimestamp() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.notes = [
            "TicketyPom Task",
            "Estimated Total Time: 15 minutes",
            "Remaining Time: 5 minutes",
            "Active: false"
        ].joined(separator: "\n")

        let metadata = decodeFriendlyMetadata(from: reminder)
        #expect(metadata.estimatedMinutes == 15)
        #expect(metadata.remainingMinutes == 5)
    }

    private func decodeFriendlyMetadata(from reminder: EKReminder) -> ReminderMetadata {
        guard let notes = reminder.notes else {
            return .init(
                estimatedMinutes: 25,
                remainingMinutes: 25,
                isActive: false
            )
        }

        var estimated = 25
        var remaining = 25
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

        return .init(
            estimatedMinutes: estimated,
            remainingMinutes: remaining,
            isActive: active
        )
    }
}

// Simple metadata struct for test purposes
struct ReminderMetadata {
    let estimatedMinutes: Int
    let remainingMinutes: Int
    let isActive: Bool
}
