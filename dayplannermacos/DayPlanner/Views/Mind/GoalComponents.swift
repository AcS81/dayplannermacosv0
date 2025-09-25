//
//  GoalComponents.swift
//  DayPlanner
//
//  Goal-related Views and Components
//

import SwiftUI

struct EnhancedGoalsSection: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @Environment(\.highlightedGoalId) private var highlightedGoalId
    @State private var showingGoalCreator = false
    @State private var showingGoalBreakdown = false
    @State private var selectedGoal: Goal?
    @State private var showingGoalDetails = false
    @State private var feedbackGoal: Goal?
    @State private var showingGoalFeedback = false
    @State private var acknowledgedGoalId: UUID?
    @State private var focusedGoalId: UUID?
    @State private var refreshingNodeIds: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(
                    title: "Goals",
                    subtitle: "Map the arcs you want to move",
                    systemImage: "target.circle",
                    gradient: LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                )
                
                Spacer()
                
                Button(action: { showingGoalCreator = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Create new goal with AI breakdown")
            }
            
            LazyVStack(spacing: 8) {
                ForEach(dataManager.appState.goals) { goal in
                    EnhancedGoalCard(
                        goal: goal,
                        onTap: { 
                            selectedGoal = goal
                            showingGoalDetails = true
                        },
                        onBreakdown: { 
                            selectedGoal = goal
                            showingGoalBreakdown = true
                        },
                        onToggleState: {
                            toggleGoalState(goal)
                        }
                    )
                }
                
                if dataManager.appState.goals.isEmpty {
                    EmptyGoalsCard {
                        showingGoalCreator = true
                    }
                }
            }
            if !dataManager.appState.goals.isEmpty {
                GoalGraphQuickCanvas(
                    goals: dataManager.appState.goals,
                    highlightedGoalId: highlightedGoalId,
                    acknowledgedGoalId: acknowledgedGoalId,
                    focusedGoalId: focusedGoalId,
                    onSelect: { goal in focusedGoalId = goal.id },
                    onFeedbackRequest: { goal in
                        feedbackGoal = goal
                        showingGoalFeedback = true
                    }
                )
                .padding(.top, 6)
            }
            
            if let goal = focusedGoal {
                GoalGraphDetailView(
                    goal: goal,
                    refreshingNodeIds: refreshingNodeIds,
                    onTogglePin: { nodeId in
                        dataManager.toggleGoalNodePin(goal.id, nodeId: nodeId)
                    },
                    onRegenerate: { nodeId, scope in
                        refreshingNodeIds.insert(nodeId)
                        Task { @MainActor in
                            dataManager.regenerateGoalNode(goal.id, nodeId: nodeId, scope: scope)
                            refreshingNodeIds.remove(nodeId)
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingGoalCreator) {
            EnhancedGoalCreatorSheet { newGoal in
                dataManager.addGoal(newGoal)
                showingGoalCreator = false
            }
            .environmentObject(aiService)
        }
        .sheet(isPresented: $showingGoalBreakdown) {
            if let goal = selectedGoal {
                AIGoalBreakdownSheet(goal: goal) { actions in
                    processGoalBreakdown(goal: goal, actions: actions)
                    showingGoalBreakdown = false
                }
                .environmentObject(aiService)
            }
        }
        .sheet(isPresented: $showingGoalDetails) {
            if let goal = selectedGoal {
                GoalDetailSheet(
                    goal: goal,
                    onSave: { updatedGoal in
                        dataManager.updateGoal(updatedGoal)
                        showingGoalDetails = false
                    },
                    onDelete: {
                        dataManager.removeGoal(id: goal.id)
                        showingGoalDetails = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingGoalFeedback) {
            if let goal = feedbackGoal {
                FeedbackComposerView(
                    title: "Goal feedback",
                    prompt: "Share how \(goal.title) should shape upcoming plans.",
                    onSubmit: { tags, comment in
                        submitGoalFeedback(for: goal, tags: tags, comment: comment)
                    }
                )
                .frame(minWidth: 320)
            }
        }
        .onAppear {
            if focusedGoalId == nil {
                focusedGoalId = dataManager.appState.goals.first?.id
            }
        }
        .onChange(of: dataManager.appState.goals) { goals in
            guard !goals.isEmpty else {
                focusedGoalId = nil
                return
            }
            if let focused = focusedGoalId, goals.contains(where: { $0.id == focused }) {
                return
            }
            focusedGoalId = goals.first?.id
        }
    }
    
    private func toggleGoalState(_ goal: Goal) {
        var updatedGoal = goal
        switch updatedGoal.state {
        case .draft: updatedGoal.state = .on
        case .on: updatedGoal.state = .off
        case .off: updatedGoal.state = .draft
        }
        dataManager.updateGoal(updatedGoal)
    }
    
    private func processGoalBreakdown(goal: Goal, actions: [GoalBreakdownAction]) {
        var hasStageableActions = false
        
        for action in actions {
            switch action {
            case .createChain(let chain):
                // Stage chains as potential actions instead of applying immediately
                for block in chain.blocks {
                    dataManager.addTimeBlock(block)
                    hasStageableActions = true
                }
            case .createPillar(let pillar):
                // Apply pillars immediately as they don't need staging
                dataManager.addPillar(pillar)
            case .createEvent(let timeBlock):
                dataManager.addTimeBlock(timeBlock)
                hasStageableActions = true
            case .updateGoal(let updatedGoal):
                // Apply goal updates immediately
                dataManager.updateGoal(updatedGoal)
            }
        }
        
        // Only show "Ready to apply?" message if there are staged items
    }
    
    private func submitGoalFeedback(for goal: Goal, tags: [FeedbackTag], comment: String) {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        dataManager.recordFeedback(
            target: .goal,
            targetId: goal.id,
            tags: tags,
            comment: trimmed.isEmpty ? nil : trimmed
        )
        showingGoalFeedback = false
        acknowledgedGoalId = goal.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if acknowledgedGoalId == goal.id {
                acknowledgedGoalId = nil
            }
        }
    }

    private var focusedGoal: Goal? {
        let goals = dataManager.appState.goals
        guard !goals.isEmpty else { return nil }
        if let focusedGoalId, let match = goals.first(where: { $0.id == focusedGoalId }) {
            return match
        }
        return goals.first
    }
}

// MARK: - Enhanced Goal Components

struct EnhancedGoalCard: View {
    let goal: Goal
    let onTap: () -> Void
    let onBreakdown: () -> Void
    let onToggleState: () -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.highlightedGoalId) private var highlightedGoalId
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Goal state indicator with click-to-toggle
            Button(action: onToggleState) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(goalStateColor)
                    .frame(width: 6, height: 24)
                    .overlay(
                        Text(goal.state.rawValue.prefix(1))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle goal state: \(goal.state.rawValue)")
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(goal.emoji)
                        .font(.caption)
                    
                    Text(goal.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    
                    Spacer()
                }
                
                Text(goal.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("Importance: \(goal.importance)/5")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if goal.progress > 0 {
                        Text("Progress: \(Int(goal.progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    
                    if goal.needsBreakdown {
                        Text("Needs breakdown")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            if isHovering {
                HStack(spacing: 6) {
                    Button(isPinned ? "Unpin" : "Pin") {
                        dataManager.toggleGoalPin(goal.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(isPinned ? .orange : .gray)
                    .help(isPinned ? "Unpin from scheduling focus" : "Pin to raise scheduling priority")
                    
                    Button("Breakdown") {
                        onBreakdown()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("AI breakdown into chains/pillars/events")
                    
                    Button("Edit") {
                        onTap()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                Circle()
                    .fill(goal.isActive ? .green : .orange)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: cardHighlighted ? 1.5 : 1)
                )
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in isHovering = hovering }
        .onTapGesture { onTap() }
    }
    
    private var goalStateColor: Color {
        switch goal.state {
        case .draft: return .orange
        case .on: return .green
        case .off: return .gray
        }
    }

    private var isPinned: Bool {
        dataManager.isGoalPinned(goal.id)
    }
    
    private var cardHighlighted: Bool {
        highlightedGoalId == goal.id
    }
    
    private var backgroundColor: Color {
        if cardHighlighted { return Color.green.opacity(0.25) }
        return Color(.sRGB, white: 1.0, opacity: 0.12)
    }
    
    private var borderColor: Color {
        if cardHighlighted { return Color.green.opacity(0.6) }
        return goalStateColor.opacity(isHovering ? 0.4 : 0.2)
    }
}

private struct GoalGraphQuickCanvas: View {
    let goals: [Goal]
    let highlightedGoalId: UUID?
    let acknowledgedGoalId: UUID?
    let focusedGoalId: UUID?
    let onSelect: (Goal) -> Void
    let onFeedbackRequest: (Goal) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(goals) { goal in
                    GoalGraphNodeView(
                        goal: goal,
                        isHighlighted: goal.id == highlightedGoalId,
                        isAcknowledged: goal.id == acknowledgedGoalId,
                        isFocused: goal.id == focusedGoalId,
                        onSelect: { onSelect(goal) },
                        onFeedback: { onFeedbackRequest(goal) }
                    )
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct GoalGraphNodeView: View {
    let goal: Goal
    var isHighlighted: Bool
    var isAcknowledged: Bool
    var isFocused: Bool
    let onSelect: () -> Void
    let onFeedback: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(nodeGradient)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isFocused ? 0.35 : 0.15), lineWidth: isFocused ? 2 : 1)
                    )
                Text(goal.emoji)
                    .font(.title3)
            }
            Text(goal.title.badgeShortTitle(maxLength: 16))
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: isFocused ? 2 : (isHighlighted ? 1.6 : 1))
        )
        .overlay(alignment: .topTrailing) {
            if goal.isActive {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .padding(4)
            }
        }
        .overlay(alignment: .bottom) {
            if isAcknowledged {
                Text("Thanks")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.25), in: Capsule())
                    .offset(y: 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in isHovering = hovering }
        .contextMenu {
            Button("Preview goal", action: onSelect)
            Button("Give feedback", action: onFeedback)
        }
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
    
    private var nodeGradient: LinearGradient {
        LinearGradient(colors: [.green.opacity(0.45), .blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var backgroundColor: Color {
        if isFocused { return Color.green.opacity(0.18) }
        if isHighlighted { return Color.green.opacity(0.12) }
        return Color.white.opacity(isHovering ? 0.08 : 0.04)
    }
    
    private var borderColor: Color {
        if isFocused { return .green.opacity(0.8) }
        if isHighlighted { return .green.opacity(0.6) }
        return .white.opacity(0.12)
    }
}

private struct GoalGraphDetailView: View {
    let goal: Goal
    let refreshingNodeIds: Set<UUID>
    let onTogglePin: (UUID) -> Void
    let onRegenerate: (UUID, GoalGraphRegenerateScope) -> Void
    
    private var pinnedCount: Int {
        goal.graph.nodes.filter { $0.pinned }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) {
                    Text(goal.emoji)
                        .font(.title2)
                    Text(goal.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }
                .foregroundStyle(.primary)
                
                Spacer()
                
                if pinnedCount > 0 {
                    Text("Pinned nodes: \(pinnedCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            
            GoalGraphCanvasView(
                goal: goal,
                refreshingNodeIds: refreshingNodeIds,
                onTogglePin: onTogglePin,
                onRegenerate: onRegenerate
            )
            .frame(height: 280)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct GoalGraphCanvasView: View {
    let goal: Goal
    let refreshingNodeIds: Set<UUID>
    let onTogglePin: (UUID) -> Void
    let onRegenerate: (UUID, GoalGraphRegenerateScope) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let layout = GoalGraphLayout(goal: goal, size: geometry.size)
            ZStack {
                Canvas { context, size in
                    let edges = layout.edges()
                    for entry in edges {
                        var path = Path()
                        path.move(to: entry.start)
                        path.addLine(to: entry.end)
                        context.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 1)
                        if let label = entry.label, !label.isEmpty {
                            let midPoint = CGPoint(
                                x: (entry.start.x + entry.end.x) / 2,
                                y: (entry.start.y + entry.end.y) / 2
                            )
                            let text = Text(label.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                            context.draw(text.foregroundStyle(.secondary), at: midPoint)
                        }
                    }
                }
                .drawingGroup()
                
                GoalGraphRootView(goal: goal)
                    .position(layout.center)
                    .allowsHitTesting(false)
                
                ForEach(goal.graph.nodes) { node in
                    GoalGraphNodeBubbleView(
                        node: node,
                        isRefreshing: refreshingNodeIds.contains(node.id),
                        onTogglePin: { onTogglePin(node.id) },
                        onRegenerate: { scope in onRegenerate(node.id, scope) }
                    )
                    .position(layout.position(for: node))
                }
            }
        }
    }
}

private struct GoalGraphNodeBubbleView: View {
    let node: GoalGraphNode
    let isRefreshing: Bool
    let onTogglePin: () -> Void
    let onRegenerate: (GoalGraphRegenerateScope) -> Void
    
    @State private var isHovering = false
    
    private var tint: Color {
        switch node.type {
        case .subgoal: return .green
        case .task: return .blue
        case .note: return .teal
        case .resource: return .purple
        case .metric: return .orange
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(node.type.glyph)
                Text(node.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }
            .foregroundStyle(.primary)
            
            if let detail = node.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            HStack(spacing: 8) {
                Text(String(format: "w %.2f", node.weight))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(node.pinned ? "Unpin" : "Pin") {
                    onTogglePin()
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.18), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 160, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1.2)
        )
        .shadow(color: tint.opacity(0.25), radius: isHovering ? 12 : 6, y: 4)
        .overlay(alignment: .topTrailing) {
            if node.pinned {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .offset(y: -12)
            }
        }
        .overlay {
            if isRefreshing {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.3))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contextMenu {
            Button("Refresh insight") { onRegenerate(.refresh) }
            Button("Expand around this") { onRegenerate(.expand) }
            Divider()
            Button(node.pinned ? "Unpin" : "Pin", action: onTogglePin)
        }
        .onHover { hovering in isHovering = hovering }
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
    
    private var backgroundColor: Color {
        tint.opacity(0.18)
    }
    
    private var borderColor: Color {
        tint.opacity(0.35)
    }
}

private struct GoalGraphRootView: View {
    let goal: Goal
    
    var body: some View {
        VStack(spacing: 6) {
            Text(goal.emoji)
                .font(.largeTitle)
            Text(goal.title)
                .font(.footnote)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !goal.description.isEmpty {
                Text(goal.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 160)
        .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }
}

private struct GoalGraphLayout {
    struct EdgeRepresentation {
        let start: CGPoint
        let end: CGPoint
        let label: String?
    }
    
    let goal: Goal
    let size: CGSize
    
    var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }
    
    func position(for node: GoalGraphNode) -> CGPoint {
        let peers = goal.graph.nodes.filter { $0.type == node.type }
        guard let index = peers.firstIndex(of: node) else { return center }
        let count = max(1, peers.count)
        let angle = angleOffset(for: node.type) + (2 * .pi * Double(index) / Double(count))
        let radius = radius(for: node.type)
        let x = center.x + CGFloat(cos(angle)) * radius
        let y = center.y + CGFloat(sin(angle)) * radius
        return CGPoint(x: x, y: y)
    }
    
    func edges() -> [EdgeRepresentation] {
        if goal.graph.edges.isEmpty {
            return goal.graph.nodes.map { node in
                EdgeRepresentation(start: center, end: position(for: node), label: nil)
            }
        }
        return goal.graph.edges.compactMap { edge in
            guard
                let fromNode = goal.graph.nodes.first(where: { $0.id == edge.from }),
                let toNode = goal.graph.nodes.first(where: { $0.id == edge.to })
            else {
                return nil
            }
            return EdgeRepresentation(
                start: position(for: fromNode),
                end: position(for: toNode),
                label: edge.label
            )
        }
    }
    
    private func radius(for type: GoalGraphNodeType) -> CGFloat {
        let base = min(size.width, size.height) * 0.22
        switch type {
        case .subgoal: return base
        case .task: return base * 1.5
        case .note: return base * 1.85
        case .resource: return base * 2.05
        case .metric: return base * 2.25
        }
    }
    
    private func angleOffset(for type: GoalGraphNodeType) -> Double {
        switch type {
        case .subgoal: return 0
        case .task: return .pi / 6
        case .note: return .pi / 3
        case .resource: return .pi / 2
        case .metric: return .pi / 1.5
        }
    }
}

struct EmptyGoalsCard: View {
    let onCreateGoal: () -> Void
    
    var body: some View {
        Button(action: onCreateGoal) {
            VStack(spacing: 12) {
                Text("🎯")
                    .font(.title)
                    .opacity(0.6)
                
                Text("Create Your First Goal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Goals help AI understand your priorities and create actionable plans")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("+ Create Goal")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

struct EnhancedGoalCreatorSheet: View {
    let onGoalCreated: (Goal) -> Void
    @EnvironmentObject private var aiService: AIService
    @Environment(\.dismiss) private var dismiss
    
    @State private var goalTitle = ""
    @State private var goalDescription = ""
    @State private var importance = 3
    @State private var selectedState: GoalState = .draft
    @State private var selectedEmoji = "🎯"
    @State private var relatedPillarIds: [UUID] = []
    @State private var aiSuggestions = ""
    @State private var isGeneratingAI = false
    @State private var targetDate: Date?
    @State private var hasTargetDate = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Create Goal")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Goal title", text: $goalTitle)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: goalTitle) { _, _ in
                                    generateAISuggestions()
                                }
                            
                            TextField("🎯", text: $selectedEmoji)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                        
                        TextField("Description (optional)", text: $goalDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Importance: \(importance)/5")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Slider(value: Binding(
                                get: { Double(importance) },
                                set: { importance = Int($0) }
                            ), in: 1...5, step: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("State")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Picker("State", selection: $selectedState) {
                                ForEach(GoalState.allCases, id: \.self) { state in
                                    Text(state.rawValue).tag(state)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Set target date", isOn: $hasTargetDate)
                        
                        if hasTargetDate {
                            DatePicker("Target date", selection: Binding(
                                get: { targetDate ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date() },
                                set: { targetDate = $0 }
                            ), displayedComponents: .date)
                        }
                    }
                }
                
                // AI Suggestions
                if !aiSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Suggestions")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Text(aiSuggestions)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                Spacer()
            }
            .padding(24)
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Goal") {
                        createGoal()
                    }
                    .disabled(goalTitle.isEmpty)
                }
            }
        }
        .frame(width: 600, height: 700)
    }
    
    private func generateAISuggestions() {
        guard !goalTitle.isEmpty else { return }
        
        isGeneratingAI = true
        
        Task {
            do {
                let prompt = """
                User wants to create a goal: "\(goalTitle)"
                Description: "\(goalDescription)"
                
                Provide 2-3 sentence suggestion on:
                1. How to break this down into actionable steps
                2. What chains or pillars might support this goal
                3. Realistic timeline considerations
                
                Keep it encouraging and practical.
                """
                
                let context = DayContext(
                    date: Date(),
                    existingBlocks: [],
                    currentEnergy: .daylight,
                    preferredEmojis: ["🌊"],
                    availableTime: 3600,
                    mood: .crystal
                )
                
                let response = try await aiService.processMessage(prompt, context: context)
                
                await MainActor.run {
                    aiSuggestions = response.text
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiSuggestions = "Consider breaking this goal into smaller, specific actions you can track daily or weekly."
                    isGeneratingAI = false
                }
            }
        }
    }
    
    private func createGoal() {
        let newGoal = Goal(
            title: goalTitle,
            description: goalDescription,
            state: selectedState,
            importance: importance,
            groups: [],
            targetDate: hasTargetDate ? targetDate : nil,
            emoji: selectedEmoji,
            relatedPillarIds: relatedPillarIds
        )
        
        onGoalCreated(newGoal)
    }
}

struct AIGoalBreakdownSheet: View {
    let goal: Goal
    let onActionsGenerated: ([GoalBreakdownAction]) -> Void
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedGoal: Goal
    @State private var breakdownActions: [GoalBreakdownAction] = []
    @State private var isGenerating = true
    @State private var analysisText = ""
    
    init(goal: Goal, onActionsGenerated: @escaping ([GoalBreakdownAction]) -> Void) {
        self.goal = goal
        self.onActionsGenerated = onActionsGenerated
        self._editedGoal = State(initialValue: goal)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("AI Goal Breakdown")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Goal editing section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Goal Details")
                        .font(.headline)
                    
                    HStack {
                        TextField("Goal title", text: $editedGoal.title)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("🎯", text: $editedGoal.emoji)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                    
                    TextField("Description", text: $editedGoal.description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .onChange(of: editedGoal.description) { _, _ in
                            // Regenerate breakdown when description changes
                            regenerateBreakdown()
                        }
                }
                
                if isGenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing '\(editedGoal.title)' for breakdown...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !analysisText.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("AI Analysis")
                                        .font(.headline)
                                    
                                    Text(analysisText)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .padding()
                                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Suggested Actions")
                                    .font(.headline)
                                
                                ForEach(Array(breakdownActions.enumerated()), id: \.offset) { index, action in
                                    ActionCard(action: action, index: index)
                                }
                            }
                        }
                        .padding()
                    }
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Apply All & Update Goal") {
                            // Update the goal first
                            let updatedActions = breakdownActions + [.updateGoal(editedGoal)]
                            onActionsGenerated(updatedActions)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(breakdownActions.isEmpty)
                    }
                    .padding()
                }
            }
            .navigationTitle("Goal Breakdown")
        }
        .frame(width: 700, height: 600)
        .task {
            await generateBreakdown()
        }
    }
    
    private func generateBreakdown() async {
        // Simple AI-generated breakdown for now
        await MainActor.run {
            analysisText = "This goal can be achieved through consistent daily actions and strategic planning."
            
            // Create sample breakdown actions
            breakdownActions = [
                .createPillar(Pillar(
                    name: "Daily \(goal.title) Work",
                    description: "Daily activities supporting \(goal.title)",
                    frequency: .daily,
                    minDuration: 1800,
                    maxDuration: 7200,
                    preferredTimeWindows: [],
                    overlapRules: [],
                    quietHours: []
                )),
                .createChain(Chain(
                    name: "\(goal.title) Sprint",
                    blocks: [
                        TimeBlock(
                            title: "Plan \(goal.title)",
                            startTime: Date(),
                            duration: 1800,
                            energy: .daylight,
                            emoji: "💎"
                        ),
                        TimeBlock(
                            title: "Execute \(goal.title) tasks",
                            startTime: Date(),
                            duration: 3600,
                            energy: .daylight,
                            emoji: "🌊"
                        )
                    ],
                    flowPattern: .waterfall
                ))
            ]
            
            isGenerating = false
        }
    }
    
    private func regenerateBreakdown() {
        isGenerating = true
        Task {
            await generateBreakdown()
        }
    }
}

struct ActionCard: View {
    let action: GoalBreakdownAction
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(actionColor, in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(actionTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(actionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: actionIcon)
                .font(.title3)
                .foregroundStyle(actionColor)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var actionTitle: String {
        switch action {
        case .createChain(let chain): return "Create Chain: \(chain.name)"
        case .createPillar(let pillar): return "Create Pillar: \(pillar.name)"
        case .createEvent(let block): return "Schedule: \(block.title)"
        case .updateGoal: return "Update Goal Structure"
        }
    }
    
    private var actionDescription: String {
        switch action {
        case .createChain(let chain): return "\(chain.blocks.count) activities, \(chain.totalDurationMinutes)min"
        case .createPillar(let pillar): return "\(pillar.frequencyDescription) pillar"
        case .createEvent(let block): return "\(block.durationMinutes) minutes"
        case .updateGoal: return "Enhance goal structure"
        }
    }
    
    private var actionIcon: String {
        switch action {
        case .createChain: return "link"
        case .createPillar: return "building.columns"
        case .createEvent: return "calendar.badge.plus"
        case .updateGoal: return "pencil.circle"
        }
    }
    
    private var actionColor: Color {
        switch action {
        case .createChain: return .blue
        case .createPillar: return .purple
        case .createEvent: return .green
        case .updateGoal: return .orange
        }
    }
}

struct GoalDetailSheet: View {
    let goal: Goal
    let onSave: (Goal) -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var editedGoal: Goal
    @State private var showingDeleteAlert = false
    
    init(goal: Goal, onSave: @escaping (Goal) -> Void, onDelete: @escaping () -> Void) {
        self.goal = goal
        self.onSave = onSave
        self.onDelete = onDelete
        self._editedGoal = State(initialValue: goal)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Goal title", text: $editedGoal.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                    
                    TextField("Description", text: $editedGoal.description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Importance: \(editedGoal.importance)/5")
                            .font(.subheadline)
                        
                        Slider(value: Binding(
                            get: { Double(editedGoal.importance) },
                            set: { editedGoal.importance = Int($0) }
                        ), in: 1...5, step: 1)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("State")
                            .font(.subheadline)
                        
                        Picker("State", selection: $editedGoal.state) {
                            ForEach(GoalState.allCases, id: \.self) { state in
                                Text(state.rawValue).tag(state)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                if goal.progress > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Progress: \(Int(goal.progress * 100))%")
                            .font(.subheadline)
                        
                        ProgressView(value: goal.progress)
                            .progressViewStyle(.linear)
                    }
                }
                
                Spacer()
                
                HStack {
                    Button("Delete Goal") {
                        showingDeleteAlert = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    
                    Spacer()
                    
                    Button("Save Changes") {
                        onSave(editedGoal)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(editedGoal.title.isEmpty)
                }
            }
            .padding(24)
            .navigationTitle("Edit Goal")
        }
        .frame(width: 600, height: 500)
        .alert("Delete Goal", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Are you sure you want to delete '\(goal.title)'? This action cannot be undone.")
        }
    }
}

struct GoalMistCard: View {
    let goal: Goal
    @State private var isHovering = false
    @State private var showingGoalDetail = false
    
    var body: some View {
        Button(action: { showingGoalDetail = true }) {
            HStack(spacing: 10) {
                // Goal state indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(goalStateColor)
                    .frame(width: 4, height: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(goal.state.rawValue)
                            .font(.caption2)
                            .foregroundStyle(goalStateColor)
                        
                        Spacer()
                        
                        // Progress visualization
                        if goal.isActive {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        } else {
                            Circle()
                                .fill(.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(isHovering ? 0.4 : 0.2), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(goalStateColor.opacity(isHovering ? 0.3 : 0.1), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in isHovering = hovering }
        .sheet(isPresented: $showingGoalDetail) {
            Text("Goal Detail - \(goal.title)")
                .padding()
        }
    }
    
    private var goalStateColor: Color {
        switch goal.state {
        case .draft: return .orange
        case .on: return .green
        case .off: return .gray
        }
    }
}

struct GoalsSection: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var showingGoalCreator = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Goals")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("New Goal") {
                    showingGoalCreator = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            if dataManager.appState.goals.isEmpty {
                VStack(spacing: 8) {
                    Text("🎯")
                        .font(.title)
                        .opacity(0.5)
                    
                    Text("No goals yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Set goals to get AI suggestions for achieving them")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(dataManager.appState.goals) { goal in
                        GoalRowView(goal: goal)
                    }
                }
            }
        }
        .sheet(isPresented: $showingGoalCreator) {
            GoalCreationView { newGoal in
                dataManager.appState.goals.append(newGoal)
                dataManager.save()
                showingGoalCreator = false
            }
        }
    }
}

struct GoalRowView: View {
    let goal: Goal
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(goal.state.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stateColor.opacity(0.2), in: Capsule())
                        .foregroundColor(stateColor)
                    
                    Text("Importance: \(goal.importance)/5")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if goal.progress > 0 {
                ProgressView(value: goal.progress)
                    .frame(width: 60)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var stateColor: Color {
        switch goal.state {
        case .draft: return .orange
        case .on: return .green
        case .off: return .gray
        }
    }
}

struct GoalCreationView: View {
    let onCreate: (Goal) -> Void
    
    @State private var title = ""
    @State private var description = ""
    @State private var importance = 3
    @State private var state: GoalState = .draft
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Title")
                        .font(.headline)
                    TextField("e.g., Learn Swift Programming", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                    TextField("Brief description of your goal", text: $description)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Importance: \(importance)/5")
                        .font(.headline)
                    Slider(value: Binding(
                        get: { Double(importance) },
                        set: { importance = Int($0) }
                    ), in: 1...5, step: 1)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Initial State")
                        .font(.headline)
                    
                    Picker("State", selection: $state) {
                        ForEach(GoalState.allCases, id: \.self) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Goal Breakdown Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Break Down Into Actions")
                        .font(.headline)
                    
                    Text("Convert your goal into actionable steps:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("→ Create Pillar") {
                            createPillarFromGoal()
                        }
                        .buttonStyle(.bordered)
                        .help("Create a recurring pillar based on this goal")
                        
                        Button("→ Create Chain") {
                            createChainFromGoal()
                        }
                        .buttonStyle(.bordered)
                        .help("Create a sequence of activities for this goal")
                        
                        Button("→ Create Event") {
                            createEventFromGoal()
                        }
                        .buttonStyle(.bordered)
                        .help("Schedule a specific time block for this goal")
                    }
                }
                
                Spacer()
            }
            .padding(24)
            .navigationTitle("Create Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let newGoal = Goal(
                            title: title,
                            description: description,
                            state: state,
                            importance: importance,
                            groups: []
                        )
                        onCreate(newGoal)
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private func createPillarFromGoal() {
        let _ = Pillar(
            name: title,
            description: "Supporting pillar for: \(description)",
            frequency: .weekly(2),
            minDuration: 1800, // 30 minutes
            maxDuration: 7200, // 2 hours
            preferredTimeWindows: [],
            overlapRules: [],
            quietHours: []
        )
        // This would ideally show a pillar creation sheet, but for now just create directly
        // In a real app, you'd want to let users customize the pillar
    }
    
    private func createChainFromGoal() {
        let _ = Chain(
            name: "\(title) Chain",
            blocks: [
                TimeBlock(
                    title: "Plan \(title)",
                    startTime: Date(),
                    duration: 1800, // 30 minutes
                    energy: .daylight,
                    emoji: "💎"
                ),
                TimeBlock(
                    title: "Execute \(title)",
                    startTime: Date(),
                    duration: 3600, // 60 minutes
                    energy: .daylight,
                    emoji: "🌊"
                )
            ],
            flowPattern: .waterfall
        )
        // This would ideally show a chain creation sheet, but for now just create directly
    }
    
    private func createEventFromGoal() {
        let _ = TimeBlock(
            title: title,
            startTime: Date(),
            duration: 3600, // 60 minutes default
            energy: .daylight,
            emoji: "🌊"
        )
        // This would ideally show a time block creation sheet
    }
}
