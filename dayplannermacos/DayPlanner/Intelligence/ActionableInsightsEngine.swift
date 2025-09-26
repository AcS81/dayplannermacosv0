//
//  ActionableInsightsEngine.swift
//  DayPlanner
//
//  Advanced insight detection system for missing/incomplete pillars and goals
//

import Foundation
import SwiftUI

/// Advanced insight detection system that identifies gaps and opportunities in user's planning system
@MainActor
class ActionableInsightsEngine: ObservableObject {
    @Published var insights: [ActionableInsight] = []
    @Published var isAnalyzing = false
    @Published var lastAnalysisTime: Date?
    
    private var dataManager: AppDataManager?
    var patternEngine: PatternLearningEngine?
    private var analysisTask: Task<Void, Never>?
    private let analysisDebounceInterval: TimeInterval = 2.0
    
    // Analysis state
    private var lastAnalyzedPillarCount = 0
    private var lastAnalyzedGoalCount = 0
    private var lastAnalyzedBlockCount = 0
    
    // Performance optimization
    private var insightCache: [String: [ActionableInsight]] = [:]
    private var lastCacheTime: Date?
    private let cacheValidityInterval: TimeInterval = 30.0 // 30 seconds
    private var analysisInProgress = false
    
    init(dataManager: AppDataManager? = nil, patternEngine: PatternLearningEngine? = nil) {
        self.dataManager = dataManager
        self.patternEngine = patternEngine
        
        // Set up bidirectional integration
        if let dataManager = dataManager {
            dataManager.insightsEngine = self
        }
    }
    
    // MARK: - Public Interface
    
    /// Trigger analysis of current state and generate insights
    func analyzeCurrentState() {
        // Check if we can use cached results
        if let lastCacheTime = lastCacheTime,
           Date().timeIntervalSince(lastCacheTime) < cacheValidityInterval,
           !insightCache.isEmpty {
            return // Use cached results
        }
        
        // Prevent concurrent analysis
        guard !analysisInProgress else { return }
        
        // Cancel any existing analysis
        analysisTask?.cancel()
        
        analysisTask = Task {
            await performAnalysis()
        }
    }
    
    /// Check if insights need refresh based on data changes
    func checkForUpdates() {
        guard let dataManager = dataManager else { return }
        
        let currentPillarCount = dataManager.appState.pillars.count
        let currentGoalCount = dataManager.appState.goals.count
        let currentBlockCount = dataManager.appState.currentDay.blocks.count
        
        // Check if significant changes occurred
        let pillarChanged = abs(currentPillarCount - lastAnalyzedPillarCount) > 0
        let goalChanged = abs(currentGoalCount - lastAnalyzedGoalCount) > 0
        let blockChanged = abs(currentBlockCount - lastAnalyzedBlockCount) > 2
        
        if pillarChanged || goalChanged || blockChanged {
            analyzeCurrentState()
        }
    }
    
    /// Clear expired insights
    func clearExpiredInsights() {
        insights.removeAll { $0.isExpired }
    }
    
    /// Dismiss a specific insight
    func dismissInsight(_ insight: ActionableInsight) {
        insights.removeAll { $0.id == insight.id }
    }
    
    // MARK: - Analysis Methods
    
