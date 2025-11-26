//
//  ConflictResolverView.swift
//  TomTimer
//
//  Created by Tom on 2025/03/21.
//

import SwiftUI
import EventKit

struct ConflictResolverView: View {
    @Binding var conflicts: [SyncConflict]
    let remindersManager: RemindersManager
    let tasks: [TodoItem]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(conflicts) { conflict in
                    ConflictRow(
                        conflict: conflict,
                        remindersManager: remindersManager,
                        tasks: tasks,
                        onResolved: {
                            conflicts.removeAll { $0.id == conflict.id }
                            if conflicts.isEmpty {
                                dismiss()
                            }
                        }
                    )
                }
            }
            .navigationTitle("Sync Conflicts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip All") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ConflictRow: View {
    let conflict: SyncConflict
    let remindersManager: RemindersManager
    let tasks: [TodoItem]
    let onResolved: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conflict: \(conflict.localTitle)")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Local (TomTimer)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    VStack(alignment: .leading) {
                        Text(conflict.localTitle)
                        Text("Estimate: \(conflict.localEstimate) min")
                        Text("Remaining: \(conflict.localRemaining) min")
                    }
                    .font(.caption)
                    
                    Spacer()
                    
                    Button("Keep This") {
                        resolveConflict(keepLocal: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote (Reminders)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    VStack(alignment: .leading) {
                        Text(conflict.remoteTitle)
                        Text("Estimate: \(conflict.remoteEstimate) min")
                        Text("Remaining: \(conflict.remoteRemaining) min")
                    }
                    .font(.caption)
                    
                    Spacer()
                    
                    Button("Keep This") {
                        resolveConflict(keepLocal: false)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.vertical, 8)
    }
    
    private func resolveConflict(keepLocal: Bool) {
        Task {
            if let task = tasks.first(where: { $0.reminderIdentifier == conflict.reminderId }) {
                do {
                    try await remindersManager.resolveConflict(
                        conflict,
                        keepLocal: keepLocal,
                        task: task,
                        reminder: conflict.reminder
                    )
                    onResolved()
                } catch {
                    print("Error resolving conflict: \(error)")
                }
            }
        }
    }
}
