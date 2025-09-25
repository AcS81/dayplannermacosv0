//
//  Storage.swift
//  DayPlanner
//
//  Simple JSON-based local storage for liquid glass data
//

import Foundation
import SwiftUI
import Combine
import EventKit
import CoreLocation
import Speech
import AVFoundation

@MainActor
protocol OnboardingProgressDelegate: AnyObject {
    func onboardingDidCaptureMood(_ entry: MoodEntry)
    func onboardingDidCreateBlock(_ block: TimeBlock, acceptedSuggestion: Bool)
    func onboardingDidCreatePillar(_ pillar: Pillar)
    func onboardingDidCreateGoal(_ goal: Goal)
    func onboardingDidSubmitFeedback(_ entry: FeedbackEntry)
}

enum MicroUpdateReason: Hashable {
    case acceptedSuggestion
    case rejectedSuggestion
    case editedBlock
    case feedback
    case pinChange
    case externalEvent
    case moodChange
    case onboarding
}

// MARK: - Shared DateFormatters

/// Shared DateFormatter instances to avoid recreation overhead
private struct DateFormatters {
    static let exportFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
    
    static let backupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Simple, local-first data manager
@MainActor
class AppDataManager: ObservableObject {
    @Published var appState = AppState()
    @Published var isLoading = false
    @Published var lastSaved: Date?
    
    // Background actor for heavy I/O operations
    private let persistenceActor = PersistenceActor()
    
    // EventKit integration
    @Published var eventKitService = EventKitService()
    
    // Weather integration
    @Published var weatherService = WeatherService()
    
    // Intelligence and analysis
    @Published var vibeAnalyzer = VibeAnalyzer()
    @Published var patternEngine = PatternLearningEngine()
    weak var onboardingDelegate: OnboardingProgressDelegate?
    @Published private(set) var todaysMoodEntry: MoodEntry?
    @Published var needsMoodPrompt = true
    
    private var lastMoodPromptShownAt: Date?
    private var cachedLLMSuggestions: [Suggestion] = []
    private var lastSuggestionContextDate: Date?
    private var lastLLMRefresh: Date?
    private var pendingMicroUpdateReasons: [MicroUpdateReason] = []
    private var cancellables: Set<AnyCancellable> = []

    func requestMicroUpdate(_ reason: MicroUpdateReason) {
        if !pendingMicroUpdateReasons.contains(reason) {
            pendingMicroUpdateReasons.append(reason)
        }
    }

    func consumePendingMicroUpdate() -> MicroUpdateReason? {
        guard !pendingMicroUpdateReasons.isEmpty else { return nil }
        return pendingMicroUpdateReasons.removeFirst()
    }

    func consumeMicroUpdate(reason: MicroUpdateReason) {
        if let index = pendingMicroUpdateReasons.firstIndex(of: reason) {
            pendingMicroUpdateReasons.remove(at: index)
        }
    }
    
    // Debug tracking
    private var loggedAmbiguousGoalSuggestions: Set<UUID> = []
    private var loggedAmbiguousPillarSuggestions: Set<UUID> = []
    
    // MARK: - Initialization
    
    init() {
        patternEngine = PatternLearningEngine(dataManager: self)
        load()
        
        // Auto-save every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                self.save()
            }
        }

        eventKitService.$lastChangeToken
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncExternalEvents(for: self.appState.currentDay.date)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Save & Load
    
    func save() {
        Task {
            isLoading = true
            let result = await persistenceActor.saveAppState(appState)
            
            await MainActor.run {
                if result.success, let saveTime = result.lastSaved {
                    lastSaved = saveTime
                }
                isLoading = false
            }
        }
    }
    
    func load() {
        Task {
            isLoading = true
            
            if let loadedState = await persistenceActor.loadAppState() {
                await MainActor.run {
                    appState = loadedState
                    ensureTodayExists()
                    ensureGoalGraphsExist()
                    updateTodaysMoodEntry()
                    isLoading = false
                }
            } else {
                // First launch or load failed - create sample data
                await MainActor.run {
                    createSampleData()
                    updateTodaysMoodEntry()
                    isLoading = false
                }
                save() // Save the sample data
            }
        }
    }
    
    // MARK: - Mood Capture

    func captureMood(_ mood: GlassMood, source: MoodCaptureSource = .launchPrompt) {
        let entry = MoodEntry(mood: mood, source: source)
        appState.moodEntries.append(entry)
        appState.currentDay.mood = mood
        todaysMoodEntry = entry
        needsMoodPrompt = false
        lastMoodPromptShownAt = nil
        onboardingDelegate?.onboardingDidCaptureMood(entry)
        updateOnboardingState { state in
            state.didCaptureMood = true
            if state.phase == .notStarted || state.phase == .mood {
                state.phase = .createEvent
                state.startedAt = state.startedAt ?? Date()
            }
        }
        recordMoodBehavior(entry)
        requestMicroUpdate(.moodChange)
        save()
    }

    func skipMoodPrompt() {
        needsMoodPrompt = false
        lastMoodPromptShownAt = Date()
    }

    private func updateTodaysMoodEntry(reference date: Date = Date()) {
        let calendar = Calendar.current
        todaysMoodEntry = appState.moodEntries.last(where: { calendar.isDate($0.capturedAt, inSameDayAs: date) })
        if let entry = todaysMoodEntry {
            appState.currentDay.mood = entry.mood
            needsMoodPrompt = false
            lastMoodPromptShownAt = nil
        } else if lastMoodPromptShownAt == nil {
            needsMoodPrompt = true
        }
    }

    private func recordMoodBehavior(_ entry: MoodEntry) {
        let dayData = DayData(
            id: appState.currentDay.id.uuidString,
            date: appState.currentDay.date,
            mood: entry.mood,
            blockCount: appState.currentDay.blocks.count,
            completionRate: appState.currentDay.completionPercentage
        )
        let behaviorEvent = BehaviorEvent(
            .moodLogged(entry),
            context: EventContext(mood: entry.mood)
        )
        patternEngine.recordBehavior(behaviorEvent)
        let dayEvent = BehaviorEvent(.dayReviewed(dayData, rating: 3), context: EventContext(mood: entry.mood))
        patternEngine.recordBehavior(dayEvent)
    }

    private func updateOnboardingState(_ transform: (inout OnboardingState) -> Void) {
        transform(&appState.onboarding)
    }

    private func syncExternalEvents(for date: Date) {
        guard appState.preferences.eventKitEnabled else { return }
        let startOfDay = Calendar.current.startOfDay(for: date)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let events = eventKitService.fetchEvents(start: startOfDay, end: endOfDay)
        mergeExternalEvents(events, dayStart: startOfDay, dayEnd: endOfDay)
    }

    private func mergeExternalEvents(_ events: [EKEvent], dayStart: Date, dayEnd: Date) {
        guard !events.isEmpty else {
            // Remove any lingering external blocks if no events exist
            appState.currentDay.blocks.removeAll { block in
                block.origin == .external
            }
            return
        }

        let identifiers = Set(events.compactMap { $0.eventIdentifier })

        // Remove deleted external events
        appState.currentDay.blocks.removeAll { block in
            guard block.origin == .external else { return false }
            if let externalId = block.externalEventId {
                return !identifiers.contains(externalId)
            }
            return true
        }

        // Update or insert events
        for event in events {
            guard let identifier = event.eventIdentifier else { continue }
            if let index = appState.currentDay.blocks.firstIndex(where: { $0.externalEventId == identifier }) {
                var block = appState.currentDay.blocks[index]
                let originalStart = block.startTime
                let originalDuration = block.duration
                let originalTitle = block.title
                block.startTime = event.startDate
                block.duration = max(300, event.endDate.timeIntervalSince(event.startDate))
                block.title = event.title
                block.notes = event.notes ?? block.notes
                block.externalLastModified = event.lastModifiedDate ?? Date()
                block.confirmationState = .confirmed
                block.glassState = .solid
                appState.currentDay.blocks[index] = block
                if originalStart != block.startTime || originalDuration != block.duration || originalTitle != block.title {
                    recordExternalChange(for: block)
                }
            } else {
                let block = TimeBlock(
                    title: event.title,
                    startTime: event.startDate,
                    duration: max(300, event.endDate.timeIntervalSince(event.startDate)),
                    energy: energyEstimate(for: event.startDate),
                    emoji: "📅",
                    glassState: .solid,
                    position: .zero,
                    relatedGoalId: nil,
                    relatedGoalTitle: nil,
                    relatedPillarId: nil,
                    relatedPillarTitle: nil,
                    suggestionId: nil,
                    suggestionReason: "External calendar",
                    suggestionWeight: nil,
                    suggestionConfidence: nil,
                    externalEventId: identifier,
                    externalLastModified: event.lastModifiedDate ?? Date(),
                    origin: .external,
                    notes: event.notes,
                    confirmationState: .confirmed
                )
                appState.addBlock(block)
                requestMicroUpdate(.externalEvent)
            }
        }
        appState.currentDay.blocks.sort { $0.startTime < $1.startTime }
        save()
    }

