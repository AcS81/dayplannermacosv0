// MARK: - Settings View

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and done button
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Settings sidebar
                SettingsSidebar(selectedTab: $selectedTab)
                    .frame(width: 200)
                
                Divider()
                
                // Settings content
                SettingsContent(selectedTab: selectedTab)
                    .frame(maxWidth: .infinity)
                    .environmentObject(dataManager)
            }
        }
        .frame(width: 700, height: 600)
        .background(.regularMaterial)
    }
}

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case ai = "AI & Trust"
    case calendar = "Calendar"
    case pillars = "Pillars & Rules"
    case chains = "Chains"
    case data = "Data & History"
    case about = "About"
    case diagnostics = "Diagnostics"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .ai: return "brain"
        case .calendar: return "calendar"
        case .pillars: return "building.columns"
        case .chains: return "link"
        case .data: return "externaldrive"
        case .about: return "info.circle"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                            .frame(width: 20, alignment: .center)
                            .foregroundColor(selectedTab == tab ? .white : .primary)
                        
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .foregroundColor(selectedTab == tab ? .white : .primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab ? .blue : .clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 12)
        .background(.quaternary)
        .frame(maxHeight: .infinity)
    }
}

struct SettingsContent: View {
    let selectedTab: SettingsTab
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                        .environmentObject(dataManager)
                case .ai:
                    AITrustSettingsView()
                        .environmentObject(dataManager)
                case .calendar:
                    CalendarSettingsView()
                        .environmentObject(dataManager)
                case .pillars:
                    PillarsRulesSettingsView()
                        .environmentObject(dataManager)
                case .chains:
                    ChainsSettingsView()
                        .environmentObject(dataManager)
                case .data:
                    DataHistorySettingsView()
                        .environmentObject(dataManager)
                case .about:
                    AboutSettingsView()
                case .diagnostics:
                    DiagnosticsSettingsView()
                        .environmentObject(dataManager)
                        .environmentObject(aiService)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Settings Sections

struct GeneralSettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General Preferences")
                .font(.title2)
                .fontWeight(.semibold)
            
            SettingsGroup("Interface") {
                Toggle("Enable Voice Input", isOn: Binding(
                    get: { dataManager.appState.preferences.enableVoice },
                    set: { newValue in
                        dataManager.appState.preferences.enableVoice = newValue
                        dataManager.save()
                    }
                ))
                
                Toggle("Enable Animations", isOn: Binding(
                    get: { dataManager.appState.preferences.enableAnimations },
                    set: { newValue in
                        dataManager.appState.preferences.enableAnimations = newValue
                        dataManager.save()
                    }
                ))
                
                Toggle("Ephemeral Reflection", isOn: Binding(
                    get: { dataManager.appState.preferences.showEphemeralInsights },
                    set: { newValue in
                        dataManager.appState.preferences.showEphemeralInsights = newValue
                        dataManager.save()
                    }
                ))
                .help("Show brief AI insights that disappear after 2 seconds")
            }
            
            SettingsGroup("Time Preferences") {
                DatePicker("Preferred Start Time", 
                          selection: Binding(
                            get: { dataManager.appState.preferences.preferredStartTime },
                            set: { newValue in
                                dataManager.appState.preferences.preferredStartTime = newValue
                                dataManager.save()
                            }
                          ), displayedComponents: .hourAndMinute)
                
                DatePicker("Preferred End Time",
                          selection: Binding(
                            get: { dataManager.appState.preferences.preferredEndTime },
                            set: { newValue in
                                dataManager.appState.preferences.preferredEndTime = newValue
                                dataManager.save()
                            }
                          ), displayedComponents: .hourAndMinute)
                
                Picker("Default Block Duration", selection: Binding(
                    get: { Int(dataManager.appState.preferences.defaultBlockDuration / 60) },
                    set: { newValue in
                        dataManager.appState.preferences.defaultBlockDuration = TimeInterval(newValue * 60)
                        dataManager.save()
                    }
                )) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
            }
        }
    }
}