    private func performAnalysis() async {
        guard let dataManager = dataManager else { return }
        
        await MainActor.run {
            isAnalyzing = true
            analysisInProgress = true
        }
        
        // Wait for debounce
        try? await Task.sleep(nanoseconds: UInt64(analysisDebounceInterval * 1_000_000_000))
        
        guard !Task.isCancelled else { 
            await MainActor.run {
                analysisInProgress = false
            }
            return 
        }
        
        var newInsights: [ActionableInsight] = []
        
        // Analyze pillars
        newInsights.append(contentsOf: await analyzePillars(dataManager.appState.pillars))
        
        // Analyze goals
        newInsights.append(contentsOf: await analyzeGoals(dataManager.appState.goals))
        
        // Analyze patterns and gaps
        newInsights.append(contentsOf: await analyzePatterns(dataManager.appState))
        
        // Integrate with pattern learning insights
        newInsights.append(contentsOf: await analyzePatternLearningInsights())
        
        // Analyze time blocks for insights
        newInsights.append(contentsOf: await analyzeTimeBlocks(dataManager.appState.currentDay.blocks))
        
        // Update state
        await MainActor.run {
            self.insights = newInsights.sorted { $0.priority > $1.priority }
            self.lastAnalysisTime = Date()
            self.isAnalyzing = false
            self.analysisInProgress = false
            
            // Update counters
            self.lastAnalyzedPillarCount = dataManager.appState.pillars.count
            self.lastAnalyzedGoalCount = dataManager.appState.goals.count
            self.lastAnalyzedBlockCount = dataManager.appState.currentDay.blocks.count
            
            // Update cache
            self.updateCache(with: newInsights)
        }
    }
    
    private func analyzePillars(_ pillars: [Pillar]) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        
        // Check for missing pillars
        if pillars.isEmpty {
            insights.append(ActionableInsight(
                title: "Create Your First Pillar",
                description: "Pillars are guiding principles that help AI make better suggestions for your day.",
                actionType: .createPillar,
                priority: 5,
                confidence: 0.9,
                suggestedAction: "Create a pillar for your core values or daily routines",
                context: "No pillars found in your system"
            ))
        } else {
            // Check for incomplete pillars
            for pillar in pillars {
                let validation = pillar.validate()
                if validation.needsEnhancement {
                    insights.append(ActionableInsight(
                        title: "Enhance \(pillar.name)",
                        description: "This pillar could be more effective with additional metadata.",
                        actionType: .updateGoal,
                        priority: 3,
                        confidence: validation.completeness,
                        suggestedAction: "Add values, habits, constraints, or quiet hours to \(pillar.name)",
                        context: "Pillar completeness: \(validation.completenessPercentage)%"
                    ))
                }
            }
            
            // Check for pillar coverage gaps
            let pillarNames = pillars.map { $0.name.lowercased() }
            let commonPillars = ["health", "work", "family", "learning", "rest", "exercise", "creativity"]
            let missingPillars = commonPillars.filter { commonPillar in
                !pillarNames.contains { $0.contains(commonPillar) }
            }
            
            if !missingPillars.isEmpty {
                insights.append(ActionableInsight(
                    title: "Consider Adding Core Pillars",
                    description: "You might benefit from pillars covering: \(missingPillars.joined(separator: ", "))",
                    actionType: .createPillar,
                    priority: 2,
                    confidence: 0.7,
                    suggestedAction: "Create pillars for missing life areas",
                    context: "Missing common pillar types"
                ))
            }
        }
        