    private func recordExternalChange(for block: TimeBlock) {
        let data = TimeBlockData(
            id: block.id.uuidString,
            title: block.title,
            emoji: block.emoji,
            energy: block.energy,
            duration: block.duration,
            period: block.period
        )
        let event = BehaviorEvent(
            .blockModified(data, changes: "external_edit"),
            context: EventContext(energyLevel: block.energy, mood: appState.currentDay.mood)
        )
        patternEngine.recordBehavior(event)
        requestMicroUpdate(.externalEvent)
    }

    private func energyEstimate(for startDate: Date) -> EnergyType {
        let hour = Calendar.current.component(.hour, from: startDate)
        switch hour {
        case 5..<11: return .sunrise
        case 11..<18: return .daylight
        default: return .moonlight
        }
    }

    private func attachEventKitIdentifier(_ blockId: UUID, identifier: String, lastModified: Date) {
        if let index = appState.currentDay.blocks.firstIndex(where: { $0.id == blockId }) {
            appState.currentDay.blocks[index].externalEventId = identifier
            appState.currentDay.blocks[index].externalLastModified = lastModified
            save()
        }
    }

    // MARK: - Time Block Operations
    
    func addTimeBlock(_ block: TimeBlock) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            appState.addBlock(block)
        }
        
        // Record for pattern learning
        let creationSource: String
        switch block.origin {
        case .suggestion: creationSource = "ai_suggestion"
        case .onboarding: creationSource = "onboarding"
        case .external: creationSource = "eventkit"
        case .chain: creationSource = "chain"
        case .aiGenerated: creationSource = "ai_generated"
        case .manual: creationSource = "manual"
        }
        recordTimeBlockCreation(block, source: creationSource)
        
        // Award XXP for productive actions
        if block.energy == .sunrise || block.energy == .daylight {
            appState.addXXP(Int(block.duration / 60), reason: "Added productive time block")
        }
        
        refreshPastBlocks()
        save()
        if block.origin != .external {
            onboardingDelegate?.onboardingDidCreateBlock(block, acceptedSuggestion: block.origin == .suggestion)
        }
    }
    
    func updateTimeBlock(_ block: TimeBlock) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            appState.updateBlock(block)
        }
        refreshPastBlocks()
        requestMicroUpdate(.editedBlock)
        save()
    }
    
    func removeTimeBlock(_ blockId: UUID) {
        withAnimation(.easeOut(duration: 0.4)) {
            appState.removeBlock(blockId)
        }
        save()
    }
    
    func moveTimeBlock(_ block: TimeBlock, to newStartTime: Date) {
        var updatedBlock = block
        updatedBlock.startTime = newStartTime
        updateTimeBlock(updatedBlock)
    }
    
    // MARK: - Scheduling Preferences

    func isGoalPinned(_ goalId: UUID) -> Bool {
        appState.pinnedGoalIds.contains(goalId)
    }

    func toggleGoalPin(_ goalId: UUID) {
        if appState.pinnedGoalIds.contains(goalId) {
            appState.pinnedGoalIds.remove(goalId)
        } else {
            appState.pinnedGoalIds.insert(goalId)
        }
        save()
        requestMicroUpdate(.pinChange)
    }

    func isPillarEmphasized(_ pillarId: UUID) -> Bool {
        appState.emphasizedPillarIds.contains(pillarId)
    }

    func togglePillarEmphasis(_ pillarId: UUID) {
        if appState.emphasizedPillarIds.contains(pillarId) {
            appState.emphasizedPillarIds.remove(pillarId)
        } else {
            appState.emphasizedPillarIds.insert(pillarId)
        }
        save()
        requestMicroUpdate(.pinChange)
    }

    // MARK: - Suggestion Weighting

    func produceSuggestions(
        context: DayContext,
        reason: MicroUpdateReason?,
        forceLLM: Bool,
        aiService: AIService
    ) async -> [Suggestion] {
        if shouldRefreshSuggestions(for: context, reason: reason, forceLLM: forceLLM) {
            do {
                cachedLLMSuggestions = try await aiService.generateSuggestions(for: context)
            } catch {
                cachedLLMSuggestions = AIService.mockSuggestions()
            }
            lastLLMRefresh = Date()
            lastSuggestionContextDate = context.date
        }
        return cachedLLMSuggestions
    }

    private func shouldRefreshSuggestions(for context: DayContext, reason: MicroUpdateReason?, forceLLM: Bool) -> Bool {
        if forceLLM { return true }
        if cachedLLMSuggestions.isEmpty { return true }
        if let lastContextDate = lastSuggestionContextDate,
           !Calendar.current.isDate(lastContextDate, inSameDayAs: context.date) {
            return true
        }
        if let reason, reasonRequiresLLM(reason) {
            return true
        }
        if let lastRefresh = lastLLMRefresh, Date().timeIntervalSince(lastRefresh) > 900 {
            return true
        }
        return false
    }

    private func reasonRequiresLLM(_ reason: MicroUpdateReason) -> Bool {
        switch reason {
        case .acceptedSuggestion,
             .rejectedSuggestion,
             .editedBlock,
             .feedback,
             .pinChange,
             .externalEvent,
             .moodChange,
             .onboarding:
            return true
        }
    }

    func prioritizeSuggestions(_ suggestions: [Suggestion]) -> [Suggestion] {
        guard !suggestions.isEmpty else { return [] }
        let weighting = appState.preferences.suggestionWeighting
        let annotated = suggestions.map { suggestion -> WeightedSuggestion in
            let baseScore = suggestion.weight ?? 0.0
            let goalInfo = goalBoost(for: suggestion, weighting: weighting)
            let pillarInfo = pillarBoost(for: suggestion, weighting: weighting)
            let feedbackInfo = feedbackBoost(for: suggestion, weighting: weighting)
            let totalBoost = goalInfo.boost + pillarInfo.boost + feedbackInfo.boost
            let finalScore = (baseScore + totalBoost) * suggestion.confidence
            var updated = suggestion
            updated.weight = finalScore
            updated.reason = combinedReason(
                base: suggestion.reason ?? suggestion.explanation,
                additions: [goalInfo.annotation, pillarInfo.annotation, feedbackInfo.annotation]
            )
            return WeightedSuggestion(
                suggestion: updated,
                base: baseScore,
                pinBoost: goalInfo.boost,
                pillarBoost: pillarInfo.boost,
                feedbackBoost: feedbackInfo.boost,
                confidence: suggestion.confidence
            )
        }
        let sorted = annotated.sorted { ($0.suggestion.weight ?? 0) > ($1.suggestion.weight ?? 0) }
        debugLogTopSuggestions(sorted)
        return sorted.map { $0.suggestion }
    }

    private func goalBoost(for suggestion: Suggestion, weighting: SuggestionWeighting) -> (boost: Double, annotation: String?) {
        guard let goalId = suggestion.relatedGoalId, appState.pinnedGoalIds.contains(goalId) else {
            return (0, nil)
        }
        let title = suggestion.relatedGoalTitle ?? appState.goals.first(where: { $0.id == goalId })?.title
        let short = title?.badgeShortTitle(maxLength: 18)
        return (weighting.pinBoost, short.map { "↑ pinned: \($0)" })
    }

    private func pillarBoost(for suggestion: Suggestion, weighting: SuggestionWeighting) -> (boost: Double, annotation: String?) {
        guard let pillarId = suggestion.relatedPillarId, appState.emphasizedPillarIds.contains(pillarId) else {
            return (0, nil)
        }
        let name = suggestion.relatedPillarTitle ?? appState.pillars.first(where: { $0.id == pillarId })?.name
        let short = name?.badgeShortTitle(maxLength: 18)
        return (weighting.pillarBoost, short.map { "↑ pillar: \($0)" })
    }

    private func feedbackBoost(for suggestion: Suggestion, weighting: SuggestionWeighting) -> (boost: Double, annotation: String?) {
        var labels: [String] = []
        var strengths: [Double] = []
        if let goalId = suggestion.relatedGoalId,
           let stats = appState.goalFeedbackStats[goalId],
           stats.hasPositiveSignal {
            let intensity = max(0.0, stats.netScore)
            strengths.append(min(1.0, intensity))
            if let title = suggestion.relatedGoalTitle ?? appState.goals.first(where: { $0.id == goalId })?.title {
                labels.append(title.badgeShortTitle(maxLength: 18))
            }
        }
        if let pillarId = suggestion.relatedPillarId,
           let stats = appState.pillarFeedbackStats[pillarId],
           stats.hasPositiveSignal {
            let intensity = max(0.0, stats.netScore)
            strengths.append(min(1.0, intensity))
            if let name = suggestion.relatedPillarTitle ?? appState.pillars.first(where: { $0.id == pillarId })?.name {
                labels.append(name.badgeShortTitle(maxLength: 18))
            }
        }
        guard !strengths.isEmpty else { return (0, nil) }
        let averageStrength = strengths.reduce(0, +) / Double(strengths.count)
        let boost = weighting.feedbackBoost * averageStrength
        let summary = labels.isEmpty ? "↑ feedback" : "↑ feedback: \(labels.joined(separator: ", "))"
        return (boost, summary)
    }

    private func combinedReason(base: String?, additions: [String?]) -> String? {
        let trimmedBase = base?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extras = additions.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if trimmedBase.isEmpty && extras.isEmpty { return nil }
        if extras.isEmpty { return trimmedBase }
        if trimmedBase.isEmpty { return extras.joined(separator: " • ") }
        return ([trimmedBase] + extras).joined(separator: " • ")
    }

    private func debugLogTopSuggestions(_ items: [WeightedSuggestion]) {
        guard !items.isEmpty else { return }
        let top = items.prefix(5)
        print("🔍 Suggestion weighting snapshot")
        for (index, entry) in top.enumerated() {
            let score = entry.suggestion.weight ?? 0
            let formatted = String(format: "%.2f", score)
            let base = String(format: "%.2f", entry.base)
            let pin = String(format: "%.2f", entry.pinBoost)
            let pillar = String(format: "%.2f", entry.pillarBoost)
            let feedback = String(format: "%.2f", entry.feedbackBoost)
            let confidence = String(format: "%.2f", entry.confidence)
            print("  \(index + 1). \(entry.suggestion.title) → score \(formatted) = (base \(base) + pin \(pin) + pillar \(pillar) + feedback \(feedback)) × conf \(confidence)")
        }
        print("🔍——")
    }

    private struct WeightedSuggestion {
        var suggestion: Suggestion
        var base: Double
        var pinBoost: Double
        var pillarBoost: Double
        var feedbackBoost: Double
        var confidence: Double
    }
    
    // MARK: - Confirmation & Records
    
    func refreshPastBlocks(referenceDate: Date = Date()) {
        var didUpdate = false
        for index in appState.currentDay.blocks.indices {
            var block = appState.currentDay.blocks[index]
            if block.endTime <= referenceDate && block.confirmationState == .scheduled {
                block.confirmationState = .unconfirmed
                if block.glassState == .solid {
                    block.glassState = .liquid
                }
                if block.glassState == .crystal {
                    block.glassState = .mist
                }
                appState.currentDay.blocks[index] = block
                didUpdate = true
            } else if block.startTime > referenceDate && block.confirmationState == .unconfirmed {
                block.confirmationState = .scheduled
                appState.currentDay.blocks[index] = block
                didUpdate = true
            }
        }
        if didUpdate {
            save()
        }
    }
    
    var unconfirmedBlocks: [TimeBlock] {
        appState.currentDay.blocks
            .filter { $0.confirmationState == .unconfirmed }
            .sorted { $0.startTime < $1.startTime }
    }
    
    func nextUnconfirmedBlock() -> TimeBlock? {
        unconfirmedBlocks.first
    }
    
    func confirmBlock(_ blockId: UUID, notes: String? = nil) {
        guard let index = appState.currentDay.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        var block = appState.currentDay.blocks[index]
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNotes, !trimmedNotes.isEmpty {
            block.notes = trimmedNotes
        }
        block.confirmationState = .confirmed
        block.glassState = .solid
        appState.currentDay.blocks[index] = block
        
        let record = Record(
            blockId: block.id,
            title: block.title,
            startTime: block.startTime,
            endTime: block.endTime,
            notes: block.notes,
            energy: block.energy,
            emoji: block.emoji,
            confirmedAt: Date()
        )
        appState.records.append(record)
        appState.todoItems.removeAll { $0.followUp?.blockId == block.id }
        save()
    }
    
    func undoRecord(_ recordId: UUID) {
        guard let index = appState.records.firstIndex(where: { $0.id == recordId }) else { return }
        let record = appState.records[index]
        guard Date().timeIntervalSince(record.confirmedAt) <= 86_400 else { return }
        if let blockIndex = appState.currentDay.blocks.firstIndex(where: { $0.id == record.blockId }) {
            var block = appState.currentDay.blocks[blockIndex]
            block.confirmationState = .unconfirmed
            if block.glassState == .solid {
                block.glassState = .liquid
            }
            appState.currentDay.blocks[blockIndex] = block
        }
        appState.records.remove(at: index)
        save()
    }
    
    func requeueBlock(_ blockId: UUID, notes: String? = nil) {
        guard let index = appState.currentDay.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        var block = appState.currentDay.blocks.remove(at: index)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNotes, !trimmedNotes.isEmpty {
            block.notes = trimmedNotes
        }
        let followUp = FollowUpMetadata(
            blockId: block.id,
            originalTitle: block.title,
            startTime: block.startTime,
            endTime: block.endTime,
            energy: block.energy,
            emoji: block.emoji,
            notesSnapshot: block.notes,
            capturedAt: Date()
        )
        let item = TodoItem(
            title: block.title,
            dueDate: nil,
            isCompleted: false,
            createdDate: Date(),
            notes: trimmedNotes ?? block.notes,
            followUp: followUp
        )
        appState.todoItems.removeAll { $0.followUp?.blockId == block.id }
        appState.todoItems.insert(item, at: 0)
        save()
    }
    
    // MARK: - Chain Operations
    
    func addChain(_ chain: Chain) {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            appState.recentChains.append(chain)
            
            // Keep only recent chains (max 20)
            if appState.recentChains.count > 20 {
                appState.recentChains.removeFirst()
            }
        }
        save()
    }
    
    // MARK: - Pillar Operations
    
    func addPillar(_ pillar: Pillar) {
        appState.pillars.append(pillar)
        save()
        
        // Award XP for creating a pillar
        appState.addXP(15, reason: "Created pillar: \(pillar.name)")
        
        onboardingDelegate?.onboardingDidCreatePillar(pillar)
    }
    
    func updatePillar(_ pillar: Pillar) {
        if let index = appState.pillars.firstIndex(where: { $0.id == pillar.id }) {
            let oldPillar = appState.pillars[index]
            appState.pillars[index] = pillar
            
            // If emoji changed, propagate to related items
            if oldPillar.emoji != pillar.emoji {
                propagateEmojiFromPillar(pillar)
            }
            save()
        }
    }
    
    func removePillar(_ pillarId: UUID) {
        appState.pillars.removeAll { $0.id == pillarId }
        appState.emphasizedPillarIds.remove(pillarId)
        appState.pillarFeedbackStats.removeValue(forKey: pillarId)
        save()
    }
    
    
    /// Create enhanced context with pillar guidance for AI decisions
    func createEnhancedContext(date: Date = Date()) -> DayContext {
        let principleGuidance = appState.pillars
            .filter { $0.isPrinciple }
            .map { $0.aiGuidanceText }
        
        let actionablePillars = appState.pillars
            .filter { $0.isActionable }
        
        return DayContext(
            date: date,
            existingBlocks: appState.currentDay.blocks,
            currentEnergy: .daylight,
            preferredEmojis: ["🌊"],
            availableTime: 3600,
            mood: appState.currentDay.mood,
            weatherContext: weatherService.getWeatherContext(),
            pillarGuidance: principleGuidance,
            actionablePillars: actionablePillars
        )
    }
    
    private func findAvailableSlots(for pillar: Pillar) -> [TimeSlot] {
        var availableSlots: [TimeSlot] = []
        let calendar = Calendar.current
        let today = Date()
        
        // Check today and next few days
        for dayOffset in 0..<3 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            
            // Get existing blocks for that day
            let existingBlocks = appState.currentDay.blocks
            
            // Check each preferred time window
            for timeWindow in pillar.preferredTimeWindows {
                guard let windowStart = calendar.date(bySettingHour: timeWindow.startHour, minute: timeWindow.startMinute, second: 0, of: targetDate),
                      let windowEnd = calendar.date(bySettingHour: timeWindow.endHour, minute: timeWindow.endMinute, second: 0, of: targetDate) else { continue }
                
                // Find gaps within this time window
                let gapsInWindow = findGaps(in: DateInterval(start: windowStart, end: windowEnd), existingBlocks: existingBlocks)
                
                for gap in gapsInWindow {
                    if gap.duration >= pillar.minDuration {
                        availableSlots.append(TimeSlot(
                            startTime: gap.start,
                            endTime: gap.end,
                            duration: gap.duration
                        ))
                    }
                }
            }
        }
        
        return availableSlots
    }
    
    private func findGaps(in interval: DateInterval, existingBlocks: [TimeBlock]) -> [DateInterval] {
        let blocksInInterval = existingBlocks.filter { block in
            block.startTime < interval.end && block.endTime > interval.start
        }.sorted { $0.startTime < $1.startTime }
        
        var gaps: [DateInterval] = []
        var currentTime = interval.start
        
        for block in blocksInInterval {
            if currentTime < block.startTime {
                gaps.append(DateInterval(start: currentTime, end: block.startTime))
            }
            currentTime = max(currentTime, block.endTime)
        }
        
        if currentTime < interval.end {
            gaps.append(DateInterval(start: currentTime, end: interval.end))
        }
        
        return gaps
    }
    
    struct TimeSlot {
        let startTime: Date
        let endTime: Date
        let duration: TimeInterval
    }
    
    func markChainCompleted(_ chainId: UUID) {
        guard let index = appState.recentChains.firstIndex(where: { $0.id == chainId }) else { return }
        
        appState.recentChains[index].completionCount += 1
        appState.recentChains[index].lastCompletedAt = Date()
        appState.recentChains[index].completionHistory.append(Date())
        
        // Check if this chain can be promoted to routine
        let chain = appState.recentChains[index]
        if chain.canBePromotedToRoutine {
            promptRoutinePromotion(for: chain)
        }
        
        save()
    }
    
    private func promptRoutinePromotion(for chain: Chain) {
        // Mark that we've shown the prompt to avoid spam
        if let index = appState.recentChains.firstIndex(where: { $0.id == chain.id }) {
            appState.recentChains[index].routinePromptShown = true
        }
        
        // In a real app, this would show UI to ask user
        // For now, we'll auto-promote with default settings
        promoteChainToRoutine(chain)
    }
    
    func promoteChainToRoutine(_ chain: Chain) {
        let routine = Routine(
            chainId: chain.id,
            name: "\(chain.name) Routine",
            adoptionScore: 0.7, // Start with good adoption since it was completed 3 times
            scheduleRules: inferScheduleRules(from: chain)
        )
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            appState.routines.append(routine)
        }
        
        // Award XP for establishing a routine
        appState.addXP(10, reason: "Established routine: \(routine.name)")
        
        save()
        
        print("✅ Promoted chain '\(chain.name)' to routine")
    }
    
    func dismissRoutinePromotion(for chainId: UUID) {
        if let index = appState.recentChains.firstIndex(where: { $0.id == chainId }) {
            appState.recentChains[index].routinePromptShown = true
        }
        save()
    }
    
    private func inferScheduleRules(from chain: Chain) -> [RoutineScheduleRule] {
        // Create a simple daily schedule rule based on completion history
        // In a real app, this could be more sophisticated
        
        if let lastCompleted = chain.lastCompletedAt {
            let hour = Calendar.current.component(.hour, from: lastCompleted)
            let timeWindow = TimeWindow(
                startHour: max(0, hour - 1),
                startMinute: 0,
                endHour: min(23, hour + 1),
                endMinute: 59
            )
            
            let rule = RoutineScheduleRule(
                timeOfDay: timeWindow,
                frequency: .daily,
                conditions: []
            )
            
            return [rule]
        }
        
        return []
    }
    
    func applyChain(_ chain: Chain, startingAt time: Date) {
        var currentTime = time
        var chainBlocks: [TimeBlock] = []
        
        // Create all chain blocks with proper time slots and relationships
        for chainBlock in chain.blocks {
            let newBlock = TimeBlock(
                title: chainBlock.title,
                startTime: currentTime,
                duration: chainBlock.duration,
                energy: chainBlock.energy,
                emoji: chainBlock.emoji,
                glassState: .solid,
                relatedGoalId: chain.relatedGoalId,
                relatedPillarId: chain.relatedPillarId
            )
            
            chainBlocks.append(newBlock)
            currentTime = newBlock.endTime.addingTimeInterval(300) // 5-minute buffer
        }
        
        // Record chain application for pattern learning
        recordChainApplication(chain)
        
        // Add all blocks from the chain
        for block in chainBlocks {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appState.addBlock(block)
            }
            
            // Record each block creation
            recordTimeBlockCreation(block, source: "chain_application")
        }
        
        // Award XP for chain usage
        appState.addXP(5, reason: "Applied chain: \(chain.name)")
        appState.addXXP(chain.totalDurationMinutes, reason: "Chain activities")
        
        // Mark chain as completed
        markChainCompleted(chain.id)
        
        save()
    }
    
    
    // MARK: - Day Management
    
    func switchToDay(_ date: Date) {
        // Analyze current day before switching
        if !appState.currentDay.blocks.isEmpty {
            let context = DayContext(
                date: appState.currentDay.date,
                existingBlocks: appState.currentDay.blocks,
                currentEnergy: .daylight,
                preferredEmojis: ["🌊"],
                availableTime: 0,
                mood: appState.currentDay.mood,
                weatherContext: weatherService.getWeatherContext()
            )
            vibeAnalyzer.analyzeCurrentVibe(from: appState.currentDay, context: context)
        }
        
        // Save current day to historical data
        if let existingIndex = appState.historicalDays.firstIndex(where: { $0.id == appState.currentDay.id }) {
            appState.historicalDays[existingIndex] = appState.currentDay
        } else {
            appState.historicalDays.append(appState.currentDay)
        }
        save()
        
        // Load existing day data or create new day
        if let existingDay = appState.historicalDays.first(where: { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .day) }) {
            // Load existing day
            appState.currentDay = existingDay
        } else {
            // Create new day
            let newDay = Day(date: date)
            appState.currentDay = newDay
            // Store in historical data
            appState.historicalDays.append(newDay)
        }
        ensureTodayExists()
        refreshPastBlocks()
        updateTodaysMoodEntry(reference: date)
        syncExternalEvents(for: date)
    }
    
    func updateDayMood(_ mood: GlassMood) {
        withAnimation(.easeInOut(duration: 1.0)) {
            appState.currentDay.mood = mood
        }
        save()
    }
    
    // MARK: - User Patterns & Learning
    
    func recordPattern(_ pattern: String) {
        let lowercasePattern = pattern.lowercased()
        if !appState.userPatterns.contains(lowercasePattern) {
            appState.userPatterns.append(lowercasePattern)
            
            // Keep patterns manageable
            if appState.userPatterns.count > 100 {
                appState.userPatterns.removeFirst()
            }
        }
        save()
    }
    
    func getUserPatternsForAI() -> String {
        appState.userPatterns.joined(separator: ", ")
    }
    
    // MARK: - Preferences
    
    func updatePreferences(_ preferences: UserPreferences) {
        appState.preferences = preferences
        save()
    }
    
    // MARK: - Export & Import
    
    func exportData() async -> URL? {
        return await persistenceActor.exportData(appState)
    }
    
    func importData(from url: URL) async throws {
        if let importedState = await persistenceActor.importData(from: url) {
            withAnimation(.easeInOut(duration: 0.8)) {
                appState = importedState
            }
            save()
        } else {
            throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to import data"])
        }
    }
    
    // MARK: - Private Helpers
    
    private func ensureTodayExists() {
        let today = Date()
        let calendar = Calendar.current
        
        if !calendar.isDate(appState.currentDay.date, inSameDayAs: today) {
            // Create today's data
            appState.currentDay = Day(date: today)
        }
    }

    private func ensureGoalGraphsExist() {
        for index in appState.goals.indices {
            appState.goals[index].graph.ensureSeedIfEmpty(
                goalTitle: appState.goals[index].title,
                description: appState.goals[index].description
            )
            if appState.goals[index].graph.nodes.contains(where: { $0.pinned }) {
                appState.pinnedGoalIds.insert(appState.goals[index].id)
            }
        }
    }
    
    private func createSampleData() {
        appState = AppState()
        appState.currentDay = Day.sample()
        
        // Add some sample chains
        appState.recentChains = [
            Chain.sample(name: "Morning Energy"),
            Chain.sample(name: "Deep Work Session"),
            Chain.sample(name: "Evening Wind Down")
        ]
        
        // Add some learning patterns
        appState.userPatterns = [
            "prefers morning work",
            "likes creative afternoon",
            "needs evening rest"
        ]
        
        // Initialize XP/XXP with some starting values
        appState.userXP = 150 // Some initial knowledge
        appState.userXXP = 320 // Some initial work done
        
        // Add sample pillars
        appState.pillars = Pillar.samplePillars()
        
        // Add sample goals
        appState.goals = Goal.sampleGoals()
        ensureGoalGraphsExist()

        // Add sample intake questions
        appState.intakeQuestions = IntakeQuestion.sampleQuestions()
        
        // Add some sample dream concepts
        appState.dreamConcepts = [
            DreamConcept(
                title: "Learn a new language",
                description: "User has mentioned wanting to learn Spanish multiple times",
                mentions: 3,
                relatedKeywords: ["spanish", "language", "travel", "culture"]
            ),
            DreamConcept(
                title: "Start a garden",
                description: "Mentioned interest in growing own vegetables",
                mentions: 2,
                relatedKeywords: ["garden", "vegetables", "healthy", "outdoor"]
            )
        ]
    }
    
    // MARK: - Goal Operations
    
    func addGoal(_ goal: Goal) {
        var enrichedGoal = goal
        enrichedGoal.graph.ensureSeedIfEmpty(goalTitle: enrichedGoal.title, description: enrichedGoal.description)
        appState.goals.append(enrichedGoal)
        if enrichedGoal.graph.nodes.contains(where: { $0.pinned }) {
            appState.pinnedGoalIds.insert(enrichedGoal.id)
        }
        save()
        onboardingDelegate?.onboardingDidCreateGoal(enrichedGoal)
    }
    
    func updateGoal(_ goal: Goal) {
        if let index = appState.goals.firstIndex(where: { $0.id == goal.id }) {
            let oldGoal = appState.goals[index]
            var updatedGoal = goal
            updatedGoal.graph.ensureSeedIfEmpty(goalTitle: updatedGoal.title, description: updatedGoal.description)
            appState.goals[index] = updatedGoal
            if updatedGoal.graph.nodes.contains(where: { $0.pinned }) {
                appState.pinnedGoalIds.insert(updatedGoal.id)
            } else {
                appState.pinnedGoalIds.remove(updatedGoal.id)
            }
            
            // If emoji changed, propagate to related items
            if oldGoal.emoji != updatedGoal.emoji {
                propagateEmojiFromGoal(updatedGoal)
            }
        }
        save()
    }
    
    func removeGoal(id: UUID) {
        appState.goals.removeAll { $0.id == id }
        appState.pinnedGoalIds.remove(id)
        appState.goalFeedbackStats.removeValue(forKey: id)
        save()
    }
    
    func toggleTaskCompletion(goalId: UUID, taskId: UUID) {
        if let goalIndex = appState.goals.firstIndex(where: { $0.id == goalId }) {
            for groupIndex in 0..<appState.goals[goalIndex].groups.count {
                if let taskIndex = appState.goals[goalIndex].groups[groupIndex].tasks.firstIndex(where: { $0.id == taskId }) {
                    appState.goals[goalIndex].groups[groupIndex].tasks[taskIndex].isCompleted.toggle()
                    
                    // Update goal progress based on completed tasks
                    updateGoalProgress(goalId: goalId)
                    break
                }
            }
        }
        save()
    }
    
    private func updateGoalProgress(goalId: UUID) {
        if let goalIndex = appState.goals.firstIndex(where: { $0.id == goalId }) {
            let goal = appState.goals[goalIndex]
            let allTasks = goal.groups.flatMap { $0.tasks }
            let completedTasks = allTasks.filter { $0.isCompleted }
            
            appState.goals[goalIndex].progress = allTasks.isEmpty ? 0.0 : Double(completedTasks.count) / Double(allTasks.count)
        }
    }
    
    // MARK: - Goal Graph Operations

    func toggleGoalNodePin(goalId: UUID, nodeId: UUID) {
        guard let goalIndex = appState.goals.firstIndex(where: { $0.id == goalId }) else { return }
        var goal = appState.goals[goalIndex]
        guard goal.graph.togglePin(for: nodeId) != nil else { return }
        appState.goals[goalIndex] = goal
        if goal.graph.nodes.contains(where: { $0.pinned }) {
            appState.pinnedGoalIds.insert(goal.id)
        } else {
            appState.pinnedGoalIds.remove(goal.id)
        }
        save()
    }

    func regenerateGoalNode(goalId: UUID, nodeId: UUID, scope: GoalGraphRegenerateScope) {
        guard let goalIndex = appState.goals.firstIndex(where: { $0.id == goalId }) else { return }
        var goal = appState.goals[goalIndex]
        goal.graph.ensureSeedIfEmpty(goalTitle: goal.title, description: goal.description)
        switch scope {
        case .refresh:
            goal.graph.refreshNode(nodeId)
        case .expand:
            if let reference = goal.graph.nodes.first(where: { $0.id == nodeId }) {
                _ = goal.graph.addSibling(near: reference, goalTitle: goal.title)
            }
        }
        appState.goals[goalIndex] = goal
        if goal.graph.nodes.contains(where: { $0.pinned }) {
            appState.pinnedGoalIds.insert(goal.id)
        }
        save()
    }

    // MARK: - Emoji Propagation & Relationship Management
    
    /// Propagate emoji changes from a goal to all related items
    func propagateEmojiFromGoal(_ goal: Goal) {
        // Update related chains
        for i in 0..<appState.recentChains.count {
            if appState.recentChains[i].relatedGoalId == goal.id {
                appState.recentChains[i].emoji = goal.emoji
            }
        }
        
        // Update related time blocks
        for i in 0..<appState.currentDay.blocks.count {
            if appState.currentDay.blocks[i].relatedGoalId == goal.id {
                appState.currentDay.blocks[i].emoji = goal.emoji
            }
        }
        
        
        // Update related pillars
        for i in 0..<appState.pillars.count {
            if appState.pillars[i].relatedGoalId == goal.id {
                appState.pillars[i].emoji = goal.emoji
            }
        }
    }
    
    /// Propagate emoji changes from a pillar to all related items
    func propagateEmojiFromPillar(_ pillar: Pillar) {
        // Update related chains
        for i in 0..<appState.recentChains.count {
            if appState.recentChains[i].relatedPillarId == pillar.id {
                appState.recentChains[i].emoji = pillar.emoji
            }
        }
        
        // Update related time blocks
        for i in 0..<appState.currentDay.blocks.count {
            if appState.currentDay.blocks[i].relatedPillarId == pillar.id {
                appState.currentDay.blocks[i].emoji = pillar.emoji
            }
        }
        
        
        // Update related goals
        for i in 0..<appState.goals.count {
            if appState.goals[i].relatedPillarIds.contains(pillar.id) {
                appState.goals[i].emoji = pillar.emoji
            }
        }
    }
    
    /// Create a time block with proper emoji inheritance from related goals/pillars
    func createTimeBlockWithInheritedEmoji(title: String, startTime: Date, duration: TimeInterval, energy: EnergyType, relatedGoalId: UUID? = nil, relatedPillarId: UUID? = nil) -> TimeBlock {
        
        // Determine emoji from relationships
        var emoji = "📋" // default
        
        if let goalId = relatedGoalId, let goal = appState.goals.first(where: { $0.id == goalId }) {
            emoji = goal.emoji
        } else if let pillarId = relatedPillarId, let pillar = appState.pillars.first(where: { $0.id == pillarId }) {
            emoji = pillar.emoji
        }
        
        return TimeBlock(
            title: title,
            startTime: startTime,
            duration: duration,
            energy: energy,
            emoji: emoji,
            relatedGoalId: relatedGoalId,
            relatedPillarId: relatedPillarId
        )
    }
    
    /// Create a chain with proper emoji inheritance from related goals/pillars
    func createChainWithInheritedEmoji(name: String, blocks: [TimeBlock], flowPattern: FlowPattern, relatedGoalId: UUID? = nil, relatedPillarId: UUID? = nil) -> Chain {
        
        // Determine emoji from relationships
        var emoji = "🔗" // default
        
        if let goalId = relatedGoalId, let goal = appState.goals.first(where: { $0.id == goalId }) {
            emoji = goal.emoji
        } else if let pillarId = relatedPillarId, let pillar = appState.pillars.first(where: { $0.id == pillarId }) {
            emoji = pillar.emoji
        }
        
        return Chain(
            name: name,
            blocks: blocks,
            flowPattern: flowPattern,
            emoji: emoji,
            relatedGoalId: relatedGoalId,
            relatedPillarId: relatedPillarId
        )
    }

    // MARK: - To-Do Operations

    func addTodoItem(_ item: TodoItem) {
        appState.todoItems.append(item)
        save()
    }

    func updateTodoItem(_ item: TodoItem) {
        if let index = appState.todoItems.firstIndex(where: { $0.id == item.id }) {
            appState.todoItems[index] = item
            save()
        }
    }

    func toggleTodoCompletion(_ todoId: UUID) {
        if let index = appState.todoItems.firstIndex(where: { $0.id == todoId }) {
            appState.todoItems[index].isCompleted.toggle()
            save()
        }
    }

    func removeTodoItem(_ todoId: UUID) {
        appState.todoItems.removeAll { $0.id == todoId }
        save()
    }

    func confirmFollowUpTodo(
        _ todoId: UUID,
        updatedTitle: String?,
        startTime: Date,
        endTime: Date,
        notes: String?
    ) {
        guard let index = appState.todoItems.firstIndex(where: { $0.id == todoId }) else { return }
        let item = appState.todoItems[index]
        guard let followUp = item.followUp else { return }
        let cleanTitle = updatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle?.isEmpty == false ? cleanTitle! : item.title
        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotes: String?
        if let cleanNotes, !cleanNotes.isEmpty {
            resolvedNotes = cleanNotes
        } else if let itemNotes = item.notes, !itemNotes.isEmpty {
            resolvedNotes = itemNotes
        } else {
            resolvedNotes = followUp.notesSnapshot
        }
        let minimumDuration: TimeInterval = 600
        let safeEnd = max(endTime, startTime.addingTimeInterval(minimumDuration))
        let record = Record(
            blockId: followUp.blockId,
            title: resolvedTitle,
            startTime: startTime,
            endTime: safeEnd,
            notes: resolvedNotes,
            energy: followUp.energy,
            emoji: followUp.emoji,
            confirmedAt: Date()
        )
        appState.records.append(record)
        appState.todoItems.remove(at: index)
        save()
    }

    /// Link a time block to a goal and inherit its emoji
    func linkTimeBlockToGoal(_ blockId: UUID, goalId: UUID) {
        // Update current day blocks
        if let blockIndex = appState.currentDay.blocks.firstIndex(where: { $0.id == blockId }) {
            appState.currentDay.blocks[blockIndex].relatedGoalId = goalId
            if let goal = appState.goals.first(where: { $0.id == goalId }) {
                appState.currentDay.blocks[blockIndex].emoji = goal.emoji
            }
        }
        
        
        save()
    }
    
    /// Link a time block to a pillar and inherit its emoji
    func linkTimeBlockToPillar(_ blockId: UUID, pillarId: UUID) {
        // Update current day blocks
        if let blockIndex = appState.currentDay.blocks.firstIndex(where: { $0.id == blockId }) {
            appState.currentDay.blocks[blockIndex].relatedPillarId = pillarId
            if let pillar = appState.pillars.first(where: { $0.id == pillarId }) {
                appState.currentDay.blocks[blockIndex].emoji = pillar.emoji
                
                // Update pillar's last event date
                appState.pillars[appState.pillars.firstIndex(where: { $0.id == pillarId })!].lastEventDate = Date()
            }
        }
        
        save()
    }
    
    // MARK: - Enhanced Pattern Learning Integration
    
    /// Record user behavior for pattern learning when time blocks are created
    func recordTimeBlockCreation(_ block: TimeBlock, source: String = "manual") {
        let behaviorEvent = BehaviorEvent(
            .blockCreated(TimeBlockData(
                id: block.id.uuidString,
                title: block.title,
                emoji: block.emoji,
                energy: block.energy,
                duration: block.duration,
                period: block.period
            )),
            context: EventContext(
                energyLevel: block.energy,
                mood: appState.currentDay.mood,
                weatherCondition: weatherService.getWeatherContext()
            )
        )
        
        patternEngine.recordBehavior(behaviorEvent)
    }
    
    /// Record when suggestions are accepted or rejected for learning
    func recordSuggestionFeedback(_ suggestion: Suggestion, accepted: Bool, reason: String? = nil) {
        let suggestionData = SuggestionData(
            title: suggestion.title,
            emoji: suggestion.emoji,
            energy: suggestion.energy,
            duration: suggestion.duration,
            confidence: suggestion.confidence,
            weight: suggestion.weight,
            reason: suggestion.reason ?? suggestion.explanation,
            relatedGoalId: suggestion.relatedGoalId,
            relatedGoalTitle: suggestion.relatedGoalTitle,
            relatedPillarId: suggestion.relatedPillarId,
            relatedPillarTitle: suggestion.relatedPillarTitle
        )
        
        let behaviorEvent = BehaviorEvent(
            accepted ? .suggestionAccepted(suggestionData) : .suggestionRejected(suggestionData, reason: reason),
            context: EventContext(
                energyLevel: suggestion.energy,
                mood: appState.currentDay.mood
            )
        )
        
        patternEngine.recordBehavior(behaviorEvent)
        updateFeedbackStats(for: suggestion, positive: accepted)
        save()
    }

    private func updateFeedbackStats(for suggestion: Suggestion, positive: Bool) {
        let tags: [FeedbackTag] = positive ? [.useful] : [.notRelevant]
        if let goalId = suggestion.relatedGoalId {
            var stats = appState.goalFeedbackStats[goalId] ?? SuggestionFeedbackStats()
            stats.register(tags: tags)
            appState.goalFeedbackStats[goalId] = stats
        }
        if let pillarId = suggestion.relatedPillarId {
            var stats = appState.pillarFeedbackStats[pillarId] ?? SuggestionFeedbackStats()
            stats.register(tags: tags)
            appState.pillarFeedbackStats[pillarId] = stats
        }
    }

    func recordFeedback(
        target: FeedbackTargetType,
        targetId: UUID,
        tags: [FeedbackTag],
        comment: String?,
        linkedGoalId: UUID? = nil,
        linkedPillarId: UUID? = nil
    ) {
        let entry = FeedbackEntry(
            targetType: target,
            targetId: targetId,
            tags: tags,
            freeText: comment
        )
        appState.feedbackEntries.append(entry)
        applyAggregatedFeedback(for: entry, linkedGoalId: linkedGoalId, linkedPillarId: linkedPillarId)
        
        let feedbackData = FeedbackBehaviorData(
            targetType: target,
            tags: tags,
            comment: comment
        )
        let behaviorEvent = BehaviorEvent(
            .feedbackGiven(feedbackData),
            context: EventContext(
                mood: appState.currentDay.mood
            )
        )
        patternEngine.recordBehavior(behaviorEvent)
        requestMicroUpdate(.feedback)
        save()
        onboardingDelegate?.onboardingDidSubmitFeedback(entry)
    }
    
    private func applyAggregatedFeedback(for entry: FeedbackEntry, linkedGoalId: UUID?, linkedPillarId: UUID?) {
        var goalIds = Set<UUID>()
        var pillarIds = Set<UUID>()
        if entry.targetType == .goal {
            goalIds.insert(entry.targetId)
        }
        if entry.targetType == .pillar {
            pillarIds.insert(entry.targetId)
        }
        if let goalId = linkedGoalId {
            goalIds.insert(goalId)
        }
        if let pillarId = linkedPillarId {
            pillarIds.insert(pillarId)
        }
        for id in goalIds {
            applyFeedbackStats(toGoal: id, tags: entry.tags)
        }
        for id in pillarIds {
            applyFeedbackStats(toPillar: id, tags: entry.tags)
        }
    }
    
    private func applyFeedbackStats(toGoal goalId: UUID, tags: [FeedbackTag]) {
        guard appState.goals.contains(where: { $0.id == goalId }) else { return }
        var stats = appState.goalFeedbackStats[goalId] ?? SuggestionFeedbackStats()
        stats.register(tags: tags)
        appState.goalFeedbackStats[goalId] = stats
    }
    
    private func applyFeedbackStats(toPillar pillarId: UUID, tags: [FeedbackTag]) {
        guard appState.pillars.contains(where: { $0.id == pillarId }) else { return }
        var stats = appState.pillarFeedbackStats[pillarId] ?? SuggestionFeedbackStats()
        stats.register(tags: tags)
        appState.pillarFeedbackStats[pillarId] = stats
    }
    
    /// Record when chains are applied for pattern learning
    func recordChainApplication(_ chain: Chain) {
        let chainData = ChainData(
            id: chain.id.uuidString,
            name: chain.name,
            emoji: chain.emoji,
            blockCount: chain.blocks.count,
            totalDuration: chain.totalDuration
        )
        
        let behaviorEvent = BehaviorEvent(
            .chainApplied(chainData),
            context: EventContext(
                mood: appState.currentDay.mood
            )
        )
        
        patternEngine.recordBehavior(behaviorEvent)
    }
    
    /// Resolve goal and pillar references on suggestions so downstream views have both IDs and titles
    func resolveMetadata(for suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.map { suggestion in
            var updated = suggestion
            resolveGoalMetadata(for: &updated)
            resolvePillarMetadata(for: &updated)
            return updated
        }
    }
    
    private func resolveGoalMetadata(for suggestion: inout Suggestion) {
        if let goalId = suggestion.relatedGoalId,
           let goal = appState.goals.first(where: { $0.id == goalId }) {
            if suggestion.relatedGoalTitle == nil {
                suggestion.relatedGoalTitle = goal.title
            }
            loggedAmbiguousGoalSuggestions.remove(suggestion.id)
            return
        }
        let candidates = matchGoals(for: suggestion)
        guard !candidates.isEmpty else {
            suggestion.relatedGoalId = nil
            return
        }
        if candidates.count == 1, let match = candidates.first {
            suggestion.relatedGoalId = match.id
            suggestion.relatedGoalTitle = match.title
            loggedAmbiguousGoalSuggestions.remove(suggestion.id)
        } else {
            handleAmbiguousLink(for: &suggestion, type: .goal, options: candidates.map { $0.title })
        }
    }

    private func resolvePillarMetadata(for suggestion: inout Suggestion) {
        if let pillarId = suggestion.relatedPillarId,
           let pillar = appState.pillars.first(where: { $0.id == pillarId }) {
            if suggestion.relatedPillarTitle == nil {
                suggestion.relatedPillarTitle = pillar.name
            }
            loggedAmbiguousPillarSuggestions.remove(suggestion.id)
            return
        }
        let candidates = matchPillars(for: suggestion)
        guard !candidates.isEmpty else {
            suggestion.relatedPillarId = nil
            return
        }
        if candidates.count == 1, let match = candidates.first {
            suggestion.relatedPillarId = match.id
            suggestion.relatedPillarTitle = match.name
            loggedAmbiguousPillarSuggestions.remove(suggestion.id)
        } else {
            handleAmbiguousLink(for: &suggestion, type: .pillar, options: candidates.map { $0.name })
        }
    }

    private func matchGoals(for suggestion: Suggestion) -> [Goal] {
        let titleMatches: [Goal]
        if let normalizedTitle = normalizedTitle(from: suggestion.relatedGoalTitle) {
            titleMatches = appState.goals.filter { matches($0.title, normalizedTitle) }
        } else {
            titleMatches = []
        }
        let hintMatches: [Goal]
        if let hints = suggestion.linkHints {
            var seen = Set<UUID>()
            var matchesList: [Goal] = []
            for hint in hints {
                guard let normalizedHint = normalizedTitle(from: hint) else { continue }
                for goal in appState.goals where matches(goal.title, normalizedHint) || matches(goal.description, normalizedHint) {
                    if seen.insert(goal.id).inserted {
                        matchesList.append(goal)
                    }
                }
            }
            hintMatches = matchesList
        } else {
            hintMatches = []
        }
        if !titleMatches.isEmpty {
            if !hintMatches.isEmpty {
                let hintIds = Set(hintMatches.map { $0.id })
                let intersection = titleMatches.filter { hintIds.contains($0.id) }
                if !intersection.isEmpty {
                    return uniqueGoals(intersection)
                }
            }
            return uniqueGoals(titleMatches)
        }
        if !hintMatches.isEmpty {
            return uniqueGoals(hintMatches)
        }
        return []
    }

    private func matchPillars(for suggestion: Suggestion) -> [Pillar] {
        let titleMatches: [Pillar]
        if let normalizedTitle = normalizedTitle(from: suggestion.relatedPillarTitle) {
            titleMatches = appState.pillars.filter { matches($0.name, normalizedTitle) }
        } else {
            titleMatches = []
        }
        let hintMatches: [Pillar]
        if let hints = suggestion.linkHints {
            var seen = Set<UUID>()
            var matchesList: [Pillar] = []
            for hint in hints {
                guard let normalizedHint = normalizedTitle(from: hint) else { continue }
                for pillar in appState.pillars where matches(pillar.name, normalizedHint) || matches(pillar.description, normalizedHint) {
                    if seen.insert(pillar.id).inserted {
                        matchesList.append(pillar)
                    }
                }
            }
            hintMatches = matchesList
        } else {
            hintMatches = []
        }
        if !titleMatches.isEmpty {
            if !hintMatches.isEmpty {
                let hintIds = Set(hintMatches.map { $0.id })
                let intersection = titleMatches.filter { hintIds.contains($0.id) }
                if !intersection.isEmpty {
                    return uniquePillars(intersection)
                }
            }
            return uniquePillars(titleMatches)
        }
        if !hintMatches.isEmpty {
            return uniquePillars(hintMatches)
        }
        return []
    }

    private func uniqueGoals(_ goals: [Goal]) -> [Goal] {
        var seen = Set<UUID>()
        return goals.compactMap { goal in
            if seen.insert(goal.id).inserted {
                return goal
            }
            return nil
        }
    }

    private func uniquePillars(_ pillars: [Pillar]) -> [Pillar] {
        var seen = Set<UUID>()
        return pillars.compactMap { pillar in
            if seen.insert(pillar.id).inserted {
                return pillar
            }
            return nil
        }
    }

    private enum AmbiguityType { case goal, pillar }

    private func handleAmbiguousLink(for suggestion: inout Suggestion, type: AmbiguityType, options: [String]) {
        switch type {
        case .goal:
            suggestion.relatedGoalId = nil
            if loggedAmbiguousGoalSuggestions.insert(suggestion.id).inserted {
                print("⚠️ Ambiguous goal link for suggestion '\(suggestion.title)': \(options.joined(separator: ", "))")
            }
        case .pillar:
            suggestion.relatedPillarId = nil
            if loggedAmbiguousPillarSuggestions.insert(suggestion.id).inserted {
                print("⚠️ Ambiguous pillar link for suggestion '\(suggestion.title)': \(options.joined(separator: ", "))")
            }
        }
        if !(suggestion.reason?.localizedCaseInsensitiveContains("ambiguous link") ?? false) {
            suggestion.reason = combinedReason(base: suggestion.reason, additions: ["ambiguous link"])
        }
    }
    
    private func normalizedTitle(from title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
    }
    
    private func matches(_ lhs: String, _ rhs: String) -> Bool {
        let lhsTrimmed = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsTrimmed = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if lhsTrimmed.localizedCaseInsensitiveCompare(rhsTrimmed) == .orderedSame {
            return true
        }
        return lhsTrimmed.localizedCaseInsensitiveContains(rhsTrimmed) || rhsTrimmed.localizedCaseInsensitiveContains(lhsTrimmed)
    }
    
    /// Enhanced applySuggestion with pattern learning
    func applySuggestion(_ suggestion: Suggestion) {
        var block = suggestion.toTimeBlock()
        
        // Record that suggestion was accepted
        recordSuggestionFeedback(suggestion, accepted: true)
        
        // Record the time block creation
        recordTimeBlockCreation(block, source: "ai_suggestion")
        
        addTimeBlock(block)
        
        // Award XP for using AI suggestions
        appState.addXP(3, reason: "Applied AI suggestion")
        if appState.preferences.eventKitEnabled {
            Task { @MainActor in
                do {
                    let identifier = try await eventKitService.createEvent(from: block)
                    attachEventKitIdentifier(block.id, identifier: identifier, lastModified: Date())
                } catch {
                    // EventKit write failures are non-fatal in cautious mode
                }
            }
        }
        requestMicroUpdate(.acceptedSuggestion)
    }
    
    /// Enhanced rejectSuggestion with pattern learning
    func rejectSuggestion(_ suggestion: Suggestion, reason: String? = nil) {
        // Record rejection for learning
        recordSuggestionFeedback(suggestion, accepted: false, reason: reason)
        
        // Track rejection patterns for learning
        let rejectionPattern = "rejected:\(suggestion.title.lowercased())"
        if !appState.userPatterns.contains(rejectionPattern) {
            appState.userPatterns.append(rejectionPattern)
        }
        save()
        requestMicroUpdate(.rejectedSuggestion)
    }
    
    /// Get all items related to a specific emoji (for consistency checking)
    func getItemsWithEmoji(_ emoji: String) -> (goals: [Goal], pillars: [Pillar], chains: [Chain], blocks: [TimeBlock]) {
        let goals = appState.goals.filter { $0.emoji == emoji }
        let pillars = appState.pillars.filter { $0.emoji == emoji }
        let chains = appState.recentChains.filter { $0.emoji == emoji }
        let blocks = appState.currentDay.blocks.filter { $0.emoji == emoji }
        
        return (goals: goals, pillars: pillars, chains: chains, blocks: blocks)
    }
    
}

