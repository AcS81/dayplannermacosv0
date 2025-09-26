//
//  Models.swift
//  DayPlanner
//
//  Liquid Glass Data Models
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Core Data Models

/// A time block represents any activity in the day
struct TimeBlock: Identifiable, Codable, Equatable, Transferable {
    var id = UUID()
    var title: String
    var startTime: Date
    var duration: TimeInterval // in seconds
    var energy: EnergyType
    var emoji: String // Visual identifier - replaces old flow system
    var glassState: GlassState = .solid
    var position: CGPoint = .zero // for drag interactions
    var relatedGoalId: UUID? // Link to related goal
    var relatedGoalTitle: String? // Human-readable goal title snapshot
    var relatedPillarId: UUID? // Link to related pillar
    var relatedPillarTitle: String? // Human-readable pillar title snapshot
    var suggestionId: UUID? // Original suggestion identifier when AI created the block
    var suggestionReason: String? // Why the recommender proposed this block
    var suggestionWeight: Double? // Weight score used by recommender
    var suggestionConfidence: Double? // Confidence score snapshot when accepted
    var externalEventId: String? // EventKit identifier when synced
    var externalLastModified: Date? // Track external edits
    var origin: TimeBlockOrigin = .manual
    var notes: String? // Optional freeform notes
    var confirmationState: BlockConfirmationState = .scheduled
    
    // Computed properties
    var endTime: Date {
        startTime.addingTimeInterval(duration)
    }
    
    var durationMinutes: Int {
        Int(duration / 60)
    }
    
    // Time period this block belongs to
    var period: TimePeriod {
        let hour = Calendar.current.component(.hour, from: startTime)
        switch hour {
        case 6..<12:
            return .morning
        case 12..<18:
            return .afternoon
        default:
            return .evening
        }
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        title: String,
        startTime: Date,
        duration: TimeInterval,
        energy: EnergyType,
        emoji: String,
        glassState: GlassState = .solid,
        position: CGPoint = .zero,
        relatedGoalId: UUID? = nil,
        relatedGoalTitle: String? = nil,
        relatedPillarId: UUID? = nil,
        relatedPillarTitle: String? = nil,
        suggestionId: UUID? = nil,
        suggestionReason: String? = nil,
        suggestionWeight: Double? = nil,
        suggestionConfidence: Double? = nil,
        externalEventId: String? = nil,
        externalLastModified: Date? = nil,
        origin: TimeBlockOrigin = .manual,
        notes: String? = nil,
        confirmationState: BlockConfirmationState = .scheduled
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.duration = duration
        self.energy = energy
        self.emoji = emoji
        self.glassState = glassState
        self.position = position
        self.relatedGoalId = relatedGoalId
        self.relatedGoalTitle = relatedGoalTitle
        self.relatedPillarId = relatedPillarId
        self.relatedPillarTitle = relatedPillarTitle
        self.suggestionId = suggestionId
        self.suggestionReason = suggestionReason
        self.suggestionWeight = suggestionWeight
        self.suggestionConfidence = suggestionConfidence
        self.externalEventId = externalEventId
        self.externalLastModified = externalLastModified
        self.origin = origin
        self.notes = notes
        self.confirmationState = confirmationState
    }
    
    // MARK: - Backward Compatibility & Migration
    
    private enum CodingKeys: String, CodingKey {
        case id, title, startTime, duration, energy, emoji, glassState, position, relatedGoalId, relatedGoalTitle, relatedPillarId, relatedPillarTitle, suggestionId, suggestionReason, suggestionWeight, suggestionConfidence, externalEventId, externalLastModified, origin, notes, confirmationState
        case flow // Old system - for backward compatibility
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        startTime = try container.decode(Date.self, forKey: .startTime)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        energy = try container.decode(EnergyType.self, forKey: .energy)
        glassState = try container.decodeIfPresent(GlassState.self, forKey: .glassState) ?? .solid
        position = try container.decodeIfPresent(CGPoint.self, forKey: .position) ?? .zero
        relatedGoalId = try container.decodeIfPresent(UUID.self, forKey: .relatedGoalId)
        relatedGoalTitle = try container.decodeIfPresent(String.self, forKey: .relatedGoalTitle)
        relatedPillarId = try container.decodeIfPresent(UUID.self, forKey: .relatedPillarId)
        relatedPillarTitle = try container.decodeIfPresent(String.self, forKey: .relatedPillarTitle)
        suggestionId = try container.decodeIfPresent(UUID.self, forKey: .suggestionId)
        suggestionReason = try container.decodeIfPresent(String.self, forKey: .suggestionReason)
        suggestionWeight = try container.decodeIfPresent(Double.self, forKey: .suggestionWeight)
        suggestionConfidence = try container.decodeIfPresent(Double.self, forKey: .suggestionConfidence)
        externalEventId = try container.decodeIfPresent(String.self, forKey: .externalEventId)
        externalLastModified = try container.decodeIfPresent(Date.self, forKey: .externalLastModified)
        origin = try container.decodeIfPresent(TimeBlockOrigin.self, forKey: .origin) ?? (externalEventId == nil ? .manual : .external)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        confirmationState = try container.decodeIfPresent(BlockConfirmationState.self, forKey: .confirmationState) ?? .scheduled
        
        // Handle migration from old flow system to emoji system
        if let existingEmoji = try container.decodeIfPresent(String.self, forKey: .emoji), !existingEmoji.isEmpty {
            emoji = existingEmoji
        } else if let oldFlow = try container.decodeIfPresent(FlowState.self, forKey: .flow) {
            // Migrate from old flow system
            emoji = oldFlow.rawValue
        } else {
            // Default emoji for very old data
            emoji = "📋"
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(duration, forKey: .duration)
        try container.encode(energy, forKey: .energy)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(glassState, forKey: .glassState)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(relatedGoalId, forKey: .relatedGoalId)
        try container.encodeIfPresent(relatedGoalTitle, forKey: .relatedGoalTitle)
        try container.encodeIfPresent(relatedPillarId, forKey: .relatedPillarId)
        try container.encodeIfPresent(relatedPillarTitle, forKey: .relatedPillarTitle)
        try container.encodeIfPresent(suggestionId, forKey: .suggestionId)
        try container.encodeIfPresent(suggestionReason, forKey: .suggestionReason)
        try container.encodeIfPresent(suggestionWeight, forKey: .suggestionWeight)
        try container.encodeIfPresent(suggestionConfidence, forKey: .suggestionConfidence)
        try container.encodeIfPresent(externalEventId, forKey: .externalEventId)
        try container.encodeIfPresent(externalLastModified, forKey: .externalLastModified)
        if origin != .manual || externalEventId != nil {
            try container.encode(origin, forKey: .origin)
        }
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(confirmationState, forKey: .confirmationState)
    }
    
    // MARK: - Transferable Conformance
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .timeBlockData)
    }
}