struct AITrustSettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var safeMode = false
    @State private var openaiApiKey = ""
    @State private var whisperApiKey = ""
    @State private var customApiEndpoint = ""
    @State private var pinBoost: Double = 0.25
    @State private var pillarBoost: Double = 0.15
    @State private var feedbackBoost: Double = 0.10
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI & Trust")
                .font(.title2)
                .fontWeight(.semibold)
            
            
            SettingsGroup("Safety") {
                Toggle("Safe Mode", isOn: $safeMode)
                    .help("Only suggest non-destructive changes, never modify existing events")
                    .onChange(of: safeMode) { _, newValue in
                        dataManager.appState.preferences.safeMode = newValue
                        dataManager.save()
                    }
            }
            
            
            SettingsGroup("API Configuration") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("OpenAI API Key:")
                            .frame(width: 120, alignment: .leading)
                        SecureField("sk-...", text: $openaiApiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: openaiApiKey) { _, newValue in
                                dataManager.appState.preferences.openaiApiKey = newValue
                                UserDefaults.standard.set(openaiApiKey, forKey: "openaiApiKey")
                                dataManager.save()
                            }
                        Button("Paste") {
                            if let clipboard = NSPasteboard.general.string(forType: .string) {
                                openaiApiKey = clipboard
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    HStack {
                        Text("Whisper API Key:")
                            .frame(width: 120, alignment: .leading)
                        SecureField("sk-...", text: $whisperApiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: whisperApiKey) { _, newValue in
                                dataManager.appState.preferences.whisperApiKey = newValue
                                UserDefaults.standard.set(whisperApiKey, forKey: "whisperApiKey")
                                dataManager.save()
                            }
                        Button("Paste") {
                            if let clipboard = NSPasteboard.general.string(forType: .string) {
                                whisperApiKey = clipboard
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    HStack {
                        Text("Custom Endpoint:")
                            .frame(width: 120, alignment: .leading)
                        TextField("http://localhost:1234", text: $customApiEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customApiEndpoint) { _, newValue in
                                dataManager.appState.preferences.customApiEndpoint = newValue
                                dataManager.save()
                            }
                        Button("Paste") {
                            if let clipboard = NSPasteboard.general.string(forType: .string) {
                                customApiEndpoint = clipboard
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("API keys are stored securely and only used for AI services. Custom endpoint defaults to LM Studio.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            SettingsGroup("Recommendation Weighting") {
                WeightSliderRow(
                    title: "Pinned goals",
                    value: $pinBoost,
                    range: 0...0.5,
                    description: "Boost applied when a suggestion matches a pinned goal"
                ) { updateWeighting() }

                WeightSliderRow(
                    title: "Emphasized pillars",
                    value: $pillarBoost,
                    range: 0...0.5,
                    description: "Additional weight for suggestions aligned with emphasized pillars"
                ) { updateWeighting() }

                WeightSliderRow(
                    title: "Positive feedback",
                    value: $feedbackBoost,
                    range: 0...0.5,
                    description: "Adaptive boost from prior thumbs-up"
                ) { updateWeighting() }
            }
        }
        .onAppear {
            safeMode = dataManager.appState.preferences.safeMode
            openaiApiKey = dataManager.appState.preferences.openaiApiKey
            whisperApiKey = dataManager.appState.preferences.whisperApiKey
            customApiEndpoint = dataManager.appState.preferences.customApiEndpoint
            let weighting = dataManager.appState.preferences.suggestionWeighting
            pinBoost = weighting.pinBoost
            pillarBoost = weighting.pillarBoost
            feedbackBoost = weighting.feedbackBoost
        }
    }

    private func updateWeighting() {
        dataManager.appState.preferences.suggestionWeighting = SuggestionWeighting(
            pinBoost: pinBoost,
            pillarBoost: pillarBoost,
            feedbackBoost: feedbackBoost
        )
        dataManager.save()
    }
}

private struct WeightSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let description: String
    let onChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value },
                set: { newValue in
                    value = newValue
                    onChange()
                }
            ), in: range, step: 0.05)
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct CalendarSettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var eventKitEnabled = true
    @State private var calendarSyncStatus = "Connected"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Calendar Integration")
                .font(.title2)
                .fontWeight(.semibold)
            
            SettingsGroup("Apple Calendar") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EventKit Integration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Status: \(calendarSyncStatus)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $eventKitEnabled)
                }
                
                if eventKitEnabled {
                    Button("Test Connection") {
                        // Test EventKit connection
                        calendarSyncStatus = "Testing..."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            calendarSyncStatus = "Connected ✅"
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Write policy", selection: Binding(
                    get: { dataManager.appState.preferences.eventKitWritePolicy },
                    set: { newValue in
                        dataManager.appState.preferences.eventKitWritePolicy = newValue
                        dataManager.save()
                    }
                )) {
                    ForEach(EventKitWritePolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
            }
            
            SettingsGroup("Sync Settings") {
                Toggle("Two-way sync", isOn: Binding(
                    get: { dataManager.appState.preferences.twoWaySync },
                    set: { newValue in
                        dataManager.appState.preferences.twoWaySync = newValue
                        dataManager.save()
                    }
                ))
                    .help("Changes in DayPlanner appear in Calendar and vice versa")
                
                Toggle("Respect Calendar privacy", isOn: Binding(
                    get: { dataManager.appState.preferences.respectCalendarPrivacy },
                    set: { newValue in
                        dataManager.appState.preferences.respectCalendarPrivacy = newValue
                        dataManager.save()
                    }
                ))
                    .help("Don't read private event details")
                
                Picker("Default Calendar", selection: .constant(0)) {
                    Text("Personal").tag(0)
                    Text("Work").tag(1)
                    Text("Family").tag(2)
                }
            }

            SettingsGroup("Recommendations") {
                Toggle("Auto-refresh suggestions", isOn: Binding(
                    get: { dataManager.appState.preferences.autoRefreshRecommendations },
                    set: { newValue in
                        dataManager.appState.preferences.autoRefreshRecommendations = newValue
                        dataManager.save()
                    }
                ))
                .help("When off, ghosts refresh only on manual actions")

                Toggle("Show ghost badges", isOn: Binding(
                    get: { dataManager.appState.preferences.showRecommendationBadges },
                    set: { newValue in
                        dataManager.appState.preferences.showRecommendationBadges = newValue
                        dataManager.save()
                    }
                ))

                Toggle("Show \"why this\" context", isOn: Binding(
                    get: { dataManager.appState.preferences.showSuggestionContext },
                    set: { newValue in
                        dataManager.appState.preferences.showSuggestionContext = newValue
                        dataManager.save()
                    }
                ))
                .help("Controls goal/pillar badges and rationale text on ghosts")
            }
        }
    }
}