// MARK: - Preview Helper

// AppDataManager.preview is defined in Extensions.swift

// MARK: - Time Helpers

// Date extensions are defined in Extensions.swift
extension Date {
    var endOfDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? self
    }
    
    func setting(hour: Int, minute: Int = 0) -> Date? {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: self)
    }
}

// MARK: - EventKit Service

/// Service for integrating with system calendar via EventKit
@MainActor
class EventKitService: ObservableObject {
    @Published var isAuthorized = false
    @Published var isProcessing = false
    @Published var lastSyncTime: Date?
    @Published var lastChangeToken: Date = .distantPast
    
    private let eventStore = EKEventStore()
    
    init() {
        Task {
            await requestCalendarAccess()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEventStoreChange),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    // MARK: - Authorization
    
    func requestCalendarAccess() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .fullAccess:
            isAuthorized = true
        case .writeOnly:
            isAuthorized = true // Write-only is sufficient for our needs
        case .notDetermined:
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                isAuthorized = granted
            } catch {
                print("❌ Failed to request calendar access: \(error)")
                isAuthorized = false
            }
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }
    
    // MARK: - Event Creation
    
    func createEvent(from timeBlock: TimeBlock) async throws -> String {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = timeBlock.title
        event.startDate = timeBlock.startTime
        event.endDate = timeBlock.endTime
        event.notes = "Created by DayPlanner\nEnergy: \(timeBlock.energy.description)\nCategory: \(timeBlock.emoji)"
        
        // Use default calendar
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            lastSyncTime = Date()
            return event.eventIdentifier
        } catch {
            throw EventKitError.saveFailed(error)
        }
    }
    
    func createEvents(from timeBlocks: [TimeBlock]) async throws -> [String] {
        var eventIds: [String] = []
        
        for block in timeBlocks {
            let eventId = try await createEvent(from: block)
            eventIds.append(eventId)
        }
        
        return eventIds
    }

    func fetchEvents(start: Date, end: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
    }

    @objc private func handleEventStoreChange(_ notification: Notification) {
        lastChangeToken = Date()
    }
    
    func getDiagnostics() -> String {
        var diagnostics = "EventKit Service Diagnostics:\n"
        diagnostics += "Authorization: \(isAuthorized ? "✅ Granted" : "❌ Denied")\n"
        diagnostics += "Processing: \(isProcessing ? "⏳ Active" : "✅ Ready")\n"
        
        if let lastSync = lastSyncTime {
            diagnostics += "Last Sync: \(lastSync.formatted(.dateTime))\n"
        } else {
            diagnostics += "Last Sync: Never\n"
        }
        
        if isAuthorized {
            let calendars = eventStore.calendars(for: .event)
            diagnostics += "Available Calendars: \(calendars.count)\n"
            if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
                diagnostics += "Default Calendar: \(defaultCalendar.title)\n"
            }
        }
        
        return diagnostics
    }
}