extension UTType {
    static let timeBlockData = UTType(exportedAs: "com.dayplanner.timeblock")
}

/// Energy levels for different types of activities
enum EnergyType: String, Codable, CaseIterable {
    case sunrise = "🌅"    // High energy, sharp focus
    case daylight = "☀️"   // Steady energy, sustained work
    case moonlight = "🌙"  // Low energy, gentle activities
    
    var description: String {
        switch self {
        case .sunrise: return "Sharp Focus"
        case .daylight: return "Steady Work"  
        case .moonlight: return "Gentle Flow"
        }
    }
    
    var color: Color {
        switch self {
        case .sunrise: return .orange
        case .daylight: return .yellow
        case .moonlight: return .purple
        }
    }
}

/// Flow states that determine visual appearance
enum FlowState: String, Codable, CaseIterable {
    case crystal = "💎"    // Precise, structured activities
    case water = "🌊"      // Fluid, creative activities
    case mist = "☁️"       // Soft, contemplative activities
    
    var description: String {
        switch self {
        case .crystal: return "Structured"
        case .water: return "Creative"
        case .mist: return "Contemplative"
        }
    }
    
    var material: Material {
        switch self {
        case .crystal: return .ultraThinMaterial
        case .water: return .regularMaterial
        case .mist: return .thickMaterial
        }
    }
}

/// Glass visual states for animations
enum GlassState: Codable, CaseIterable {
    case solid      // Committed, stable
    case liquid     // Being dragged/manipulated
    case mist       // Suggested/staged
    case crystal    // AI-generated, pristine
    
    var opacity: Double {
        switch self {
        case .solid: return 1.0
        case .liquid: return 0.8
        case .mist: return 0.6
        case .crystal: return 0.9
        }
    }
}

/// Time periods for the three main panels
enum TimePeriod: String, Codable, CaseIterable {
    case morning = "Morning Mist"
    case afternoon = "Afternoon Flow"
    case evening = "Evening Glow"
    
    var timeRange: String {
        switch self {
        case .morning: return "6:00 AM - 12:00 PM"
        case .afternoon: return "12:00 PM - 6:00 PM"
        case .evening: return "6:00 PM - 12:00 AM"
        }
    }
    
    var tint: Color {
        switch self {
        case .morning: return Color(hue: 0.6, saturation: 0.3, brightness: 0.9)
        case .afternoon: return Color(hue: 0.1, saturation: 0.4, brightness: 0.95)
        case .evening: return Color(hue: 0.8, saturation: 0.5, brightness: 0.8)
        }
    }
}

// MARK: - Chain Models

/// A chain is a sequence of related time blocks
struct Chain: Identifiable, Codable {
    let id: UUID
    var name: String
    var blocks: [TimeBlock]
    var flowPattern: FlowPattern
    var completionCount: Int
    var isActive: Bool
    var createdAt: Date
    var lastCompletedAt: Date?
    var completionHistory: [Date] = []
    var routinePromptShown: Bool = false
    var emoji: String // Visual identifier shared with related goals/pillars
    var relatedGoalId: UUID? // Link to related goal
    var relatedPillarId: UUID? // Link to related pillar
    
    // Custom Codable implementation to handle missing fields gracefully
    private enum CodingKeys: String, CodingKey {
        case id, name, blocks, flowPattern, completionCount, isActive, createdAt, lastCompletedAt, completionHistory, routinePromptShown, emoji, relatedGoalId, relatedPillarId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        blocks = try container.decode([TimeBlock].self, forKey: .blocks)
        flowPattern = try container.decode(FlowPattern.self, forKey: .flowPattern)
        completionCount = try container.decode(Int.self, forKey: .completionCount)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
        
        // Handle missing fields gracefully with defaults
        completionHistory = try container.decodeIfPresent([Date].self, forKey: .completionHistory) ?? []
        routinePromptShown = try container.decodeIfPresent(Bool.self, forKey: .routinePromptShown) ?? false
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "🔗"
        relatedGoalId = try container.decodeIfPresent(UUID.self, forKey: .relatedGoalId)
        relatedPillarId = try container.decodeIfPresent(UUID.self, forKey: .relatedPillarId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(blocks, forKey: .blocks)
        try container.encode(flowPattern, forKey: .flowPattern)
        try container.encode(completionCount, forKey: .completionCount)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastCompletedAt, forKey: .lastCompletedAt)
        try container.encode(completionHistory, forKey: .completionHistory)
        try container.encode(routinePromptShown, forKey: .routinePromptShown)
        try container.encode(emoji, forKey: .emoji)
        try container.encodeIfPresent(relatedGoalId, forKey: .relatedGoalId)
        try container.encodeIfPresent(relatedPillarId, forKey: .relatedPillarId)
    }
    
    init(id: UUID = UUID(), name: String, blocks: [TimeBlock], flowPattern: FlowPattern, completionCount: Int = 0, isActive: Bool = true, createdAt: Date = Date(), lastCompletedAt: Date? = nil, emoji: String = "🔗", relatedGoalId: UUID? = nil, relatedPillarId: UUID? = nil) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.flowPattern = flowPattern
        self.completionCount = completionCount
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastCompletedAt = lastCompletedAt
        self.emoji = emoji
        self.relatedGoalId = relatedGoalId
        self.relatedPillarId = relatedPillarId
    }
    
    var canBePromotedToRoutine: Bool {
        return completionCount >= 3 && !routinePromptShown && hasProperSpacing
    }
    
    private var hasProperSpacing: Bool {
        // PRD requirement: minimum 24h separation between completions
        guard completionHistory.count >= 3 else { return false }
        
        let sortedHistory = completionHistory.sorted()
        for i in 1..<sortedHistory.count {
            let timeDifference = sortedHistory[i].timeIntervalSince(sortedHistory[i-1])
            if timeDifference < 24 * 3600 { // Less than 24 hours
                return false
            }
        }
        return true
    }
    
    var totalDuration: TimeInterval {
        blocks.reduce(0) { $0 + $1.duration }
    }
    
    var totalDurationMinutes: Int {
        Int(totalDuration / 60)
    }
}

/// Visual patterns for chain animations
enum FlowPattern: String, Codable, CaseIterable {
    case waterfall = "waterfall"  // Sequential cascading
    case spiral = "spiral"        // Circular flow
    case ripple = "ripple"        // Radial expansion
    case wave = "wave"            // Undulating motion
    
    var description: String {
        switch self {
        case .waterfall: return "Sequential Flow"
        case .spiral: return "Circular Flow"
        case .ripple: return "Expanding Flow"
        case .wave: return "Rhythmic Flow"
        }
    }
}

// MARK: - Routine Models

/// A routine is a chain that has been promoted after 3+ completions
struct Routine: Identifiable, Codable {
    let id: UUID
    let chainId: UUID
    var name: String
    var adoptionScore: Double // How well-established this routine is (0.0 to 1.0)
    var scheduleRules: [RoutineScheduleRule]
    var isActive: Bool
    var createdAt: Date
    var lastSuggested: Date?
    
