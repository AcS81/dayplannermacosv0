//
//  DayPlannerApp.swift
//  DayPlanner
//
//  Liquid Glass Day Planner - Main App
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Tab Enum

enum MindSection: String, CaseIterable, Identifiable {
    case recommendations
    case goals
    case pillars
    case view
    
    var id: String { rawValue }
}

enum MindDestination: Equatable {
    case recommendations
    case goals(targetId: UUID?)
    case pillars(targetId: UUID?)
    case view
    
    var section: MindSection {
        switch self {
        case .recommendations: return .recommendations
        case .goals: return .goals
        case .pillars: return .pillars
        case .view: return .view
        }
    }
}

@MainActor
final class MindNavigationModel: ObservableObject {
    @Published private(set) var pendingDestination: MindDestination?
    
    func open(to destination: MindDestination) {
        pendingDestination = destination
    }
    
    func consumeDestination() {
        pendingDestination = nil
    }
}

enum AppTab: String, CaseIterable {
    case calendar = "calendar"
    case mind = "mind"
    
    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .mind: return "Mind"
        }
    }
}

@main
struct DayPlannerApp: App {
    @StateObject private var dataManager: AppDataManager
    @StateObject private var aiService: AIService
    @StateObject private var mindNavigator = MindNavigationModel()
    @StateObject private var onboardingCoordinator: OnboardingCoordinator

    init() {
        let dataManager = AppDataManager()
        let aiService = AIService()
        dataManager.patternEngine = PatternLearningEngine(dataManager: dataManager, aiService: aiService)
        aiService.setPatternEngine(dataManager.patternEngine)
        let onboarding = OnboardingCoordinator(dataManager: dataManager, aiService: aiService)
        _dataManager = StateObject(wrappedValue: dataManager)
        _aiService = StateObject(wrappedValue: aiService)
        _onboardingCoordinator = StateObject(wrappedValue: onboarding)
    }
    
    var body: some Scene {
        WindowGroup {
            RippleContainer {
                ContentView()
                    .environmentObject(dataManager)
                    .environmentObject(aiService)
                    .environmentObject(dataManager.patternEngine)
                    .environmentObject(mindNavigator)
                    .environmentObject(onboardingCoordinator)
            }
            .frame(minWidth: 1000, minHeight: 700)
            .background(.ultraThinMaterial)
            .clipped() // Prevent UI from moving outside bounds
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Time Block") {
                    // Create a new time block at the current time
                    let now = Date()
                    let _ = TimeBlock(
                        title: "New Task",
                        startTime: now,
                        duration: 3600, // 1 hour
                        energy: .daylight,
                        emoji: "📋"
                    )
                    // Note: Would need to access dataManager here in a real implementation
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Button("AI Assistant") {
                    // Focus on the AI action bar
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                Button("Export Day") {
                    // Trigger export functionality
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "DayPlanner_Export_\(Date().formatted(.iso8601.year().month().day()))"
                    panel.begin { result in
                        if result == .OK, let url = panel.url {
                            // Note: Would need to access dataManager here in a real implementation
                            print("Export to: \(url)")
                        }
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}


// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var mindNavigator: MindNavigationModel
    @EnvironmentObject private var onboarding: OnboardingCoordinator
    @State private var showingSettings = false
    @State private var showingAIDiagnostics = false
    @State private var selectedTab: AppTab = .calendar
    @State private var selectedDate = Date() // Shared date state across tabs
    @State private var showingSettingsPanel = false
    @State private var showingXPDisplay = false
    @State private var isHoveringSettings = false
    @State private var showingMindPanel = false // Control mind panel visibility
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top bar with XP/XXP and status
                TopBarView(
                    xp: dataManager.appState.userXP,
                    xxp: dataManager.appState.userXXP,
                    aiConnected: aiService.isConnected,
                    showingMindPanel: $showingMindPanel,
                    hideSettingsButton: showingSettingsPanel,
                    isHoveringSettings: $isHoveringSettings,
                    onSettingsTap: { 
                        showingSettings = true
                    },
                    onDiagnosticsTap: { showingAIDiagnostics = true }
                )
                
                
                // Main unified split view - Both calendar and mind visible simultaneously
                UnifiedSplitView(selectedDate: $selectedDate, showingMindPanel: $showingMindPanel)
                    .environmentObject(dataManager)
                    .environmentObject(aiService)
                
                // Floating Action Bar overlay
                Spacer()
            }
            
            // Darker overlay for settings hover - positioned at top to darken the tab section
            if isHoveringSettings {
                VStack {
                    HoverSettingsOverlay(
                        xp: dataManager.appState.userXP,
                        xxp: dataManager.appState.userXXP,
                        isVisible: isHoveringSettings,
                        onSettingsTap: {
                            showingSettings = true
                        }
                    )
                    Spacer()
                }
            }

            if dataManager.needsMoodPrompt {
                VStack {
                    MoodPromptBanner()
                        .padding(.top, 52)
                        .padding(.horizontal, 36)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            } else if let entry = dataManager.todaysMoodEntry {
                VStack {
                    HStack {
                        MoodStatusChip(entry: entry)
                            .padding(.leading, 24)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            
            // Bottom Mind Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            showingMindPanel.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Mind")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.bottom, 20)
            }
            
            OnboardingOverlay()
            
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(dataManager)
                .environmentObject(aiService)
        }
        .sheet(isPresented: $showingAIDiagnostics) {
            AIDiagnosticsView()
                .environmentObject(aiService)
        }
        .onTapGesture {
            if isHoveringSettings {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isHoveringSettings = false
                }
            }
        }
        .onAppear {
            setupAppAppearance()
            // Connect pattern engine to AI service
            aiService.setPatternEngine(dataManager.patternEngine)
            onboarding.startIfNeeded()
        }
        .onChange(of: mindNavigator.pendingDestination) { _, destination in
            guard destination != nil else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                showingMindPanel = true
            }
        }
    }
    
    private func setupAppAppearance() {
        // Configure the app's visual appearance
        if let window = NSApplication.shared.windows.first {
            window.isMovableByWindowBackground = false // Prevent window drag interference
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor.clear
        }
    }
}
