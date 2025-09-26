// MARK: - Mind Panel

import SwiftUI
import Foundation

private struct HighlightedGoalEnvironmentKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct HighlightedPillarEnvironmentKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var highlightedGoalId: UUID? {
        get { self[HighlightedGoalEnvironmentKey.self] }
        set { self[HighlightedGoalEnvironmentKey.self] = newValue }
    }
    
    var highlightedPillarId: UUID? {
        get { self[HighlightedPillarEnvironmentKey.self] }
        set { self[HighlightedPillarEnvironmentKey.self] = newValue }
    }
}

struct MindPanel: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var patternEngine: PatternLearningEngine
    @EnvironmentObject private var mindNavigator: MindNavigationModel
    @Binding var selectedTimeframe: TimeframeSelector
    
    @State private var highlightedGoalId: UUID?
    @State private var highlightedPillarId: UUID?
    @State private var viewThanksBlink = false
    
    var body: some View {
        VStack(spacing: 0) {
            MindPanelHeader(selectedTimeframe: $selectedTimeframe)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 28) {
                        MindRecommendationsSection()
                            .id(MindSection.recommendations)
                            .environmentObject(patternEngine)
                            .environmentObject(dataManager)
                            .environmentObject(aiService)
                        
                        EnhancedGoalsSection()
                        .id(MindSection.goals)
                        .environmentObject(dataManager)
                        .environmentObject(aiService)
                        .environment(\.highlightedGoalId, highlightedGoalId)
                        
                        MindPillarsSection()
                        .id(MindSection.pillars)
                        .environmentObject(dataManager)
                        .environmentObject(aiService)
                        .environment(\.highlightedPillarId, highlightedPillarId)
                        
                        MindViewSection(
                            isAcknowledged: viewThanksBlink
                        )
                        .id(MindSection.view)
                        .environmentObject(dataManager)
                        .environmentObject(patternEngine)
                        .environmentObject(mindNavigator)

                        FeedbackDebugPanel()
                            .environmentObject(dataManager)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 180)
                }
                .scrollIndicators(.hidden)
                .onChange(of: mindNavigator.pendingDestination) { _, destination in
                    guard let destination else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        proxy.scrollTo(destination.section, anchor: .top)
                    }
                    applyHighlight(for: destination)
                    mindNavigator.consumeDestination()
                }
            }
        }
        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            MindChatBar()
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }
    
    private func applyHighlight(for destination: MindDestination) {
        switch destination {
        case .goals(let id):
            highlightedGoalId = id
            highlightedPillarId = nil
        case .pillars(let id):
            highlightedPillarId = id
            highlightedGoalId = nil
        case .view:
            viewThanksBlink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                viewThanksBlink = false
            }
        case .recommendations:
            highlightedGoalId = nil
            highlightedPillarId = nil
        }
        guard highlightedGoalId != nil || highlightedPillarId != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            highlightedGoalId = nil
            highlightedPillarId = nil
        }
    }
    
}

// MARK: - Mind Panel Header