    init(id: UUID = UUID(), chainId: UUID, name: String, adoptionScore: Double = 0.5, scheduleRules: [RoutineScheduleRule] = [], isActive: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.chainId = chainId
        self.name = name
        self.adoptionScore = adoptionScore
        self.scheduleRules = scheduleRules
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

struct RoutineScheduleRule: Identifiable, Codable {
    let id: UUID
    var dayOfWeek: Set<Int>? // 1-7, Sunday = 1
    var timeOfDay: TimeWindow?
    var frequency: RoutineFrequency
    var conditions: [RoutineCondition]
    
    init(id: UUID = UUID(), dayOfWeek: Set<Int>? = nil, timeOfDay: TimeWindow? = nil, frequency: RoutineFrequency = .daily, conditions: [RoutineCondition] = []) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.timeOfDay = timeOfDay
        self.frequency = frequency
        self.conditions = conditions
    }
}

enum RoutineFrequency: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekends = "Weekends"
    case specific = "Specific Days"
    
    var description: String { return rawValue }
}

enum RoutineCondition: String, Codable, CaseIterable {
    case weatherSunny = "When sunny"
    case weatherRainy = "When rainy"
    case afterActivity = "After specific activity"
    case beforeActivity = "Before specific activity"
    case energyHigh = "When energy is high"
    case energyLow = "When energy is low"
    
    var description: String { return rawValue }
}

// MARK: - Day Model

/// Represents a complete day with its mood and blocks
struct Day: Identifiable, Codable {
    let id: UUID
    var date: Date
    var blocks: [TimeBlock]
    var mood: GlassMood
    var completedBlocks: Int
    
    init(id: UUID = UUID(), date: Date, blocks: [TimeBlock] = [], mood: GlassMood = .crystal, completedBlocks: Int = 0) {
        self.id = id
        self.date = date
        self.blocks = blocks
        self.mood = mood
        self.completedBlocks = completedBlocks
    }
    
    // Computed properties for three time periods
    var morningBlocks: [TimeBlock] {
        blocks.filter { $0.period == .morning }.sorted { $0.startTime < $1.startTime }
    }
    
    var afternoonBlocks: [TimeBlock] {
        blocks.filter { $0.period == .afternoon }.sorted { $0.startTime < $1.startTime }
    }
    
    var eveningBlocks: [TimeBlock] {
        blocks.filter { $0.period == .evening }.sorted { $0.startTime < $1.startTime }
    }
    
    var completionPercentage: Double {
        guard !blocks.isEmpty else { return 0 }
        return Double(completedBlocks) / Double(blocks.count)
    }
}

/// Overall mood/theme of the day affecting glass appearance
enum GlassMood: String, Codable, CaseIterable {
    case crystal = "crystal"    // Clear, focused day
    case mist = "mist"          // Gentle, flowing day
    case prism = "prism"        // Creative, dynamic day
    case storm = "storm"        // Intense, challenging day
    
    var description: String {
        switch self {
        case .crystal: return "Clear & Focused"
        case .mist: return "Gentle & Flowing"
        case .prism: return "Creative & Dynamic"
        case .storm: return "Intense & Challenging"
        }
    }
    
    var emoji: String {
        switch self {
        case .crystal: return "✨"
        case .mist: return "🌫"
        case .prism: return "🌈"
        case .storm: return "⚡️"
        }
    }