        return insights
    }
    
    private func analyzeGoals(_ goals: [Goal]) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        
        // Check for missing goals
        if goals.isEmpty {
            insights.append(ActionableInsight(
                title: "Set Your First Goal",
                description: "Goals help you stay focused on what matters most.",
                actionType: .updateGoal,
                priority: 4,
                confidence: 0.8,
                suggestedAction: "Create a goal for something you want to achieve",
                context: "No goals found in your system"
            ))
        } else {
            // Check for draft goals
            let draftGoals = goals.filter { $0.state == .draft }
            if !draftGoals.isEmpty {
                insights.append(ActionableInsight(
                    title: "Activate Draft Goals",
                    description: "You have \(draftGoals.count) goal(s) in draft that could be activated.",
                    actionType: .updateGoal,
                    priority: 3,
                    confidence: 0.8,
                    suggestedAction: "Review and activate your draft goals",
                    context: "\(draftGoals.count) draft goals found"
                ))
            }
            
            // Check for goals without breakdown
            let goalsNeedingBreakdown = goals.filter { $0.needsBreakdown }
            if !goalsNeedingBreakdown.isEmpty {
                insights.append(ActionableInsight(
                    title: "Break Down Your Goals",
                    description: "Some goals need to be broken down into actionable steps.",
                    actionType: .updateGoal,
                    priority: 3,
                    confidence: 0.7,
                    suggestedAction: "Add tasks and sub-goals to make your goals actionable",
                    context: "\(goalsNeedingBreakdown.count) goals need breakdown"
                ))
            }
            
            // Check for overdue goals
            let overdueGoals = goals.filter { goal in
                guard let targetDate = goal.targetDate else { return false }
                return targetDate < Date() && goal.state == .on
            }
            
            if !overdueGoals.isEmpty {
                insights.append(ActionableInsight(
                    title: "Review Overdue Goals",
                    description: "Some goals have passed their target date and may need adjustment.",
                    actionType: .updateGoal,
                    priority: 4,
                    confidence: 0.9,
                    suggestedAction: "Update target dates or adjust goal scope",
                    context: "\(overdueGoals.count) overdue goals found"
                ))
            }
        }
        
        return insights
    }
    
    private func analyzePatterns(_ appState: AppState) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        
        // Analyze time block patterns
        let blocks = appState.currentDay.blocks
        if blocks.isEmpty {
            insights.append(ActionableInsight(
                title: "Plan Your Day",
                description: "Start by adding some activities to your day.",
                actionType: .createBlock,
                priority: 3,
                confidence: 0.8,
                suggestedAction: "Add time blocks for your planned activities",
                context: "No time blocks scheduled"
            ))
        } else {
            // Check for energy distribution
            let energyCounts = Dictionary(grouping: blocks, by: { $0.energy })
            let hasVariety = energyCounts.count > 1
            
            if !hasVariety {
                insights.append(ActionableInsight(
                    title: "Balance Your Energy",
                    description: "Consider mixing different types of activities throughout your day.",
                    actionType: .adjustEnergy,
                    priority: 2,
                    confidence: 0.6,
                    suggestedAction: "Add variety to your energy levels",
                    context: "All activities have the same energy type"
                ))
            }
            
            // Check for gaps in schedule
            let sortedBlocks = blocks.sorted { $0.startTime < $1.startTime }
            var gaps: [TimeInterval] = []
            
            for i in 0..<(sortedBlocks.count - 1) {
                let currentEnd = sortedBlocks[i].endTime
                let nextStart = sortedBlocks[i + 1].startTime
                let gap = nextStart.timeIntervalSince(currentEnd)
                
                if gap > 3600 { // Gaps larger than 1 hour
                    gaps.append(gap)
                }
            }
            
            if !gaps.isEmpty {
                insights.append(ActionableInsight(
                    title: "Fill Schedule Gaps",
                    description: "You have \(gaps.count) significant gaps in your schedule.",
                    actionType: .createBlock,
                    priority: 2,
                    confidence: 0.7,
                    suggestedAction: "Add activities to fill time gaps",
                    context: "\(gaps.count) gaps found in schedule"
                ))
            }
        }
        
        return insights
    }
    
    private func analyzeTimeBlocks(_ blocks: [TimeBlock]) async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        
        // Check for blocks without related goals or pillars
        let unlinkedBlocks = blocks.filter { block in
            block.relatedGoalId == nil && block.relatedPillarId == nil
        }
        
        if unlinkedBlocks.count > blocks.count / 2 {
            insights.append(ActionableInsight(
                title: "Connect Activities to Goals",
                description: "Many of your activities aren't linked to specific goals or pillars.",
                actionType: .updateGoal,
                priority: 2,
                confidence: 0.6,
                suggestedAction: "Link your activities to relevant goals and pillars",
                context: "\(unlinkedBlocks.count) unlinked activities"
            ))
        }
        
        // Check for blocks with low confidence
        let lowConfidenceBlocks = blocks.filter { block in
            (block.suggestionConfidence ?? 1.0) < 0.5
        }
        
        if !lowConfidenceBlocks.isEmpty {
            insights.append(ActionableInsight(
                title: "Review Low-Confidence Activities",
                description: "Some activities were created with low confidence and may need adjustment.",
                actionType: .modifySchedule,
                priority: 2,
                confidence: 0.7,
                suggestedAction: "Review and adjust activities with low confidence scores",
                context: "\(lowConfidenceBlocks.count) low-confidence activities"
            ))
        }
        
        return insights
    }
    
    private func analyzePatternLearningInsights() async -> [ActionableInsight] {
        var insights: [ActionableInsight] = []
        
        guard let patternEngine = patternEngine else { return insights }
        
        // Convert pattern learning insights to actionable insights
        for patternInsight in patternEngine.actionableInsights {
            let actionType: InsightActionType
            
            // Map pattern insight action types to actionable insight types
            switch patternInsight.actionType {
            case .createBlock:
                actionType = .createBlock
            case .modifySchedule:
                actionType = .modifySchedule
            case .createChain:
                actionType = .createChain
            case .updateGoal:
                actionType = .updateGoal
            case .createPillar:
                actionType = .createPillar
            case .adjustEnergy:
                actionType = .adjustEnergy
            case .optimizeTiming:
                actionType = .optimizeTiming
            }
            
            let actionableInsight = ActionableInsight(
                title: patternInsight.title,
                description: patternInsight.description,
                actionType: actionType,
                priority: patternInsight.priority,
                confidence: patternInsight.confidence,
                suggestedAction: patternInsight.suggestedAction,
                context: patternInsight.context,
                expiresAt: patternInsight.expiresAt
            )
            
            insights.append(actionableInsight)
        }
        
        // Add insights based on pattern learning confidence
        if patternEngine.confidence < 0.5 {
            insights.append(ActionableInsight(
                title: "Build Pattern Intelligence",
                description: "The system is still learning your patterns. More data will improve suggestions.",
                actionType: .createBlock,
                priority: 1,
                confidence: 0.8,
                suggestedAction: "Continue using the app to help the AI learn your preferences",
                context: "Pattern learning confidence: \(Int(patternEngine.confidence * 100))%"
            ))
        }
        
        return insights
    }
    
    // MARK: - Performance Optimization Methods
    
    private func updateCache(with insights: [ActionableInsight]) {
        let cacheKey = generateCacheKey()
        insightCache[cacheKey] = insights
        lastCacheTime = Date()
        
        // Clean up old cache entries (keep only last 5)
        if insightCache.count > 5 {
            let sortedKeys = insightCache.keys.sorted()
            for key in sortedKeys.prefix(insightCache.count - 5) {
                insightCache.removeValue(forKey: key)
            }
        }
    }
    
    private func generateCacheKey() -> String {
        guard let dataManager = dataManager else { return "default" }
        
        let pillarCount = dataManager.appState.pillars.count
        let goalCount = dataManager.appState.goals.count
        let blockCount = dataManager.appState.currentDay.blocks.count
        
        return "\(pillarCount)-\(goalCount)-\(blockCount)"
    }
    
    /// Get cached insights if available and valid
    private func getCachedInsights() -> [ActionableInsight]? {
        guard let lastCacheTime = lastCacheTime,
              Date().timeIntervalSince(lastCacheTime) < cacheValidityInterval else {
            return nil
        }
        
        let cacheKey = generateCacheKey()
        return insightCache[cacheKey]
    }
    
    /// Clear expired cache entries
    private func clearExpiredCache() {
        guard let lastCacheTime = lastCacheTime,
              Date().timeIntervalSince(lastCacheTime) > cacheValidityInterval else {
            return
        }
        
        insightCache.removeAll()
        self.lastCacheTime = nil
    }
}

// MARK: - Insight Action Types
// Note: InsightActionType and ActionableInsight are defined in PatternLearning.swift

// MARK: - Extensions

extension ActionableInsightsEngine {
    /// Get insights filtered by priority and confidence
    func getHighPriorityInsights() -> [ActionableInsight] {
        return insights.filter { $0.priority >= 4 && $0.confidence >= 0.7 }
    }
    
    /// Get insights for a specific action type
    func getInsights(for actionType: InsightActionType) -> [ActionableInsight] {
        return insights.filter { $0.actionType == actionType }
    }
    
    /// Get the most urgent insight
    func getMostUrgentInsight() -> ActionableInsight? {
        return insights.max { $0.priority < $1.priority }
    }
}
