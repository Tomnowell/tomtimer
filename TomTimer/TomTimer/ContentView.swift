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
    @AppStorage("timerEndDateTimestamp") private var timerEndDateTimestamp: Double = 0
    @AppStorage("sessionDurationBackup") private var storedSessionDuration: Int = 0
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
    @State private var showingTimerCompleteAlert = false
    @State private var isSyncing = false
    @State private var hasBootstrapped = false
    @State private var lastScenePhase: ScenePhase? = nil
    @State private var isTaskBoundSession = false
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.modifiedAt) private var tasks: [TodoItem]
    @StateObject private var remindersManager = RemindersManager.shared
    @StateObject private var pluginManager = PluginManager.shared
    
    let brown = Color(red: 122/255, green: 92/255, blue: 84/255)
    let green = Color(red: 48/255, green: 250/255, blue: 116/255)
    let orange = Color(red: 250/255, green: 88/255, blue: 57/255)
    let pink = Color(red: 250/255, green: 47/255, blue: 151/255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text(activeTaskTitle ?? "No task selected")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                timerControls
                center
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
            .onChange(of: timerDuration) { oldValue, newValue in
                if !timerActive {
                    timeRemaining = newValue
                    sessionDuration = nil
                    timerEndDateTimestamp = 0
                    storedSessionDuration = 0
                    syncTimerState(isRunning: false, seconds: newValue)
                }
            }
        }
        .sheet(isPresented: $showingNewTaskSheet) {
            taskEditor
        }
        .sheet(isPresented: $showingConflictResolver) {
            ConflictResolverView(conflicts: $syncConflicts, remindersManager: remindersManager, tasks: tasks)
        }
        .alert("Pomodoro Complete! 🍅", isPresented: $showingTimerCompleteAlert) {
            Button("OK", role: .cancel) { }
            Button("Start Another") {
                if activeTask != nil {
                    startTimer()
                }
            }
        } message: {
            if let taskTitle = activeTaskTitle {
                Text("Great work on \(taskTitle)! Time for a break.")
            } else {
                Text("Great work! Time for a break.")
            }
        }
        .onChange(of: remindersManager.selectedListIdentifier) { _, newValue in
            guard newValue != nil else { return }
            performSync()
        }
    }
    
    
    private var timerControls: some View {
        
        VStack(spacing: 24) {
            Button(action: { startTimer() }) {
                Text(timerActive ? "Running" : "Start")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(timerActive ? brown: green)
                    .foregroundColor(timerActive ? green: brown)
                    .cornerRadius(12)
            }
            .disabled(timerActive)

            HStack(spacing: 16) {
                Button("Pause", action: pauseTimer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(pink)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(!timerActive)

                Button("Reset", action: resetTimer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
    
    private var center: some View {
        VStack () {
            Text("Todo List:")
        }
    }

    private var taskList: some View {
        List {
            Section() {
                if tasks.isEmpty {
                    Text("Add a task or start a timer with no task")
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
                            toggleSelection(for: task)
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
                
                // Add Task button row
                Button(action: { showingNewTaskSheet = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Task")
                            .foregroundColor(.blue)
                        Spacer()
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
                    Stepper(value: $estimatedMinutesInput, in: 1...600, step: 1) {
                        Text("Estimated Minutes: \(estimatedMinutesInput)")
                    }
                }
                if let editing = taskToEdit {
                    Section(header: Text("Adjust Remaining")) {
                        Stepper(value: Binding(get: { editing.remainingMinutes }, set: { newValue in
                            editing.remainingMinutes = newValue
                        }), in: 0...editing.estimatedMinutes, step: 1) {
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

    private func toggleSelection(for task: TodoItem) {
        if task.isActive {
            // Deselect current task
            task.isActive = false
            activeTaskTitle = nil
            isTaskBoundSession = false
            WatchConnectivityManager.shared.sendActiveTask(title: nil)
            persistTasks()
        } else {
            select(task)
        }
    }

    private func bootstrapState() {
        // Ensure we only bootstrap once per ContentView lifecycle
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // Only set an initial time if there is no persisted session
        if timerEndDateTimestamp == 0 && storedSessionDuration == 0 {
            timeRemaining = timerDuration
        } else {
            // Try to restore existing timer immediately on launch
            restoreTimerIfNeeded()
        }

        syncTimerState(isRunning: timerActive, seconds: timeRemaining)
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
        NotificationCenter.default.addObserver(forName: .timerStatusUpdated, object: nil, queue: .main) { notification in
            guard let isRunning = notification.object as? Bool else { return }
            handleRemoteTimerStatusChange(isRunning)
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase?, to newPhase: ScenePhase) {
        lastScenePhase = newPhase
        switch (oldPhase, newPhase) {
        case (.inactive, .active), (.background, .active):
            // Only attempt restore when coming back from inactive/background
            restoreTimerIfNeeded()
        case (_, .background):
            // Persist timer state when going to background
            persistTimerState()
        default:
            break
        }
    }

    // Restore timer based on persisted end timestamp and stored session duration
    private func restoreTimerIfNeeded() {
        guard timerEndDateTimestamp > 0 else { return }

        let now = Date().timeIntervalSince1970
        let remaining = timerEndDateTimestamp - now

        if remaining <= 0 {
            // Timer expired while app was inactive – reset to default
            timerActive = false
            timeRemaining = timerDuration
            sessionDuration = nil
            clearTimerPersistence()
            isTaskBoundSession = false
            syncTimerState(isRunning: false, seconds: timeRemaining)
            return
        }

        timeRemaining = Int(remaining)

        if sessionDuration == nil {
            if storedSessionDuration > 0 {
                sessionDuration = storedSessionDuration
            } else {
                sessionDuration = timerDuration
            }
        }

        // If we don't already have a timer running, start one in resume mode
        if timer == nil {
            timerActive = true
            startTimer(resumingExisting: true)
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func syncTimerState(isRunning: Bool? = nil, seconds: Int? = nil) {
        let runningState = isRunning ?? timerActive
        let remainingSeconds = seconds ?? timeRemaining
        WatchConnectivityManager.shared.sendTimerState(timeRemaining: remainingSeconds, isRunning: runningState)
    }

    private func handleRemoteTimerStatusChange(_ isRunning: Bool) {
        if !isRunning {
            timer?.invalidate()
            timer = nil
        }
        timerActive = isRunning
    }

    private func startTimer(resumingExisting: Bool = false) {
        let task = activeTask

        if resumingExisting {
            if sessionDuration == nil {
                sessionDuration = storedSessionDuration > 0 ? storedSessionDuration : timerDuration
            }
        } else if sessionDuration == nil {
            sessionDuration = timeRemaining
        }

        isTaskBoundSession = (task != nil)
        storedSessionDuration = sessionDuration ?? timerDuration
        timer?.invalidate()
        timerActive = true
        syncTimerState(isRunning: true)
        WatchConnectivityManager.shared.sendActiveTask(title: task?.title)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
                syncTimerState(isRunning: true)
            } else {
                timerExpired()
            }
        }

        persistTimerState()
    }

    private func timerExpired() {
        timer?.invalidate()
        timer = nil
        timerActive = false
        let elapsedSeconds = elapsedSecondsForCurrentSession() ?? sessionDuration ?? timerDuration
        
        // Trigger haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
        
        // Show system notification
        notifyTimerFinished()
        
        // Show in-app alert
        showingTimerCompleteAlert = true
        
        syncTimerState(isRunning: false, seconds: 0)
        saveCompletedSession(duration: elapsedSeconds)
        
        if isTaskBoundSession {
            applyCompletionToActiveTask(elapsedSeconds: elapsedSeconds)
        }
        
        isTaskBoundSession = false
        sessionDuration = nil
        storedSessionDuration = 0
        timerEndDateTimestamp = 0
        timeRemaining = timerDuration
    }

    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
        timerActive = false
        persistTimerState()
        syncTimerState(isRunning: false)
    }

    private func resetTimer() {
        if isTaskBoundSession, let elapsed = elapsedSecondsForCurrentSession() {
            applyCompletionToActiveTask(elapsedSeconds: elapsed)
        }
        timer?.invalidate()
        timer = nil
        timerActive = false
        timeRemaining = timerDuration
        sessionDuration = nil
        storedSessionDuration = 0
        timerEndDateTimestamp = 0
        isTaskBoundSession = false
        syncTimerState(isRunning: false)
    }

    private func notifyTimerFinished() {
        let content = UNMutableNotificationContent()
        content.title = "🍅 Pomodoro Finished!"
        content.body = activeTaskTitle.map { "\($0) updated." } ?? "Nice job! Time for a break."
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
        if isTaskBoundSession, let elapsed = elapsedSecondsForCurrentSession(), let previous = activeTask {
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
        storedSessionDuration = 0
        timerEndDateTimestamp = 0
        timeRemaining = timerDuration
        isTaskBoundSession = false
        syncTimerState(isRunning: false)

        // Toggle active flags
        for item in tasks {
            item.isActive = (item.id == task.id)
        }
        activeTaskTitle = task.title
        isTaskBoundSession = task.isActive
        WatchConnectivityManager.shared.sendActiveTask(title: task.title)
        persistTasks()
    }

    private func delete(_ task: TodoItem) {
        context.delete(task)
        if task.isActive {
            activeTaskTitle = nil
            isTaskBoundSession = false
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

    private func persistTimerState() {
        guard timerActive else { return }
        let now = Date().timeIntervalSince1970
        timerEndDateTimestamp = now + Double(timeRemaining)
        storedSessionDuration = sessionDuration ?? timerDuration
    }

    private func clearTimerPersistence() {
        timerEndDateTimestamp = 0
        storedSessionDuration = 0
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