    var backgroundGradient: LinearGradient {
        switch self {
        case .crystal:
            return LinearGradient(colors: [.clear, .blue.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        case .mist:
            return LinearGradient(colors: [.gray.opacity(0.1), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        case .prism:
            return LinearGradient(colors: [.purple.opacity(0.1), .pink.opacity(0.1), .orange.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .storm:
            return LinearGradient(colors: [.gray.opacity(0.2), .black.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - AI Models

/// AI suggestion for time blocks
struct Suggestion: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var duration: TimeInterval
    var suggestedTime: Date
    var energy: EnergyType
    var emoji: String
    var explanation: String
    var confidence: Double // 0.0 to 1.0
    var weight: Double? // Relative priority from recommender
    var relatedGoalId: UUID? = nil
    var relatedGoalTitle: String? = nil
    var relatedPillarId: UUID? = nil
    var relatedPillarTitle: String? = nil
    var reason: String? = nil
    var linkHints: [String]? = nil
    
    init(
        id: UUID = UUID(),
        title: String,
        duration: TimeInterval,
        suggestedTime: Date,
        energy: EnergyType,
        emoji: String,
        explanation: String,
        confidence: Double,
        weight: Double? = nil,
        relatedGoalId: UUID? = nil,
        relatedGoalTitle: String? = nil,
        relatedPillarId: UUID? = nil,
        relatedPillarTitle: String? = nil,
        reason: String? = nil,
        linkHints: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.suggestedTime = suggestedTime
        self.energy = energy
        self.emoji = emoji
        self.explanation = explanation
        self.confidence = confidence
        self.weight = weight
        self.relatedGoalId = relatedGoalId
        self.relatedGoalTitle = relatedGoalTitle
        self.relatedPillarId = relatedPillarId
        self.relatedPillarTitle = relatedPillarTitle
        self.reason = reason
        self.linkHints = linkHints
    }
    
    func toTimeBlock() -> TimeBlock {
        TimeBlock(
            title: title,
            startTime: suggestedTime,
            duration: duration,
            energy: energy,
            emoji: emoji,
            glassState: .liquid,
            relatedGoalId: relatedGoalId,
            relatedGoalTitle: relatedGoalTitle,
            relatedPillarId: relatedPillarId,
            relatedPillarTitle: relatedPillarTitle,
            suggestionId: id,
            suggestionReason: reason ?? explanation,
            suggestionWeight: weight,
            suggestionConfidence: confidence,
            origin: .suggestion
        )
    }
}

/// Context for AI decision making
struct DayContext: Codable {
    let date: Date
    let currentTime: Date
    let existingBlocks: [TimeBlock]
    let currentEnergy: EnergyType
    let preferredEmojis: [String]
    let availableTime: TimeInterval
    let mood: GlassMood
    let weatherContext: String?
    let pillarGuidance: [String]
    
    init(date: Date, existingBlocks: [TimeBlock], currentEnergy: EnergyType, preferredEmojis: [String], availableTime: TimeInterval, mood: GlassMood, weatherContext: String? = nil, pillarGuidance: [String] = []) {
        self.date = date
        self.currentTime = Date()
        self.existingBlocks = existingBlocks
        self.currentEnergy = currentEnergy
        self.preferredEmojis = preferredEmojis
        self.availableTime = availableTime
        self.mood = mood
        self.weatherContext = weatherContext
        self.pillarGuidance = pillarGuidance
    }
    
    var summary: String {
        var summary = """
        Date: \(date.formatted(date: .abbreviated, time: .omitted))
        Current time: \(currentTime.formatted(.dateTime.hour().minute()))
        Energy: \(currentEnergy.description)
        Blocks: \(existingBlocks.count)
        Available: \(Int(availableTime/3600))h
        Mood: \(mood.description)
        """
        
        if let weather = weatherContext {
            summary += "\nWeather: \(weather)"
        }
        
        if !pillarGuidance.isEmpty {
            summary += "\nGuiding principles: \(pillarGuidance.joined(separator: "; "))"
        }
        
        return summary
    }
}

// MARK: - App State

/// Complete app state - simple and focused
struct AppState: Codable {
    var currentDay: Day = Day(date: Date())
    var historicalDays: [Day] = [] // Store previous days for persistence
    var recentChains: [Chain] = []
    var routines: [Routine] = [] // Promoted chains that became routines
    var userPatterns: [String] = [] // Simple pattern storage
    var preferences: UserPreferences = UserPreferences()
    var records: [Record] = []
    
    // XP/XXP System
    var userXP: Int = 0 // Knowledge about user
    var userXXP: Int = 0 // Work accomplished
    
    // Pillars and Goals (PRD requirements)
    var pillars: [Pillar] = []
    var goals: [Goal] = []
    var dreamConcepts: [DreamConcept] = []
    var intakeQuestions: [IntakeQuestion] = []
    var feedbackEntries: [FeedbackEntry] = []
    var todoItems: [TodoItem] = []
    var moodEntries: [MoodEntry] = []
    var onboarding: OnboardingState = OnboardingState()
    var ghostRejectionMemory: [String: GhostRejectionInfo] = [:]
    
    // Scheduling emphasis and feedback signals
    var pinnedGoalIds: Set<UUID> = []
    var emphasizedPillarIds: Set<UUID> = []
    var goalFeedbackStats: [UUID: SuggestionFeedbackStats] = [:]
    var pillarFeedbackStats: [UUID: SuggestionFeedbackStats] = [:]
    
    // Helper methods
    mutating func addBlock(_ block: TimeBlock) {
        currentDay.blocks.append(block)
    }
    
    mutating func updateBlock(_ block: TimeBlock) {
        if let index = currentDay.blocks.firstIndex(where: { $0.id == block.id }) {
            currentDay.blocks[index] = block
        }
    }
    
    mutating func removeBlock(_ blockId: UUID) {
        currentDay.blocks.removeAll { $0.id == blockId }
    }
    
    // XP/XXP methods
    mutating func addXP(_ amount: Int, reason: String) {
        userXP += amount
        // Could log the reason for transparency
    }
    
    mutating func addXXP(_ amount: Int, reason: String) {
        userXXP += amount
        // Could log the reason for transparency
    }
}

enum BlockConfirmationState: String, Codable, CaseIterable {
    case scheduled
    case unconfirmed
    case confirmed
}

enum TimeBlockOrigin: String, Codable {
    case manual
    case suggestion
    case onboarding
    case external
    case chain
    case aiGenerated
}

struct Record: Identifiable, Codable {
    var id = UUID()
    var blockId: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var notes: String?
    var energy: EnergyType
    var emoji: String
    var confirmedAt: Date = Date()

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

struct AutoConfirmedBlock: Identifiable, Codable {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var note: String?
    var confirmationTime: Date

    init(block: TimeBlock, note: String?, confirmationTime: Date) {
        self.id = block.id
        self.title = block.title
        self.startTime = block.startTime
        self.endTime = block.endTime
        self.note = note
        self.confirmationTime = confirmationTime
    }
}

struct GhostRejectionInfo: Codable {
    var count: Int = 0
    var lastRejectedAt: Date = Date()
    var lastTitle: String = ""

    mutating func registerRejection(for title: String) {
        count += 1
        lastRejectedAt = Date()
        lastTitle = title
    }
}

/// Simple user preferences
struct UserPreferences: Codable {
    var preferredStartTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    var preferredEndTime: Date = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    var defaultBlockDuration: TimeInterval = 3600 // 1 hour
    var favoriteEnergy: EnergyType = .daylight
    var favoriteEmoji: String = "📋"
    var enableVoice: Bool = true
    var enableAnimations: Bool = true
    
    // PRD Required Settings  
    var showEphemeralInsights: Bool = true
    var safeMode: Bool = false // Safe Mode: only non-destructive suggestions
    var autoRefreshRecommendations: Bool = true
    var showRecommendationBadges: Bool = true
    var showSuggestionContext: Bool = true
    var eventKitWritePolicy: EventKitWritePolicy = .writeOnAccept

    // Calendar & Integration
    var eventKitEnabled: Bool = true
    var twoWaySync: Bool = true
    var respectCalendarPrivacy: Bool = true
    
    // History & Undo
    var keepUndoHistory: Bool = true
    var historyRetentionDays: Int = 30
    
    
    // AI API Configuration
    var aiProvider: AIProvider = .local
    var openaiApiKey: String = ""
    var whisperApiKey: String = ""
    var customApiEndpoint: String = "http://localhost:1234"
    var openaiModel: String = "gpt-4o-mini"

    // Suggestion weighting configuration
    var suggestionWeighting: SuggestionWeighting = SuggestionWeighting()
}

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case local
    case openAI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local (LM Studio)"
        case .openAI: return "OpenAI API"
        }
    }
}

enum OpenAIModel: String, Codable, CaseIterable, Identifiable {
    case gpt5 = "gpt-5"
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4Turbo = "gpt-4-turbo"
    case gpt35Turbo = "gpt-3.5-turbo"
    case gpt4 = "gpt-4"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .gpt5: return "GPT-5 (Next Gen)"
        case .gpt5Mini: return "GPT-5 Mini (Fast & Smart)"
        case .gpt5Nano: return "GPT-5 Nano (Ultra Fast)"
        case .gpt4o: return "GPT-4o (Latest)"
        case .gpt4oMini: return "GPT-4o Mini (Fast & Cheap)"
        case .gpt4Turbo: return "GPT-4 Turbo"
        case .gpt35Turbo: return "GPT-3.5 Turbo"
        case .gpt4: return "GPT-4"
        }
    }
    
    var description: String {
        switch self {
        case .gpt5: return "Next generation model with advanced reasoning and multimodal capabilities"
        case .gpt5Mini: return "Balanced performance and speed, great for most applications"
        case .gpt5Nano: return "Ultra-fast responses, perfect for real-time applications"
        case .gpt4o: return "Most capable model, best for complex tasks"
        case .gpt4oMini: return "Fast and cost-effective, good for most tasks"
        case .gpt4Turbo: return "High performance, good balance of speed and capability"
        case .gpt35Turbo: return "Fast and efficient, good for simple tasks"
        case .gpt4: return "High quality responses, slower than newer models"
        }
    }
}

struct SuggestionWeighting: Codable {
    var pinBoost: Double = 0.25
    var pillarBoost: Double = 0.15
    var feedbackBoost: Double = 0.10
}

enum EventKitWritePolicy: String, Codable, CaseIterable, Identifiable {
    case readOnly
    case writeOnAccept

    var id: String { rawValue }

    var label: String {
        switch self {
        case .readOnly: return "Read-only"
        case .writeOnAccept: return "Write on accept"
        }
    }
}

struct SuggestionFeedbackStats: Codable {
    var positive: Int = 0
    var negative: Int = 0

    mutating func register(positive feedback: Bool) {
        if feedback {
            positive += 1
        } else {
            negative += 1
        }
    }

    mutating func register(tags: [FeedbackTag]) {
        let positives = tags.filter { $0.isPositive }.count
        let negatives = tags.filter { $0.isNegative }.count
        positive += positives
        negative += negatives
    }

    var total: Int {
        positive + negative
    }

    var netScore: Double {
        guard total > 0 else { return 0 }
        return Double(positive - negative) / Double(total)
    }

    var hasPositiveSignal: Bool {
        netScore > 0
    }
}

enum FeedbackTargetType: String, Codable {
    case suggestion
    case goal
    case pillar
}

enum FeedbackTag: String, Codable, CaseIterable, Identifiable {
    case useful = "👍 Useful"
    case notRelevant = "👎 Not relevant"
    case wrongTime = "⏱ Wrong time"
    case wrongPriority = "🧠 Wrong priority"
    
    var id: String { rawValue }
    
    var emoji: String {
        switch self {
        case .useful: return "👍"
        case .notRelevant: return "👎"
        case .wrongTime: return "⏱"
        case .wrongPriority: return "🧠"
        }
    }
    
    var label: String {
        rawValue
    }
    
    var isPositive: Bool {
        self == .useful
    }
    
    var isNegative: Bool {
        self != .useful
    }
}

struct FeedbackEntry: Identifiable, Codable {
    let id: UUID
    let targetType: FeedbackTargetType
    let targetId: UUID
    let tags: [FeedbackTag]
    let freeText: String?
    let timestamp: Date
    
    init(id: UUID = UUID(), targetType: FeedbackTargetType, targetId: UUID, tags: [FeedbackTag], freeText: String?, timestamp: Date = Date()) {
        self.id = id
        self.targetType = targetType
        self.targetId = targetId
        self.tags = tags
        self.freeText = freeText
        self.timestamp = timestamp
    }
    
    var tagSummary: String {
        tags.isEmpty ? "—" : tags.map(\.emoji).joined(separator: " ")
    }
}

// MARK: - Extensions for UI

// TimeBlock extensions are defined in Extensions.swift

struct MoodEntry: Identifiable, Codable {
    let id: UUID
    let mood: GlassMood
    let capturedAt: Date
    let source: MoodCaptureSource
    
    init(id: UUID = UUID(), mood: GlassMood, capturedAt: Date = Date(), source: MoodCaptureSource = .launchPrompt) {
        self.id = id
        self.mood = mood
        self.capturedAt = capturedAt
        self.source = source
    }
}

enum MoodCaptureSource: String, Codable {
    case launchPrompt
    case onboarding
    case quickUpdate
}

enum OnboardingPhase: String, Codable {
    case notStarted
    case mood
    case createEvent
    case createPillar
    case createGoal
    case exploreGhosts
    case feedback
    case checklist
    case completed
}

struct OnboardingState: Codable {
    var phase: OnboardingPhase = .notStarted
    var startedAt: Date?
    var completedAt: Date?
    var didCaptureMood: Bool = false
    var didCreateEvent: Bool = false
    var didCreatePillar: Bool = false
    var didCreateGoal: Bool = false
    var didAcceptGhost: Bool = false
    var didSubmitFeedback: Bool = false
    
    var isComplete: Bool {
        phase == .completed
    }
}

// MARK: - To-Do & Follow-up Items

struct FollowUpMetadata: Codable, Equatable {
    var blockId: UUID
    var originalTitle: String
    var startTime: Date
    var endTime: Date
    var energy: EnergyType
    var emoji: String
    var notesSnapshot: String?
    var capturedAt: Date

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date?
    var isCompleted: Bool
    var createdDate: Date
    var notes: String?
    var followUp: FollowUpMetadata?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        createdDate: Date = Date(),
        notes: String? = nil,
        followUp: FollowUpMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdDate = createdDate
        self.notes = notes
        self.followUp = followUp
    }

    var isFollowUp: Bool {
        followUp != nil
    }

    var markerLabel: String? {
        isFollowUp ? "Past/Unconfirmed" : nil
    }

    var dueDateString: String {
        guard let dueDate else { return "No due date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dueDate)
    }

    func followUpRelativeString(reference: Date = Date()) -> String? {
        guard let followUp else { return nil }
        return followUp.startTime.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

extension Chain {
    /// Create a sample chain for previews
    static func sample(name: String = "Morning Routine") -> Chain {
        let blocks = [
            TimeBlock.sample(title: "Wake Up", hour: 7),
            TimeBlock.sample(title: "Exercise", hour: 8),
            TimeBlock.sample(title: "Breakfast", hour: 9)
        ]
        return Chain(name: name, blocks: blocks, flowPattern: .waterfall)
    }
}

extension Day {
    /// Create a sample day for previews
    static func sample() -> Day {
        var day = Day(date: Date())
        day.blocks = [
            TimeBlock.sample(title: "Morning Coffee", hour: 8),
            TimeBlock.sample(title: "Deep Work", hour: 9),
            TimeBlock.sample(title: "Lunch Break", hour: 12),
            TimeBlock.sample(title: "Meetings", hour: 14),
            TimeBlock.sample(title: "Creative Time", hour: 16),
            TimeBlock.sample(title: "Evening Walk", hour: 19)
        ]
        return day
    }
}

// MARK: - PRD Required Models

/// Pillar: Core life principles that guide all AI decisions - can be actionable (events) or principle (values/thoughts)
struct Pillar: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var frequency: PillarFrequency
    var quietHours: [TimeWindow]
    var wisdomText: String?
    var values: [String]
    var habits: [String]
    var constraints: [String]
    var color: CodableColor
    var emoji: String
    var relatedGoalId: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        type: PillarType = .principle,
        frequency: PillarFrequency,
        minDuration: TimeInterval = 0,
        maxDuration: TimeInterval = 0,
        preferredTimeWindows: [TimeWindow] = [],
        overlapRules: [OverlapRule] = [],
        quietHours: [TimeWindow] = [],
        eventConsiderationEnabled: Bool = true,
        wisdomText: String? = nil,
        values: [String] = [],
        habits: [String] = [],
        constraints: [String] = [],
        color: CodableColor = CodableColor(.blue),
        emoji: String = "🏛️",
        relatedGoalId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.frequency = frequency
        self.quietHours = quietHours
        self.wisdomText = wisdomText
        self.values = values
        self.habits = habits
        self.constraints = constraints
        self.color = color
        self.emoji = emoji
        self.relatedGoalId = relatedGoalId
        self.createdAt = createdAt
        _ = type
        _ = minDuration
        _ = maxDuration
        _ = preferredTimeWindows
        _ = overlapRules
        _ = eventConsiderationEnabled
    }

    var frequencyDescription: String {
        switch frequency {
        case .daily: return "Daily"
        case .weekly(let count): return "\(count)x per week"
        case .monthly(let count): return "\(count)x per month"
        case .asNeeded: return "As needed"
        }
    }

    /// Guidance text summarises the principle for the AI engine.
    var aiGuidanceText: String {
        var components: [String] = []
        components.append(description)
        if let wisdom = wisdomText, !wisdom.isEmpty {
            components.append("Core principle: \(wisdom)")
        }
        if !values.isEmpty {
            components.append("Values: \(values.joined(separator: ", "))")
        }
        if !habits.isEmpty {
            components.append("Habits to encourage: \(habits.joined(separator: ", "))")
        }
        if !constraints.isEmpty {
            components.append("Constraints: \(constraints.joined(separator: ", "))")
        }
        if !quietHours.isEmpty {
            let windowText = quietHours.map { $0.description }.joined(separator: ", ")
            components.append("Quiet hours to protect: \(windowText)")
        }
        return components.joined(separator: "\n\n")
    }

    // Legacy compatibility surface; pillars are principle-only but some views still expect these accessors.
    var type: PillarType { .principle }
    var minDuration: TimeInterval { 0 }
    var maxDuration: TimeInterval { 0 }
    var preferredTimeWindows: [TimeWindow] { [] }
    var overlapRules: [OverlapRule] { [] }
    var eventConsiderationEnabled: Bool { true }
    var isActionable: Bool { false }
    var isPrinciple: Bool { true }
}

enum PillarType: String, Codable, CaseIterable {
    case actionable = "Actionable"
    case principle = "Principle"

    static var allCases: [PillarType] { [.principle] }

    var description: String {
        switch self {
        case .actionable:
            return "Creates scheduled activities (legacy)"
        case .principle:
            return "Guides AI decisions and suggestions"
        }
    }

    var icon: String {
        switch self {
        case .actionable:
            return "calendar.badge.plus"
        case .principle:
            return "lightbulb"
        }
    }
}

enum PillarFrequency: Codable, Hashable, CaseIterable {
    case daily
    case weekly(Int)
    case monthly(Int) 
    case asNeeded
    
    static var allCases: [PillarFrequency] {
        [.daily, .weekly(1), .monthly(1), .asNeeded]
    }
    
    var displayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly(let count):
            return count == 1 ? "Weekly" : "\(count)x per week"
        case .monthly(let count):
            return count == 1 ? "Monthly" : "\(count)x per month"
        case .asNeeded:
            return "As needed"
        }
    }
}

struct TimeWindow: Codable, Hashable {
    let startHour: Int // 0-23
    let startMinute: Int // 0-59
    let endHour: Int
    let endMinute: Int
    
    var description: String {
        let startTime = String(format: "%02d:%02d", startHour, startMinute)
        let endTime = String(format: "%02d:%02d", endHour, endMinute)
        return "\(startTime) - \(endTime)"
    }
}

enum OverlapRule: Codable {
    case cannotOverlap([String])
    case mustFollow(String)
    case mustPrecede(String)
    case requiresBuffer(TimeInterval)
}

/// Goal: Draft / On / Off; groups & tasks > suggestions
struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var state: GoalState
    var importance: Int // 1-5, AI uses this for scoring
    var groups: [GoalGroup]
    var createdAt: Date
    var targetDate: Date?
    var progress: Double // 0.0 to 1.0
    var emoji: String // Visual identifier shared with related pillars/chains/events
    var relatedPillarIds: [UUID] // Links to supporting pillars
    var graph: GoalGraph
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        state: GoalState,
        importance: Int,
        groups: [GoalGroup],
        createdAt: Date = Date(),
        targetDate: Date? = nil,
        progress: Double = 0.0,
        emoji: String = "🎯",
        relatedPillarIds: [UUID] = [],
        graph: GoalGraph = GoalGraph()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.state = state
        self.importance = importance
        self.groups = groups
        self.createdAt = createdAt
        self.targetDate = targetDate
        self.progress = progress
        self.emoji = emoji
        self.relatedPillarIds = relatedPillarIds
        self.graph = graph
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, state, importance, groups, createdAt, targetDate, progress, emoji, relatedPillarIds, graph
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        state = try container.decodeIfPresent(GoalState.self, forKey: .state) ?? .draft
        importance = try container.decodeIfPresent(Int.self, forKey: .importance) ?? 3
        groups = try container.decodeIfPresent([GoalGroup].self, forKey: .groups) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        targetDate = try container.decodeIfPresent(Date.self, forKey: .targetDate)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0.0
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "🎯"
        relatedPillarIds = try container.decodeIfPresent([UUID].self, forKey: .relatedPillarIds) ?? []
        graph = try container.decodeIfPresent(GoalGraph.self, forKey: .graph) ?? GoalGraph()
        graph.ensureSeedIfEmpty(goalTitle: title, description: description)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(state, forKey: .state)
        try container.encode(importance, forKey: .importance)
        try container.encode(groups, forKey: .groups)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(targetDate, forKey: .targetDate)
        try container.encode(progress, forKey: .progress)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(relatedPillarIds, forKey: .relatedPillarIds)
        try container.encode(graph, forKey: .graph)
    }
    
    var isActive: Bool {
        state == .on
    }
    
    var needsBreakdown: Bool {
        return groups.isEmpty && state != .off
    }
}

// MARK: - Goal Breakdown Actions

enum GoalBreakdownAction {
    case createChain(Chain)
    case createPillar(Pillar)
    case createEvent(TimeBlock)
    case updateGoal(Goal)
}

enum GoalState: String, Codable, CaseIterable {
    case draft = "Draft"
    case on = "On"
    case off = "Off"
    
    var description: String {
        switch self {
        case .draft: return "Draft - preparation phase"
        case .on: return "On - actively working towards"
        case .off: return "Off - paused"
        }
    }
}

struct GoalGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    var tasks: [GoalTask]
    
    init(id: UUID = UUID(), name: String, tasks: [GoalTask]) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
    var isCompleted: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.isCompleted }
    }
}