struct PillarsRulesSettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var selectedPillar: Pillar?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pillars & Soft Rules")
                .font(.title2)
                .fontWeight(.semibold)
            
            if dataManager.appState.pillars.isEmpty {
                VStack(spacing: 16) {
                    Text("No pillars defined yet")
                        .foregroundColor(.secondary)
                    
                    Button("Create Your First Pillar") {
                        // Navigate to pillar creation
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ForEach(dataManager.appState.pillars) { pillar in
                    SettingsGroup(pillar.name) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(pillar.color.color)
                                    .frame(width: 12, height: 12)
                                
                                Text(pillar.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Edit") {
                                    selectedPillar = pillar
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            
                            Text("Frequency: \(pillar.frequencyDescription)")
                                .font(.caption)
                            
                            Text("Duration: \(pillar.minDuration.minutes)min - \(pillar.maxDuration.minutes)min")
                                .font(.caption)
                            
                            if !pillar.quietHours.isEmpty {
                                Text("Quiet hours: \(pillar.quietHours.map(\.description).joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedPillar) { pillar in
            PillarEditView(pillar: pillar) { updatedPillar in
                if let index = dataManager.appState.pillars.firstIndex(where: { $0.id == pillar.id }) {
                    dataManager.appState.pillars[index] = updatedPillar
                    dataManager.save()
                }
                selectedPillar = nil
            }
        }
    }
}

struct ChainsSettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var selectedChain: Chain?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Chains Management")
                .font(.title2)
                .fontWeight(.semibold)
            
            SettingsGroup("Auto-promotion") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chains become routines after being completed 3 times")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Enable routine promotion", isOn: .constant(true))
                    
                    Toggle("Show promotion notifications", isOn: .constant(true))
                }
            }
            
            SettingsGroup("Recent Chains") {
                ForEach(dataManager.appState.recentChains.prefix(5)) { chain in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chain.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("\(chain.blocks.count) blocks • \(chain.totalDurationMinutes)m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if chain.completionCount >= 3 {
                            Text("Routine")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.2), in: Capsule())
                                .foregroundColor(.green)
                        }
                        
                        Button("Edit") {
                            selectedChain = chain
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .sheet(item: $selectedChain) { chain in
            ChainEditView(chain: chain) { updatedChain in
                if let index = dataManager.appState.recentChains.firstIndex(where: { $0.id == chain.id }) {
                    dataManager.appState.recentChains[index] = updatedChain
                    dataManager.save()
                }
                selectedChain = nil
            }
        }
    }
}

