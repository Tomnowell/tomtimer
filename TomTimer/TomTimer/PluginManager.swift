//
//  PluginManager.swift
//  TomTimer
//
//  Created by AI Assistant on 2025/11/27.
//

import Foundation
import SwiftUI

/// Manages all task provider plugins
@MainActor
class PluginManager: ObservableObject {
    static let shared = PluginManager()
    
    /// All available providers (built-in and discovered)
    @Published private(set) var availableProviders: [TaskProvider] = []
    
    /// Set of enabled provider identifiers
    @Published var enabledProviders: Set<String> = [] {
        didSet {
            saveEnabledProviders()
        }
    }
    
    private let enabledProvidersKey = "enabledProviderIdentifiers"
    
    private init() {
        loadEnabledProviders()
        registerBuiltInProviders()
    }
    
    /// Register built-in providers that ship with the app
    private func registerBuiltInProviders() {
        // For now, we'll add the Reminders provider
        // Later: TodoistProvider(), ThingsProvider(), etc.
        availableProviders = []
    }
    
    /// Register a new provider
    func registerProvider(_ provider: TaskProvider) {
        // Avoid duplicates
        if !availableProviders.contains(where: { $0.identifier == provider.identifier }) {
            availableProviders.append(provider)
        }
    }
    
    /// Enable a provider
    func enableProvider(_ identifier: String) {
        enabledProviders.insert(identifier)
    }
    
    /// Disable a provider
    func disableProvider(_ identifier: String) {
        enabledProviders.remove(identifier)
    }
    
    /// Toggle a provider's enabled state
    func toggleProvider(_ identifier: String) {
        if enabledProviders.contains(identifier) {
            disableProvider(identifier)
        } else {
            enableProvider(identifier)
        }
    }
    
    /// Get a specific provider by identifier
    func getProvider(_ identifier: String) -> TaskProvider? {
        availableProviders.first { $0.identifier == identifier }
    }
    
    /// Get all enabled providers
    func getEnabledProviders() -> [TaskProvider] {
        availableProviders.filter { enabledProviders.contains($0.identifier) }
    }
    
    // MARK: - Persistence
    
    private func saveEnabledProviders() {
        UserDefaults.standard.set(Array(enabledProviders), forKey: enabledProvidersKey)
    }
    
    private func loadEnabledProviders() {
        if let saved = UserDefaults.standard.array(forKey: enabledProvidersKey) as? [String] {
            enabledProviders = Set(saved)
        }
    }
}