struct GoalTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var isCompleted: Bool
    var estimatedDuration: TimeInterval?
    var suggestedChains: [UUID] // Chain IDs that help accomplish this task
    var actionQuality: Int // 1-5, AI scoring of how good this action is
    
    init(id: UUID = UUID(), title: String, description: String, isCompleted: Bool = false, estimatedDuration: TimeInterval? = nil, suggestedChains: [UUID], actionQuality: Int = 3) {
        self.id = id
        self.title = title
        self.description = description
        self.isCompleted = isCompleted
        self.estimatedDuration = estimatedDuration
        self.suggestedChains = suggestedChains
        self.actionQuality = actionQuality
    }
}

// MARK: - GoalGraph (Mind Map)

enum GoalGraphNodeType: String, Codable, CaseIterable, Identifiable {
    case subgoal
    case task
    case note
    case resource
    case metric

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subgoal: return "Sub-goal"
        case .task: return "Task"
        case .note: return "Note"
        case .resource: return "Resource"
        case .metric: return "Metric"
        }
    }

    var glyph: String {
        switch self {
        case .subgoal: return "🎯"
        case .task: return "🧩"
        case .note: return "📝"
        case .resource: return "📚"
        case .metric: return "📈"
        }
    }

    func seededTitle(goalTitle: String, index: Int) -> String {
        switch self {
        case .subgoal:
            return "Anchor \(index): \(goalTitle)"
        case .task:
            return "Step \(index)"
        case .note:
            return "Insight \(index)"
        case .resource:
            return "Support \(index)"
        case .metric:
            return "Metric \(index)"
        }
    }
}

