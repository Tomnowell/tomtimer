//
//  ContentView.swift
//  TomTimer
//
//  Created by Tom on 2025/03/21.
//

import SwiftUI
import SwiftData
import UserNotifications
import WatchConnectivity

struct ContentView: View {
    @AppStorage("timerDuration") private var timerDuration = 1500
    @State private var timeRemaining = 1500
    @State private var timerActive = false
    @State private var timer: Timer?
    @State private var showingNewTaskSheet = false
    @State private var taskTitle = ""
    @State private var estimatedMinutesInput = 25
    @State private var taskToEdit: TodoItem?
    @State private var activeTaskTitle: String?
    @State private var sessionDuration: Int?
    @State private var syncConflicts: [SyncConflict] = []
    @State private var showingConflictResolver = false
    @State private var isSyncing = false

    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.createdAt) private var tasks: [TodoItem]
    @StateObject private var remindersManager = RemindersManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 48) {
                VStack(spacing: 80) {
                    Text(activeTaskTitle ?? "Select a task")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                timerControls
                taskList
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { performSync() }) {
                            Label("Sync", systemImage: isSyncing ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                        }
                        .disabled(isSyncing || remindersManager.selectedList == nil)

                        Button(action: { showingNewTaskSheet = true }) {
                            Label("Add Task", systemImage: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear(perform: bootstrapState)
            .onChange(of: timerDuration) { oldValue, newValue in
                if !timerActive {
                    timeRemaining = newValue
                    sessionDuration = nil
                    WatchConnectivityManager.shared.sendTimerUpdate(newValue)
                }
            }
        }
        .sheet(isPresented: $showingNewTaskSheet) {
            taskEditor
        }
        .sheet(isPresented: $showingConflictResolver) {
            ConflictResolverView(conflicts: $syncConflicts, remindersManager: remindersManager, tasks: tasks)
        }
        .onChange(of: remindersManager.selectedListIdentifier) { _, newValue in
            guard newValue != nil else { return }
            performSync()
        }
    }

    private var timerControls: some View {
        VStack(spacing: 22) {
            Button(action: startTimer) {
                Text(timerActive ? "Running" : "Start")
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(timerActive ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(timerActive || activeTask == nil)

            HStack(spacing: 16) {
                Button("Pause", action: pauseTimer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(!timerActive)

                Button("Reset", action: resetTimer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }

    private var taskList: some View {
        List {
            Section("Todo List") {
                if tasks.isEmpty {
                    Text("Add a task to get started")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(tasks) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.body)
                                Text("Remaining: \(task.remainingMinutes) min / \(task.estimatedMinutes) min")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if task.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            select(task)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                taskToEdit = task
                                taskTitle = task.title
                                estimatedMinutesInput = task.estimatedMinutes
                                showingNewTaskSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var taskEditor: some View {
        NavigationStack {
            Form {
                Section(header: Text("Task")) {
                    TextField("Title", text: $taskTitle)
                    Stepper(value: $estimatedMinutesInput, in: 5...600, step: 5) {
                        Text("Estimated Minutes: \(estimatedMinutesInput)")
                    }
                }
                if let editing = taskToEdit {
                    Section(header: Text("Adjust Remaining")) {
                        Stepper(value: Binding(get: { editing.remainingMinutes }, set: { newValue in
                            editing.remainingMinutes = newValue
                        }), in: 0...editing.estimatedMinutes, step: 5) {
                            Text("Remaining Minutes: \(editing.remainingMinutes)")
                        }
                    }
                }
            }
            .navigationTitle(taskToEdit == nil ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismissTaskEditor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveTask)
                        .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var activeTask: TodoItem? {
        tasks.first(where: { $0.isActive })
    }

    private func bootstrapState() {
        timeRemaining = timerDuration
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)
        activeTaskTitle = activeTask?.title
        WatchConnectivityManager.shared.sendActiveTask(title: activeTaskTitle)

        NotificationCenter.default.addObserver(forName: .timerUpdated, object: nil, queue: .main) { notification in
            if let newTime = notification.object as? Int {
                timeRemaining = newTime
            }
        }
        NotificationCenter.default.addObserver(forName: .activeTaskUpdated, object: nil, queue: .main) { notification in
            activeTaskTitle = notification.object as? String
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func startTimer() {
        guard let task = activeTask else { return }
        if sessionDuration == nil {
            sessionDuration = timeRemaining
        }
        timerActive = true
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)
        WatchConnectivityManager.shared.sendActiveTask(title: task.title)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
                WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)
            } else {
                timerExpired()
            }
        }
    }

    private func timerExpired() {
        timer?.invalidate()
        timer = nil
        timerActive = false
        // Prefer measured elapsed; fall back to planned session duration; else current setting
        let elapsedSeconds = elapsedSecondsForCurrentSession() ?? sessionDuration ?? timerDuration
        notifyTimerFinished()
        WatchConnectivityManager.shared.sendTimerUpdate(0)
        saveCompletedSession(duration: elapsedSeconds)
        applyCompletionToActiveTask(elapsedSeconds: elapsedSeconds)
        sessionDuration = nil
        timeRemaining = timerDuration
    }

    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
        timerActive = false
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)
    }

    private func resetTimer() {
        // Apply any elapsed time from the current session before resetting
        if let elapsed = elapsedSecondsForCurrentSession() {
            applyCompletionToActiveTask(elapsedSeconds: elapsed)
        }
        timer?.invalidate()
        timer = nil
        timerActive = false
        timeRemaining = timerDuration
        sessionDuration = nil
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)
    }

    private func notifyTimerFinished() {
        let content = UNMutableNotificationContent()
        content.title = "🍅 Pomodoro Finished!"
        content.body = activeTaskTitle.map { "\($0) updated." } ?? "Nice job! Time for a short break."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification scheduling error: \(error.localizedDescription)")
            }
        }
    }

    private func saveCompletedSession(duration: Int) {
        let session = TomTimerSession(duration: duration)
        context.insert(session)
        let newCount = TimerSyncManager.shared.getCompletedSessions() + 1
        TimerSyncManager.shared.saveCompletedSessions(newCount)

        do {
            try context.save()
        } catch {
            print("Error saving session: \(error.localizedDescription)")
        }
    }

    private func applyCompletionToActiveTask(elapsedSeconds: Int) {
        guard let task = activeTask else { return }
        let minutes = minutesFromSeconds(elapsedSeconds)
        guard minutes > 0 else { return }
        task.applyCompletion(minutes: minutes)
        if task.remainingMinutes == 0 {
            task.isActive = false
            activeTaskTitle = nil
            WatchConnectivityManager.shared.sendActiveTask(title: nil)
        }
        persistTasks()
    }

    private func minutesFromSeconds(_ seconds: Int) -> Int {
        guard seconds > 0 else { return 0 }
        // Use ceiling to the next minute so partial minutes still count
        return (seconds + 59) / 60
    }

    private func elapsedSecondsForCurrentSession() -> Int? {
        guard let original = sessionDuration else { return nil }
        let elapsed = original - timeRemaining
        return elapsed > 0 ? elapsed : nil
    }

    private func select(_ task: TodoItem) {
        // Apply elapsed time to the previously active task before switching
        if let elapsed = elapsedSecondsForCurrentSession(), let previous = activeTask {
            let minutes = minutesFromSeconds(elapsed)
            if minutes > 0 {
                previous.applyCompletion(minutes: minutes)
                if previous.remainingMinutes == 0 {
                    previous.isActive = false
                }
                persistTasks()
            }
        }
        // Stop and reset the session without applying again
        timer?.invalidate()
        timer = nil
        timerActive = false
        sessionDuration = nil
        timeRemaining = timerDuration
        WatchConnectivityManager.shared.sendTimerUpdate(timeRemaining)

        // Toggle active flags
        for item in tasks {
            item.isActive = (item.id == task.id)
        }
        activeTaskTitle = task.title
        WatchConnectivityManager.shared.sendActiveTask(title: task.title)
        persistTasks()
    }

    private func delete(_ task: TodoItem) {
        context.delete(task)
        if task.isActive {
            activeTaskTitle = nil
            WatchConnectivityManager.shared.sendActiveTask(title: nil)
        }
        persistTasks()
    }

    private func saveTask() {
        let trimmedTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let editing = taskToEdit {
            editing.title = trimmedTitle
            editing.updateEstimates(estimated: estimatedMinutesInput, remaining: editing.remainingMinutes)
        } else {
            let newTask = TodoItem(title: trimmedTitle, estimatedMinutes: estimatedMinutesInput)
            context.insert(newTask)
        }

        persistTasks()
        dismissTaskEditor()
    }

    private func dismissTaskEditor() {
        taskTitle = ""
        estimatedMinutesInput = 25
        taskToEdit = nil
        showingNewTaskSheet = false
    }

    private func persistTasks() {
        do {
            try context.save()
        } catch {
            print("Failed to save tasks: \(error.localizedDescription)")
        }
    }

    private func performSync() {
        guard remindersManager.authorizationStatus == .fullAccess ||
              remindersManager.authorizationStatus == .writeOnly,
              remindersManager.selectedList != nil else {
            return
        }

        isSyncing = true
        Task {
            defer { isSyncing = false }

            let conflicts = await remindersManager.syncFromReminders(to: context, tasks: tasks)
            if !conflicts.isEmpty {
                syncConflicts = conflicts
                showingConflictResolver = true
            }

            for task in tasks {
                do {
                    try await remindersManager.createOrUpdateReminder(for: task)
                } catch {
                    print("Error syncing task to reminder: \(error.localizedDescription)")
                }
            }

            do {
                try context.save()
            } catch {
                print("Failed to save context after sync: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TodoItem.self, TomTimerSession.self], inMemory: true)
}