enum EventKitError: LocalizedError {
    case notAuthorized
    case eventNotFound
    case saveFailed(Error)
    case deleteFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized. Please grant permission in System Preferences."
        case .eventNotFound:
            return "Event not found in calendar"
        case .saveFailed(let error):
            return "Failed to save event: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete event: \(error.localizedDescription)"
        }
    }
}

// MARK: - Weather Service

/// Service for providing weather context to AI suggestions
@MainActor
class WeatherService: ObservableObject {
    @Published var currentWeather: WeatherInfo?
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    
    private let locationManager = CLLocationManager()
    private var locationDelegate: WeatherLocationDelegate?
    
    init() {
        locationDelegate = WeatherLocationDelegate(service: self)
        locationManager.delegate = locationDelegate
        requestLocationPermission()
    }
    
    func requestLocationPermission() {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            #if os(macOS)
            locationManager.requestAlwaysAuthorization()
            #else
            locationManager.requestWhenInUseAuthorization()
            #endif
        case .authorizedAlways:
            updateWeatherIfNeeded()
        #if !os(macOS)
        case .authorizedWhenInUse:
            updateWeatherIfNeeded()
        #endif
        case .denied, .restricted:
            setDefaultWeather()
        @unknown default:
            setDefaultWeather()
        }
    }
    
    func updateWeatherIfNeeded() {
        if let lastUpdate = lastUpdated,
           Date().timeIntervalSince(lastUpdate) < 3600 {
            return
        }
        
        Task {
            await fetchWeatherData()
        }
    }
    
    private func fetchWeatherData() async {
        #if os(macOS)
        guard locationManager.authorizationStatus == .authorizedAlways else {
            setDefaultWeather()
            return
        }
        #else
        guard locationManager.authorizationStatus == .authorizedWhenInUse ||
              locationManager.authorizationStatus == .authorizedAlways else {
            setDefaultWeather()
            return
        }
        #endif
        
        isLoading = true
        defer { isLoading = false }
        
        await simulateWeatherFetch()
    }
    
    private func simulateWeatherFetch() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let month = Calendar.current.component(.month, from: now)
        
        let weather = generateSeasonalWeather(hour: hour, month: month)
        
        currentWeather = weather
        lastUpdated = Date()
    }
    
    private func setDefaultWeather() {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let month = Calendar.current.component(.month, from: now)
        
        currentWeather = generateSeasonalWeather(hour: hour, month: month)
        lastUpdated = Date()
    }
    
    private func generateSeasonalWeather(hour: Int, month: Int) -> WeatherInfo {
        var baseTemp: Double
        
        switch month {
        case 12, 1, 2: baseTemp = 35 // Winter
        case 3, 4, 5: baseTemp = 60 // Spring
        case 6, 7, 8: baseTemp = 78 // Summer
        case 9, 10, 11: baseTemp = 65 // Fall
        default: baseTemp = 65
        }
        
        let timeAdjustment: Double
        switch hour {
        case 6..<10: timeAdjustment = -5
        case 12..<16: timeAdjustment = 8
        case 16..<20: timeAdjustment = 3
        default: timeAdjustment = -8
        }
        
        let temperature = baseTemp + timeAdjustment
        
        let conditions: [WeatherCondition]
        if temperature > 75 {
            conditions = [.sunny, .partlyCloudy]
        } else if temperature < 40 {
            conditions = [.snowy, .cloudy]
        } else {
            conditions = [.sunny, .partlyCloudy, .cloudy, .rainy]
        }
        
        let condition = conditions.randomElement() ?? .sunny
        
        return WeatherInfo(
            temperature: temperature,
            condition: condition,
            humidity: Int.random(in: 30...80),
            timestamp: Date()
        )
    }
    
    func getWeatherContext() -> String {
        guard let weather = currentWeather else {
            return "Weather: Unknown"
        }
        
        let suggestion = weather.condition.suggestion
        return "Weather: \(Int(weather.temperature))°F, \(weather.condition.rawValue) - \(suggestion)"
    }
    
    func shouldSuggestIndoor() -> Bool {
        guard let weather = currentWeather else { return false }
        return weather.condition == .rainy || weather.condition == .snowy || weather.temperature < 35 || weather.temperature > 90
    }
    
    func shouldSuggestOutdoor() -> Bool {
        guard let weather = currentWeather else { return false }
        return weather.condition == .sunny && weather.temperature > 55 && weather.temperature < 85
    }
}