struct GoalGraphNode: Identifiable, Codable, Equatable {
    let id: UUID
    var type: GoalGraphNodeType
    var title: String
    var detail: String?
    var pinned: Bool
    var weight: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: GoalGraphNodeType,
        title: String,
        detail: String? = nil,
        pinned: Bool = false,
        weight: Double = 0.35,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.pinned = pinned
        self.weight = weight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GoalGraphEdge: Identifiable, Codable, Equatable {
    let id: UUID
    var from: UUID
    var to: UUID
    var label: String?

    init(id: UUID = UUID(), from: UUID, to: UUID, label: String? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.label = label
    }
}

struct GoalGraphHistoryEntry: Identifiable, Codable {
    let id: UUID
    var timestamp: Date
    var summary: String
    var nodeId: UUID?

    init(id: UUID = UUID(), timestamp: Date = Date(), summary: String, nodeId: UUID? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.summary = summary
        self.nodeId = nodeId
    }
}

struct GoalGraph: Codable {
    var nodes: [GoalGraphNode]
    var edges: [GoalGraphEdge]
    var history: [GoalGraphHistoryEntry]

    init(
        nodes: [GoalGraphNode] = [],
        edges: [GoalGraphEdge] = [],
        history: [GoalGraphHistoryEntry] = []
    ) {
        self.nodes = nodes
        self.edges = edges
        self.history = history
    }
}

extension GoalGraph {
    mutating func togglePin(for nodeId: UUID) -> GoalGraphNode? {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return nil }
        nodes[index].pinned.toggle()
        nodes[index].updatedAt = Date()
        history.append(
            GoalGraphHistoryEntry(
                summary: nodes[index].pinned ? "Pinned \(nodes[index].title)" : "Unpinned \(nodes[index].title)",
                nodeId: nodeId
            )
        )
        return nodes[index]
    }

