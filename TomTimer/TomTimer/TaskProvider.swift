//
//  TaskProvider.swift
//  TomTimer
//
//  Created by AI Assistant on 2025/11/27.
//

import Foundation

/// Protocol that all task list integration plugins must implement
public protocol TaskProvider: AnyObject {
    /// Unique identifier for this provider (e.g., "com.tomtimer.provider.reminders")
    var identifier: String { get }
    
    /// Display name shown to users (e.g., "Apple Reminders")
    var displayName: String { get }
    
    /// SF Symbol name for the provider icon
    var icon: String { get }
    
    /// Whether this provider requires user authentication
    var requiresAuthentication: Bool { get }
    
    /// Whether this provider is currently authenticated/configured
    var isAuthenticated: Bool { get }
    
    /// Authenticate or configure the provider
    func authenticate() async throws
    
    /// Fetch all tasks from the remote provider
    func fetchTasks() async throws -> [TaskProviderItem]
    
    /// Create a new task in the remote provider
    /// - Returns: The remote ID assigned by the provider
    func createTask(_ item: TaskProviderItem) async throws -> String
    
    /// Update an existing task in the remote provider
    func updateTask(_ item: TaskProviderItem) async throws
    
    /// Delete a task from the remote provider
    func deleteTask(remoteID: String) async throws
}

/// Standardized task item that providers exchange with the app
public struct TaskProviderItem: Codable, Identifiable {
    public let id: UUID
    public let remoteID: String?
    public let title: String
    public let estimatedMinutes: Int
    public let remainingMinutes: Int
    public let isActive: Bool
    public let isCompleted: Bool
    public let modifiedAt: Date
    
    public init(
        id: UUID,
        remoteID: String?,
        title: String,
        estimatedMinutes: Int,
        remainingMinutes: Int,
        isActive: Bool,
        isCompleted: Bool,
        modifiedAt: Date
    ) {
        self.id = id
        self.remoteID = remoteID
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.remainingMinutes = remainingMinutes
        self.isActive = isActive
        self.isCompleted = isCompleted
        self.modifiedAt = modifiedAt
    }
}

/// Errors that providers can throw
public enum TaskProviderError: LocalizedError {
    case authorizationDenied
    case notConfigured
    case networkError(String)
    case syncFailed(String)
    case taskNotFound
    
    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Authorization denied. Please grant access in Settings."
        case .notConfigured:
            return "Provider not configured. Please complete setup."
        case .networkError(let message):
            return "Network error: \(message)"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        case .taskNotFound:
            return "Task not found in remote provider."
        }
    }
}
