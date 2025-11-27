//
//  SettingsView.swift
//  Pomodoro
//
//  Created by Tom on 2025/03/18.
//  Copyright © 2025 I. All rights reserved.
//

import SwiftUI
import EventKit

struct SettingsView: View {
    @AppStorage("timerDuration") private var timerDuration = 1500  // Default 25 mins
    @StateObject private var remindersManager = RemindersManager.shared
    @State private var showingListPicker = false
    
    private var pluginManager: PluginManager { PluginManager.shared }

    var body: some View {
        Form {
            Section(header: Text("Timer Settings")) {
                Stepper(value: $timerDuration, in: 60...3600, step: 60) {
                    Text("Pomodoro Duration: \(timerDuration / 60) min")
                }
            }
            
            Section(header: Text("Integrations")) {
                if pluginManager.availableProviders.isEmpty {
                    Text("No integrations available")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(pluginManager.availableProviders.enumerated()), id: \.offset) { index, provider in
                        HStack {
                            Image(systemName: provider.icon)
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .font(.body)
                                if !provider.isAuthenticated {
                                    Text("Tap to configure")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if pluginManager.enabledProviders.contains(provider.identifier) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                if !provider.isAuthenticated {
                                    do {
                                        try await provider.authenticate()
                                        pluginManager.enableProvider(provider.identifier)
                                    } catch {
                                        print("Authentication failed: \(error)")
                                    }
                                } else {
                                    pluginManager.toggleProvider(provider.identifier)
                                }
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Reminders Sync")) {
                Button(action: {
                    Task {
                        if remindersManager.authorizationStatus == .fullAccess ||
                            remindersManager.authorizationStatus == .writeOnly {
                            showingListPicker = true
                        } else {
                            let granted = await remindersManager.requestAccess()
                            if granted {
                                showingListPicker = true
                            }
                        }
                    }
                }) {
                    HStack {
                        Text("Selected List")
                        Spacer()
                        if let list = remindersManager.selectedList {
                            Text(list.title)
                                .foregroundColor(.secondary)
                        } else {
                            Text("None")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if remindersManager.authorizationStatus == .denied {
                    Text("Reminders access denied. Please enable in Settings.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingListPicker) {
            RemindersListPicker(
                lists: remindersManager.availableLists,
                selectedID: Binding(
                    get: { remindersManager.selectedListIdentifier ?? "" },
                    set: { remindersManager.selectedListIdentifier = $0.isEmpty ? nil : $0 }
                )
            )
        }
        .task {
            remindersManager.updateAuthorizationStatus()
            if remindersManager.authorizationStatus == .fullAccess ||
                remindersManager.authorizationStatus == .writeOnly {
                await remindersManager.loadAvailableLists()
            }
        }
    }
}

struct RemindersListPicker: View {
    let lists: [EKCalendar]
    @Binding var selectedID: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(lists, id: \.calendarIdentifier) { list in
                HStack {
                    Circle()
                        .fill(Color(cgColor: list.cgColor))
                        .frame(width: 12, height: 12)
                    Text(list.title)
                    Spacer()
                    if list.calendarIdentifier == selectedID {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedID = list.calendarIdentifier
                    dismiss()
                }
            }
            .navigationTitle("Select Reminders List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [TodoItem.self, TomTimerSession.self], inMemory: true)
}

extension Notification.Name {
    static let reminderListSelected = Notification.Name("reminderListSelected")
}