    mutating func refreshNode(_ nodeId: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[index].updatedAt = Date()
        // Light-touch adjustment to weight keeps the suggestion engine reactive without altering structure
        let delta = min(0.1, max(-0.1, Double.random(in: -0.05...0.08)))
        nodes[index].weight = max(0.1, min(1.0, nodes[index].weight + delta))
        history.append(
            GoalGraphHistoryEntry(
                summary: "Refreshed \(nodes[index].title)",
                nodeId: nodeId
            )
        )
    }

    mutating func addSibling(near node: GoalGraphNode, goalTitle: String) -> GoalGraphNode {
        let siblingIndex = nodes.filter { $0.type == node.type }.count + 1
        let title = node.type.seededTitle(goalTitle: goalTitle, index: siblingIndex)
        var newNode = GoalGraphNode(type: node.type, title: title)
        newNode.weight = max(node.weight - 0.05, 0.2)
        nodes.append(newNode)
        edges.append(
            GoalGraphEdge(
                from: node.id,
                to: newNode.id,
                label: node.type == .metric ? "tracks" : "supports"
            )
        )
        history.append(
            GoalGraphHistoryEntry(
                summary: "Expanded \(node.type.displayName.lowercased()) with \(title)",
                nodeId: newNode.id
            )
        )
        return newNode
    }

    mutating func ensureSeedIfEmpty(goalTitle: String, description: String?) {
        guard nodes.isEmpty else { return }
        let anchor = GoalGraphNode(
            type: .subgoal,
            title: "Clarify \(goalTitle)",
            detail: description ?? "Define why this matters",
            weight: 0.45
        )
        let firstTask = GoalGraphNode(
            type: .task,
            title: "Next step",
            detail: "Identify immediate action",
            weight: 0.4
        )
        let note = GoalGraphNode(
            type: .note,
            title: "Context",
            detail: description ?? "Capture motivation",
            weight: 0.3
        )
        nodes = [anchor, firstTask, note]
        edges = [
            GoalGraphEdge(from: anchor.id, to: firstTask.id, label: "leads"),
            GoalGraphEdge(from: anchor.id, to: note.id, label: "why")
        ]
        history.append(
            GoalGraphHistoryEntry(
                summary: "Seeded mind-map for \(goalTitle)"
            )
        )
    }
}

enum GoalGraphRegenerateScope {
    case refresh
    case expand
}

/// Dream Builder: recurring desires/themes captured from chats and calendar notes
struct DreamConcept: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var mentions: Int // How many times user has mentioned this
    var lastMentioned: Date
    var relatedKeywords: [String]
    var canMergeWith: [UUID] // Other dream concept IDs
    var hasBeenPromotedToGoal: Bool
    
    init(id: UUID = UUID(), title: String, description: String, mentions: Int = 1, lastMentioned: Date = Date(), relatedKeywords: [String] = [], canMergeWith: [UUID] = [], hasBeenPromotedToGoal: Bool = false) {
        self.id = id
        self.title = title
        self.description = description
        self.mentions = mentions
        self.lastMentioned = lastMentioned
        self.relatedKeywords = relatedKeywords
        self.canMergeWith = canMergeWith
        self.hasBeenPromotedToGoal = hasBeenPromotedToGoal
    }
    
    var priority: Double {
        // Simple priority based on mentions and recency
        let recencyFactor = max(0.1, 1.0 - (Date().timeIntervalSince(lastMentioned) / (30 * 24 * 3600))) // 30 days
        return Double(mentions) * recencyFactor
    }
}

/// Intake Q&A: short, targeted questions; long‑press any card for "what the AI thinks"
struct IntakeQuestion: Identifiable, Codable {
    let id: UUID
    var question: String
    var category: IntakeCategory
    var answer: String?
    var answeredAt: Date?
    var importance: Int // 1-5
    var aiInsight: String? // What AI thinks about this answer
    