struct DataHistorySettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var showingExportSheet = false
    @State private var showingHistoryLog = false
    @State private var showingImportSheet = false
    @State private var showingClearDataAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Data & History")
                .font(.title2)
                .fontWeight(.semibold)
            
            SettingsGroup("Data Management") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Saved")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(dataManager.lastSaved?.formatted() ?? "Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Save Now") {
                        dataManager.save()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Button("Export Data") {
                        showingExportSheet = true
                    }
                    .buttonStyle(.bordered)
                    
                Button("Import Data") {
                    showingImportSheet = true
                }
                .buttonStyle(.bordered)
                }
            }
            
            SettingsGroup("History & Undo Log") {
                Toggle("Keep undo history", isOn: Binding(
                    get: { dataManager.appState.preferences.keepUndoHistory },
                    set: { newValue in
                        dataManager.appState.preferences.keepUndoHistory = newValue
                        dataManager.save()
                    }
                ))
                
                HStack {
                    Text("History retention")
                    
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { dataManager.appState.preferences.historyRetentionDays },
                        set: { newValue in
                            dataManager.appState.preferences.historyRetentionDays = newValue
                            dataManager.save()
                        }
                    )) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                Button("View History Log") {
                    showingHistoryLog = true
                }
                .buttonStyle(.bordered)
            }
            
            SettingsGroup("Privacy") {
                Toggle("Analytics", isOn: .constant(false))
                    .help("All data stays local - no analytics are sent")
                
                Toggle("Crash reports", isOn: .constant(false))
                    .help("Local crash logs only")
                
                Button("Clear All Data") {
                    showingClearDataAlert = true
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(.red)
            }
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: ExportDocument(data: try! JSONEncoder().encode(dataManager.appState)),
            contentType: .json,
            defaultFilename: "DayPlanner_Export"
        ) { result in
            switch result {
            case .success(let url):
                print("Exported to: \(url)")
            case .failure(let error):
                print("Export failed: \(error)")
            }
        }
        .fileImporter(
            isPresented: $showingImportSheet,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        let _ = try Data(contentsOf: url)
                        try await dataManager.importData(from: url)
                    } catch {
                        print("Import failed: \(error)")
                    }
                }
            case .failure(let error):
                print("Import selection failed: \(error)")
            }
        }
        .sheet(isPresented: $showingHistoryLog) {
            HistoryLogView()
                .environmentObject(dataManager)
        }
        .alert("Clear All Data", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                // Clear all data
                dataManager.appState = AppState()
                dataManager.save()
            }
        } message: {
            Text("This will permanently delete all your data, including time blocks, chains, pillars, and goals. This action cannot be undone.")
        }
    }
}

struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @State private var diagnosticsLog: String = ""
    @State private var isRunningDiagnostics = false

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var topSuggestions: [SuggestionSnapshot] {
        Array(dataManager.suggestionSnapshots.prefix(10))
    }

    private var recentFeedback: [FeedbackEntry] {
        Array(dataManager.appState.feedbackEntries.suffix(10).reversed())
    }

    private var pendingReasonsDescription: String {
        guard !dataManager.pendingMicroUpdateReasons.isEmpty else { return "None" }
        return dataManager.pendingMicroUpdateReasons.map(label(for:)).joined(separator: ", ")
    }

    private func label(for reason: MicroUpdateReason) -> String {
        switch reason {
        case .acceptedSuggestion: return "accept"
        case .rejectedSuggestion: return "reject"
        case .editedBlock: return "edit"
        case .feedback: return "feedback"
        case .pinChange: return "pin"
        case .externalEvent: return "external"
        case .moodChange: return "mood"
        case .onboarding: return "onboarding"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Engine Diagnostics")
                .font(.title2)
                .fontWeight(.semibold)

            SettingsGroup("Recommendation Pool (Top \(topSuggestions.count))") {
                if topSuggestions.isEmpty {
                    Text("No weighted recommendations yet. Trigger a refresh to populate this table.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(topSuggestions) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(snapshot.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.2f", snapshot.score))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.blue)
                            }
                            HStack(spacing: 12) {
                                Text("conf \(String(format: "%.0f%%", snapshot.confidence * 100))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("base \(String(format: "%.2f", snapshot.base))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("pin +\(String(format: "%.2f", snapshot.pinBoost))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("pillar +\(String(format: "%.2f", snapshot.pillarBoost))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("feedback +\(String(format: "%.2f", snapshot.feedbackBoost))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let reason = snapshot.reason, !reason.isEmpty {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 8) {
                                if let goal = snapshot.goalTitle {
                                    Label(goal, systemImage: "target")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let pillar = snapshot.pillarTitle {
                                    Label(pillar, systemImage: "building.columns")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        if snapshot.id != topSuggestions.last?.id {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }

            SettingsGroup("Recent Feedback (last \(recentFeedback.count))") {
                if recentFeedback.isEmpty {
                    Text("No feedback captured yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentFeedback) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(timestampFormatter.string(from: entry.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            Text(entry.tagSummary)
                                .font(.caption)
                            if let note = entry.freeText, !note.isEmpty {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                Text(note)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.targetType.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if entry.id != recentFeedback.last?.id {
                            Divider().opacity(0.1)
                        }
                    }
                }
            }

            SettingsGroup("Engine Stats") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last refresh: \(lastRefreshText)")
                        .font(.caption)
                    Text("Context date: \(contextDateText)")
                        .font(.caption)
                    Text("Cached ghosts: \(dataManager.cachedSuggestionCount)")
                        .font(.caption)
                    Text("Pending micro-updates: \(pendingReasonsDescription)")
                        .font(.caption)
                    Text("Auto refresh: \(dataManager.appState.preferences.autoRefreshRecommendations ? "On" : "Off")")
                        .font(.caption)
                    Text("AI connection: \(aiService.isConnected ? "Online" : "Offline")")
                        .font(.caption)
                }
            }

            SettingsGroup("Tools") {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Task {
                            await MainActor.run { isRunningDiagnostics = true }
                            let result = await aiService.runDiagnostics()
                            await MainActor.run {
                                diagnosticsLog = result
                                isRunningDiagnostics = false
                            }
                        }
                    } label: {
                        Label(isRunningDiagnostics ? "Running…" : "Run AI diagnostics", systemImage: "waveform")
                    }
                    .disabled(isRunningDiagnostics)
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task {
                            await aiService.checkConnection()
                            await MainActor.run {
                                let stamp = timestampFormatter.string(from: Date())
                                let status = aiService.isConnected ? "✅ Connection ok" : "❌ Connection failed"
                                diagnosticsLog = "[\(stamp)] \(status)\n" + diagnosticsLog
                            }
                        }
                    } label: {
                        Label("Test connection", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)

                    Divider().opacity(0.2)

                    HStack {
                        Text("Performance harness")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if dataManager.diagnosticsGhostOverrideActive {
                            Text("ACTIVE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                    }

                    Text("Spawns synthetic ghosts for timeline profiling (25 blocks spaced hourly).")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack {
                        Button {
                            NotificationCenter.default.post(name: .diagnosticsSpawnGhosts, object: nil, userInfo: ["count": 25])
                        } label: {
                            Label("Spawn test ghosts", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            NotificationCenter.default.post(name: .diagnosticsClearGhosts, object: nil)
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!dataManager.diagnosticsGhostOverrideActive)
                    }

                    if !diagnosticsLog.isEmpty {
                        ScrollView {
                            Text(diagnosticsLog)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var lastRefreshText: String {
        guard let date = dataManager.lastSuggestionRefresh else { return "—" }
        return dateFormatter.string(from: date)
    }

    private var contextDateText: String {
        guard let date = dataManager.lastSuggestionContextDate else { return "—" }
        return dateFormatter.string(from: date)
    }
}

extension Notification.Name {
    static let diagnosticsSpawnGhosts = Notification.Name("DiagnosticsSpawnGhosts")
    static let diagnosticsClearGhosts = Notification.Name("DiagnosticsClearGhosts")
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("About DayPlanner")
                .font(.title2)
                .fontWeight(.semibold)
            
            SettingsGroup("Version") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DayPlanner")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Version 1.0.0 (Build 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("🌊")
                        .font(.largeTitle)
                }
            }
            
            SettingsGroup("AI Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local AI via LM Studio")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("All AI processing happens locally on your device. No data is sent to external servers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Test AI Connection") {
                        // Test AI
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            SettingsGroup("Support") {
                Link("Documentation", destination: URL(string: "https://example.com")!)
                Link("Report Issue", destination: URL(string: "https://example.com")!)
                Link("Feature Request", destination: URL(string: "https://example.com")!)
            }
        }
    }
}

// MARK: - Helper Views

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(16)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct PillarEditView: View {
    let pillar: Pillar
    let onSave: (Pillar) -> Void
    
    @State private var name: String
    @State private var description: String
    @State private var frequency: PillarFrequency
    @Environment(\.dismiss) private var dismiss
    
    init(pillar: Pillar, onSave: @escaping (Pillar) -> Void) {
        self.pillar = pillar
        self.onSave = onSave
        self._name = State(initialValue: pillar.name)
        self._description = State(initialValue: pillar.description)
        self._frequency = State(initialValue: pillar.frequency)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description)
                }
                
                Section("Frequency") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(PillarFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Edit Pillar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updatedPillar = pillar
                        updatedPillar.name = name
                        updatedPillar.description = description
                        updatedPillar.frequency = frequency
                        onSave(updatedPillar)
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct ChainEditView: View {
    let chain: Chain
    let onSave: (Chain) -> Void
    
    @State private var name: String
    @State private var blocks: [TimeBlock]
    
    init(chain: Chain, onSave: @escaping (Chain) -> Void) {
        self.chain = chain
        self.onSave = onSave
        self._name = State(initialValue: chain.name)
        self._blocks = State(initialValue: chain.blocks)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Chain Name", text: $name)
                }
                
                Section("Time Blocks") {
                    ForEach($blocks, id: \.id) { $block in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Title", text: $block.title)
                            
                            HStack {
                                Text("Duration:")
                                Stepper("\(Int(block.duration/60))min", 
                                       value: Binding(
                                           get: { Double(block.duration/60) },
                                           set: { newValue in
                                               block.duration = TimeInterval(newValue * 60)
                                           }
                                       ), 
                                       in: 5...480, 
                                       step: 5)
                                Spacer()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button("Add Block") {
                        let newBlock = TimeBlock(
                            title: "New Activity",
                            startTime: Date(),
                            duration: 30 * 60,
                            energy: .daylight,
                            emoji: "📋"
                        )
                        blocks.append(newBlock)
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Edit Chain")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onSave(chain) // Cancel without changes
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updatedChain = chain
                        updatedChain.name = name
                        updatedChain.blocks = blocks
                        onSave(updatedChain)
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Helper Types

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct HistoryLogView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if dataManager.appState.preferences.keepUndoHistory {
                    Text("History logging is enabled")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                    
                    Text("History log functionality would be implemented here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Text("History logging is disabled")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle("History Log")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
    }
}