struct WeatherInfo: Codable {
    let temperature: Double
    let condition: WeatherCondition
    let humidity: Int
    let timestamp: Date
}

enum WeatherCondition: String, Codable, CaseIterable {
    case sunny = "Sunny"
    case partlyCloudy = "Partly Cloudy" 
    case cloudy = "Cloudy"
    case rainy = "Rainy"
    case snowy = "Snowy"
    
    var suggestion: String {
        switch self {
        case .sunny: return "Great weather for outdoor activities"
        case .partlyCloudy: return "Good weather for any activity"
        case .cloudy: return "Good for indoor or outdoor activities"
        case .rainy: return "Perfect for indoor activities and cozy tasks"
        case .snowy: return "Great for indoor activities or winter sports"
        }
    }
    
    var emoji: String {
        switch self {
        case .sunny: return "☀️"
        case .partlyCloudy: return "⛅"
        case .cloudy: return "☁️"
        case .rainy: return "🌧️"
        case .snowy: return "🌨️"
        }
    }
}

private class WeatherLocationDelegate: NSObject, CLLocationManagerDelegate {
    weak var service: WeatherService?
    
    init(service: WeatherService) {
        self.service = service
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            service?.requestLocationPermission()
        }
    }
}


// MARK: - Animation Helpers

extension Animation {
    static let liquidGlass = Animation.spring(response: 0.6, dampingFraction: 0.8)
    static let ripple = Animation.easeOut(duration: 0.8)
    static let settle = Animation.spring(response: 1.2, dampingFraction: 0.7)
    static let flow = Animation.easeInOut(duration: 1.0)
}