struct MindPanelHeader: View {
    @Binding var selectedTimeframe: TimeframeSelector
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mind")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("Recommendations • Goals • Pillars • View")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Timeframe selector with liquid glass styling
            TimeframeSelectorCompact(selection: $selectedTimeframe)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Timeframe Selector Compact

struct TimeframeSelectorCompact: View {
    @Binding var selection: TimeframeSelector
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(TimeframeSelector.allCases, id: \.self) { timeframe in
                Button(action: { 
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selection = timeframe
                    }
                }) {
                    Text(timeframe.shortTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            selection == timeframe 
                                ? .blue.opacity(0.15) 
                                : .clear,
                            in: Capsule()
                        )
                        .foregroundStyle(selection == timeframe ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

// MARK: - Recommendations Section

struct MindRecommendationsSection: View {
    @EnvironmentObject private var patternEngine: PatternLearningEngine
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @State private var activeFeedbackInsight: ActionableInsight?
    @State private var showingFeedbackComposer = false
    @State private var acknowledgedInsightId: UUID?
    
    private var insights: [ActionableInsight] {
        patternEngine.actionableInsights
            .filter { !$0.isExpired }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.priority > rhs.priority
            }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Recommendations",
                subtitle: "Strategic nudges refreshed every few seconds",
                systemImage: "sparkles",
                gradient: LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
            )
            
            if insights.isEmpty {
                MindEmptyState(
                    emoji: "🔄",
                    title: "Listening for signals",
                    message: "Confirm what happened today and I’ll start proposing pattern-aware moves."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(insights.prefix(4)) { insight in
                        MindRecommendationCard(
                            insight: insight,
                            isAcknowledged: acknowledgedInsightId == insight.id,
                            onFeedback: {
                                activeFeedbackInsight = insight
                                showingFeedbackComposer = true
                            }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingFeedbackComposer) {
            if let insight = activeFeedbackInsight {
                FeedbackComposerView(
                    title: "Feedback",
                    prompt: "Tell the planner how this recommendation landed.",
                    onSubmit: { tags, comment in
                        submitFeedback(tags: tags, comment: comment, for: insight)
                    }
                )
                .frame(minWidth: 320)
            }
        }
    }
    
    private func submitFeedback(tags: [FeedbackTag], comment: String, for insight: ActionableInsight) {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let (goalId, pillarId) = resolveLinks(for: insight)
        dataManager.recordFeedback(
            target: .suggestion,
            targetId: insight.id,
            tags: tags,
            comment: trimmed.isEmpty ? nil : trimmed,
            linkedGoalId: goalId,
            linkedPillarId: pillarId
        )
        showingFeedbackComposer = false
        acknowledgedInsightId = insight.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if acknowledgedInsightId == insight.id {
                acknowledgedInsightId = nil
            }
        }
    }
    
    private func resolveLinks(for insight: ActionableInsight) -> (UUID?, UUID?) {
        let payload = "\(insight.title) \(insight.description) \(insight.context) \(insight.suggestedAction)".lowercased()
        let matchedGoal = dataManager.appState.goals.first { payload.contains($0.title.lowercased()) }
        let matchedPillar = dataManager.appState.pillars.first { payload.contains($0.name.lowercased()) }
        return (matchedGoal?.id, matchedPillar?.id)
    }
}

private struct MindRecommendationCard: View {
    let insight: ActionableInsight
    var isAcknowledged: Bool
    let onFeedback: () -> Void
    
    private var priorityColor: Color {
        switch insight.priority {
        case 4...: return .green
        case 2...3: return .blue
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(insight.actionType.emoji)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(insight.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                ConfidencePill(confidence: insight.confidence)
            }
            
            HStack(spacing: 12) {
                Label("Priority \(insight.priority)", systemImage: "arrow.up.right")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(priorityColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(priorityColor)
                
                Text(insight.context)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                Button("Feedback", action: onFeedback)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if isAcknowledged {
                Text("Thanks, learning…")
                    .font(.caption2)
                    .padding(6)
                    .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
            }
        }
    }
}

private struct ConfidencePill: View {
    let confidence: Double
    
    private var formattedConfidence: String {
        String(format: "%.0f%%", confidence * 100)
    }
    
    var body: some View {
        Label(formattedConfidence, systemImage: "waveform.path")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }
}

private struct MindEmptyState: View {
    let emoji: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(emoji).font(.title2)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - View Section

struct MindViewSection: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var patternEngine: PatternLearningEngine
    @EnvironmentObject private var mindNavigator: MindNavigationModel
    var isAcknowledged: Bool
    
    private let grid = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "View",
                subtitle: "What the AI knows about you right now",
                systemImage: "brain.head.profile",
                gradient: LinearGradient(colors: [.indigo, .cyan], startPoint: .leading, endPoint: .trailing)
            )
            
            LazyVGrid(columns: grid, spacing: 12) {
                MindProfileCard(
                    title: "Facts",
                    emoji: "📌",
                    bullets: factsBullets,
                    accent: .teal,
                    isHighlighted: isAcknowledged
                )
                MindProfileCard(
                    title: "Patterns",
                    emoji: "🔍",
                    bullets: patternsBullets,
                    accent: .purple
                )
                MindProfileCard(
                    title: "Active Goals Focus",
                    emoji: "🎯",
                    bullets: goalsBullets,
                    accent: .green
                )
                MindProfileCard(
                    title: "Risks & Blocks",
                    emoji: "⚠️",
                    bullets: risksBullets,
                    accent: .orange
                )
            }
        }
    }
    
    private var factsBullets: [MindProfileBullet] {
        let mood = dataManager.appState.currentDay.mood.description
        let records = dataManager.appState.records.count
        let pillars = dataManager.appState.pillars.count
        return [
            makeBullet("Today's mood: \(mood)", id: "fact_mood") {
                mindNavigator.open(to: .view)
            },
            makeBullet("Records captured: \(records)", id: "fact_records") {
                mindNavigator.open(to: .view)
            },
            makeBullet("Active pillars: \(pillars)", id: "fact_pillars") {
                mindNavigator.open(to: .pillars(targetId: nil))
            }
        ]
    }
    
    private var patternsBullets: [MindProfileBullet] {
        let topPatterns = patternEngine.detectedPatterns.prefix(4)
        if topPatterns.isEmpty {
            return [
                makeBullet("Learning your rhythms", id: "pattern_learning") {
                    mindNavigator.open(to: .recommendations)
                }
            ]
        }
        return topPatterns.map { pattern in
            makeBullet("\(pattern.emoji) \(pattern.title.badgeShortTitle(maxLength: 22))", id: "pattern_\(pattern.id.uuidString)") {
                mindNavigator.open(to: .recommendations)
            }
        }
    }
    
    private var goalsBullets: [MindProfileBullet] {
        let pinned = dataManager.appState.pinnedGoalIds
        let goals = dataManager.appState.goals
            .filter { pinned.contains($0.id) || $0.isActive }
            .prefix(3)
        if goals.isEmpty {
            return [
                makeBullet("No pinned goals yet", id: "goal_empty") {
                    mindNavigator.open(to: .goals(targetId: nil))
                }
            ]
        }
        return goals.map { goal in
            let progress = Int(goal.progress * 100)
            let text = "\(goal.emoji) \(goal.title.badgeShortTitle(maxLength: 22)) • \(progress)%"
            return makeBullet(text, id: "goal_\(goal.id.uuidString)") {
                mindNavigator.open(to: .goals(targetId: goal.id))
            }
        }
    }
    
    private var risksBullets: [MindProfileBullet] {
        var bullets: [MindProfileBullet] = []
        if dataManager.unconfirmedBlocks.count > 0 {
            bullets.append(
                makeBullet("Confirm past blocks to keep reality fresh", id: "risk_confirm") {
                    mindNavigator.open(to: .view)
                }
            )
        }
        if dataManager.appState.pillars.filter({ $0.isActionable }).isEmpty {
            bullets.append(
                makeBullet("No actionable pillars yet—add one", id: "risk_pillars") {
                    mindNavigator.open(to: .pillars(targetId: nil))
                }
            )
        }
        if bullets.isEmpty {
            bullets.append(makeBullet("No major risks right now—stay curious", id: "risk_none"))
        }
        return bullets
    }

    private func makeBullet(_ text: String, id: String, action: (() -> Void)? = nil) -> MindProfileBullet {
        MindProfileBullet(id: id, text: text, action: action)
    }
}

private struct MindProfileCard: View {
    let title: String
    let emoji: String
    let bullets: [MindProfileBullet]
    let accent: Color
    var isHighlighted: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.title3)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            ForEach(bullets) { bullet in
                if let action = bullet.action {
                    Button(action: action) {
                        HStack(spacing: 6) {
                            Text(bullet.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                } else {
                    Text(bullet.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHighlighted ? accent.opacity(0.2) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(isHighlighted ? 0.5 : 0.18), lineWidth: isHighlighted ? 1.5 : 1)
        )
    }
}

private struct MindProfileBullet: Identifiable {
    let id: String
    let text: String
    let action: (() -> Void)?
}

// MARK: - Feedback Composer

struct FeedbackComposerView: View {
    let title: String
    let prompt: String
    let onSubmit: (_ tags: [FeedbackTag], _ comment: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTags: Set<FeedbackTag> = []
    @State private var comment: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                ForEach(FeedbackTag.allCases) { tag in
                    FeedbackTagChip(tag: tag, isSelected: selectedTags.contains(tag)) {
                        toggle(tag)
                    }
                }
            }
            
            TextField("Add a note (optional)", text: $comment)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)
            
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Submit") {
                    onSubmit(Array(selectedTags), comment)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(selectedTags.isEmpty && comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
    
    private func toggle(_ tag: FeedbackTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

private struct FeedbackTagChip: View {
    let tag: FeedbackTag
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(tag.emoji)
                Text(tag.label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(isSelected ? Color.blue : Color.primary)
            .overlay(
                Capsule().strokeBorder(Color.blue.opacity(isSelected ? 0.6 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FeedbackDebugPanel: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var isExpanded = false
    
    private var recentEntries: [FeedbackEntry] {
        Array(dataManager.appState.feedbackEntries.suffix(5).reversed())
    }
    
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    var body: some View {
        if recentEntries.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recentEntries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(tagline(for: entry))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.tagSummary)
                                .font(.caption2)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Feedback log", systemImage: "ladybug")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func tagline(for entry: FeedbackEntry) -> String {
        let timeString = relativeFormatter.localizedString(for: entry.timestamp, relativeTo: Date())
        switch entry.targetType {
        case .goal:
            if let goal = dataManager.appState.goals.first(where: { $0.id == entry.targetId }) {
                return "Goal • \(goal.title.badgeShortTitle(maxLength: 20)) • \(timeString)"
            }
            return "Goal • \(timeString)"
        case .pillar:
            if let pillar = dataManager.appState.pillars.first(where: { $0.id == entry.targetId }) {
                return "Pillar • \(pillar.name.badgeShortTitle(maxLength: 20)) • \(timeString)"
            }
            return "Pillar • \(timeString)"
        case .suggestion:
            return "Recommendation • \(timeString)"
        }
    }
}