    init(id: UUID = UUID(), question: String, category: IntakeCategory, answer: String? = nil, answeredAt: Date? = nil, importance: Int = 3, aiInsight: String? = nil) {
        self.id = id
        self.question = question
        self.category = category
        self.answer = answer
        self.answeredAt = answeredAt
        self.importance = importance
        self.aiInsight = aiInsight
    }
    
    var isAnswered: Bool {
        answer != nil && !(answer?.isEmpty ?? true)
    }
}

enum IntakeCategory: String, Codable, CaseIterable {
    case routine = "Routine"
    case preferences = "Preferences"
    case constraints = "Constraints"
    case goals = "Goals"
    case energy = "Energy Patterns"
    case context = "Context"
    
    var description: String {
        switch self {
        case .routine: return "Daily routines and habits"
        case .preferences: return "Likes and dislikes"
        case .constraints: return "Time and resource limitations"
        case .goals: return "Aspirations and objectives"
        case .energy: return "Energy levels throughout the day"
        case .context: return "Life context and situation"
        }
    }
}

// MARK: - Helper Types

/// Codable wrapper for SwiftUI Color
struct CodableColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    init(_ color: Color) {
        // This is a simplified approach - in practice you'd need more sophisticated color extraction
        self.red = 0.5
        self.green = 0.5
        self.blue = 1.0
        self.alpha = 1.0
    }
    
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Sample Data Extensions

extension Pillar {
    static func samplePillars() -> [Pillar] {
        [
            Pillar(
                name: "Exercise",
                description: "Keep energy and resilience high through movement.",
                frequency: .daily,
                quietHours: [
                    TimeWindow(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0)
                ],
                wisdomText: "Strong body, clear mind.",
                values: ["Vitality", "Discipline"],
                habits: ["Strength training", "Mobility work", "Walks"],
                constraints: ["No intense workouts after 9pm"],
                color: CodableColor(.orange)
            ),
            Pillar(
                name: "Deep Work",
                description: "Protect craft blocks for meaningful output.",
                frequency: .daily,
                quietHours: [
                    TimeWindow(startHour: 19, startMinute: 0, endHour: 9, endMinute: 0)
                ],
                wisdomText: "Default to depth when energy is high.",
                values: ["Craft", "Focus"],
                habits: ["Block 90 minutes before lunch", "Single-task"],
                constraints: ["No meetings before 11am"],
                color: CodableColor(.blue)
            ),
            Pillar(
                name: "Rest",
                description: "Make space to recharge and downshift.",
                frequency: .daily,
                quietHours: [],
                wisdomText: "Rest is fuel, not a reward.",
                values: ["Presence", "Recovery"],
                habits: ["Digital sunset at 9pm", "Evening stretch"],
                constraints: ["Stop work devices by 9pm"],
                color: CodableColor(.purple)
            )
        ]
    }
}

extension Goal {
    static func sampleGoals() -> [Goal] {
        [
            Goal(
                title: "Launch Side Project",
                description: "Build and launch my productivity app",
                state: .on,
                importance: 5,
                groups: [
                    GoalGroup(
                        name: "Development",
                        tasks: [
                            GoalTask(
                                title: "Complete MVP features",
                                description: "Build core functionality",
                                estimatedDuration: 3600 * 40, // 40 hours
                                suggestedChains: [],
                                actionQuality: 5
                            ),
                            GoalTask(
                                title: "User testing",
                                description: "Get feedback from beta users",
                                estimatedDuration: 3600 * 8, // 8 hours
                                suggestedChains: [],
                                actionQuality: 4
                            )
                        ]
                    ),
                    GoalGroup(
                        name: "Marketing",
                        tasks: [
                            GoalTask(
                                title: "Create landing page",
                                description: "Build a simple landing page",
                                estimatedDuration: 3600 * 6, // 6 hours
                                suggestedChains: [],
                                actionQuality: 3
                            )
                        ]
                    )
                ],
                targetDate: Calendar.current.date(byAdding: .month, value: 3, to: Date())
            ),
            Goal(
                title: "Improve Health",
                description: "Get in better physical shape",
                state: .on,
                importance: 4,
                groups: [
                    GoalGroup(
                        name: "Exercise",
                        tasks: [
                            GoalTask(
                                title: "Morning runs",
                                description: "Run 3x per week",
                                suggestedChains: [],
                                actionQuality: 4
                            ),
                            GoalTask(
                                title: "Strength training",
                                description: "Gym 2x per week",
                                suggestedChains: [],
                                actionQuality: 4
                            )
                        ]
                    )
                ],
                targetDate: Calendar.current.date(byAdding: .month, value: 6, to: Date())
            )
        ]
    }
}

extension IntakeQuestion {
    static func sampleQuestions() -> [IntakeQuestion] {
        [
            IntakeQuestion(
                question: "What time do you usually have dinner?",
                category: .routine,
                importance: 4,
                aiInsight: "Knowing meal times helps schedule around energy dips and social commitments"
            ),
            IntakeQuestion(
                question: "Which days do you typically commute to work?",
                category: .constraints,
                importance: 5,
                aiInsight: "Commute days affect available time blocks and energy patterns"
            ),
            IntakeQuestion(
                question: "When do you feel most energetic and focused?",
                category: .energy,
                importance: 5,
                aiInsight: "Peak energy times should be reserved for your most important work"
            ),
            IntakeQuestion(
                question: "Do you prefer to exercise before or after work?",
                category: .preferences,
                importance: 3,
                aiInsight: "Exercise timing affects both energy levels and schedule constraints"
            )
        ]
    }
}

// MARK: - Extensions for Enhanced UI

enum TimeframeSelector: String, CaseIterable {
    case now = "Now"
    case lastTwoWeeks = "Last 2 weeks"
    case custom = "Custom"
    
    /// Short title for compact display in the new split view
    var shortTitle: String {
        switch self {
        case .now: return "Now"
        case .lastTwoWeeks: return "2wks"
        case .custom: return "Custom"
        }
    }
}

extension FlowPattern {
    /// Emoji representation for visual display
    var emoji: String {
        switch self {
        case .waterfall: return "⬇️"
        case .spiral: return "🌀" 
        case .ripple: return "〰️"
        case .wave: return "🌊"
        }
    }
}

// MARK: - Chain Templates

/// Chain templates for quick creation
struct ChainTemplate: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let activities: [String]
    let totalDuration: Int // in minutes
    let energyFlow: [EnergyType]
    
    var description: String {
        "\(activities.count) activities • \(totalDuration)min"
    }
}

// MARK: - Backfill Support

enum BackfillViewMode: String, CaseIterable {
    case timeline = "Timeline"
    case hybrid = "Hybrid"
    case list = "List"
    
    var icon: String {
        switch self {
        case .timeline: return "clock"
        case .hybrid: return "squares.below.rectangle"
        case .list: return "list.bullet"
        }
    }
}

struct QuickTemplate {
    let title: String
    let icon: String
    let duration: TimeInterval
    let energy: EnergyType
    let emoji: String
}