// MARK: - Background Persistence Actor

/// Actor for handling heavy I/O operations off the main thread
actor PersistenceActor {
    private let fileManager = FileManager.default
    private lazy var documentsDirectory: URL = {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    
    private lazy var appDataURL: URL = {
        documentsDirectory.appendingPathComponent("DayPlannerData.json")
    }()
    
    private lazy var backupDirectory: URL = {
        let url = documentsDirectory.appendingPathComponent("Backups")
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    
    // Throttling mechanism
    private var lastSaveTime: Date = .distantPast
    private var pendingSave: Task<Void, Never>?
    private let saveThrottleInterval: TimeInterval = 1.0 // 1 second throttle
    
    /// Save app state with throttling to prevent excessive writes
    func saveAppState(_ appState: AppState) async -> (success: Bool, lastSaved: Date?) {
        // Cancel any pending save
        pendingSave?.cancel()
        
        // Check if we should throttle this save
        let now = Date()
        if now.timeIntervalSince(lastSaveTime) < saveThrottleInterval {
            // Schedule a delayed save
            pendingSave = Task {
                try? await Task.sleep(nanoseconds: UInt64(saveThrottleInterval * 1_000_000_000))
                if !Task.isCancelled {
                    _ = await performSave(appState)
                }
            }
            return (success: true, lastSaved: nil) // Return success but no timestamp
        }
        
        return await performSave(appState)
    }
    
    private func performSave(_ appState: AppState) async -> (success: Bool, lastSaved: Date?) {
        do {
            let data = try JSONEncoder().encode(appState)
            try data.write(to: appDataURL)
            let saveTime = Date()
            lastSaveTime = saveTime
            
            // Create backup if needed
            if await shouldCreateBackup() {
                await createDailyBackup(data: data)
            }
            
            return (success: true, lastSaved: saveTime)
        } catch {
            print("❌ Failed to save app data: \(error)")
            return (success: false, lastSaved: nil)
        }
    }
    
    /// Load app state from disk
    func loadAppState() async -> AppState? {
        guard fileManager.fileExists(atPath: appDataURL.path) else {
            return nil // No existing data
        }
        
        do {
            let data = try Data(contentsOf: appDataURL)
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            print("❌ Failed to load app data: \(error)")
            return nil
        }
    }
    
    /// Export data to a file
    func exportData(_ appState: AppState) async -> URL? {
        let timestamp = DateFormatters.exportFormatter.string(from: Date())
        let exportURL = documentsDirectory.appendingPathComponent("DayPlanner_Export_\(timestamp).json")
        
        do {
            let data = try JSONEncoder().encode(appState)
            try data.write(to: exportURL)
            return exportURL
        } catch {
            print("❌ Failed to export data: \(error)")
            return nil
        }
    }
    
    /// Import data from a file
    func importData(from url: URL) async -> AppState? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            print("❌ Failed to import data: \(error)")
            return nil
        }
    }
    
    // MARK: - Backup Management
    
    private func shouldCreateBackup() async -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let lastBackupDate = await getLastBackupDate()
        
        return lastBackupDate == nil || !Calendar.current.isDate(lastBackupDate!, inSameDayAs: today)
    }
    
    private func createDailyBackup(data: Data) async {
        let dateString = DateFormatters.backupFormatter.string(from: Date())
        let backupURL = backupDirectory.appendingPathComponent("backup_\(dateString).json")
        
        do {
            try data.write(to: backupURL)
            // Removed automatic cleanup - backups are kept indefinitely
        } catch {
            print("❌ Failed to create backup: \(error)")
        }
    }
    
    private func getLastBackupDate() async -> Date? {
        do {
            let backupFiles = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            let sortedFiles = backupFiles.sorted { file1, file2 in
                let date1 = try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let date2 = try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return date1 ?? Date.distantPast > date2 ?? Date.distantPast
            }
            
            return try sortedFiles.first?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch {
            return nil
        }
    }
    
    private func cleanOldBackups() async {
        do {
            let backupFiles = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
            
            for file in backupFiles {
                let resourceValues = try file.resourceValues(forKeys: [.contentModificationDateKey])
                if let modificationDate = resourceValues.contentModificationDate,
                   modificationDate < thirtyDaysAgo {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("❌ Failed to clean old backups: \(error)")
        }
    }
}
