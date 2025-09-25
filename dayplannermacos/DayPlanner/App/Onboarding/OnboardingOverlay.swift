import SwiftUI

struct OnboardingOverlay: View {
    @EnvironmentObject private var coordinator: OnboardingCoordinator
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    
    @State private var eventTitle: String = "Focus Sprint"
    @State private var eventDuration: Double = 45
    @State private var feedbackComment: String = "First impression is solid!"
    @State private var isAcceptingGhost = false
    
    private var shouldShowSkipButton: Bool {
        coordinator.step != .checklist
    }
    
    var body: some View {
        if coordinator.isActive, coordinator.step != .completed {
            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                onboardingCard
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .ignoresSafeArea()
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: coordinator.step)
        }
    }
    
    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iconForStep(coordinator.step))
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleForStep(coordinator.step))
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(detailForStep(coordinator.step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if shouldShowSkipButton {
                    Button(action: coordinator.completeOnboarding) {
                        Text("Skip onboarding")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.12), in: Capsule())
                }
            }
            Divider()
            stepContent
        }
        .padding(20)
        .frame(maxWidth: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch coordinator.step {
        case .mood:
            Text("Pick whichever mood matches your energy. You can change it later from the chip in the top-left.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .createEvent:
            VStack(alignment: .leading, spacing: 12) {
                TextField("Event title", text: $eventTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $eventDuration, in: 15...90, step: 15) {
                        Text("Duration")
                    }
                    Text("\(Int(eventDuration)) min")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Button(action: coordinator.createGuidedEvent) {
                    Label("Create this event", systemImage: "calendar.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            }
        case .createPillar:
            VStack(alignment: .leading, spacing: 12) {
                Text("A pillar is a principle that nudges planning. We'll start with a morning clarity ritual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: coordinator.createGuidedPillar) {
                    Label("Add Morning Clarity pillar", systemImage: "building.columns")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        case .createGoal:
            VStack(alignment: .leading, spacing: 12) {
                Text("Goals give the AI direction. We'll capture one that keeps the day purposeful.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: coordinator.createGuidedGoal) {
                    Label("Create starter goal", systemImage: "target")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        case .exploreGhosts:
            VStack(alignment: .leading, spacing: 12) {
                Text("Ghost suggestions appear in the Hourly view. Pick one that fits, or let us drop one in for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: coordinator.requestGuidedGhost) {
                    Label("Refresh suggestions", systemImage: "sparkles")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                Button(action: acceptFirstGhost)
                {
                    if isAcceptingGhost {
                        ProgressView()
                    } else {
                        Label("Accept first suggestion for me", systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAcceptingGhost)
            }
        case .feedback:
            VStack(alignment: .leading, spacing: 12) {
                Text("Feedback helps the engine adapt. Share a quick signal about the last suggestion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(action: coordinator.createGuidedFeedback) {
                        Label("Log a quick 👍", systemImage: "hand.thumbsup")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: coordinator.completeOnboarding) {
                        Label("Skip", systemImage: "forward")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .checklist:
            checklistView
        case .completed:
            EmptyView()
        }
    }
    
    private var checklistView: some View {
        let state = dataManager.appState.onboarding
        let items: [(String, Bool, String)] = [
            ("Mood logged", state.didCaptureMood, "sparkles"),
            ("Event created", state.didCreateEvent, "calendar"),
            ("Pillar added", state.didCreatePillar, "building.columns"),
            ("Goal defined", state.didCreateGoal, "target"),
            ("Ghost accepted", state.didAcceptGhost, "sparkles"),
            ("Feedback shared", state.didSubmitFeedback, "message")
        ]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.element.1 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.element.1 ? .green : .gray)
                    Text(item.element.0)
                        .font(.subheadline)
                    Spacer()
                }
            }
            Button(action: coordinator.completeOnboarding) {
                Label("You're set — start planning", systemImage: "arrow.right")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func iconForStep(_ step: OnboardingCoordinator.Step) -> String {
        switch step {
        case .mood: return "face.smiling"
        case .createEvent: return "calendar.badge.plus"
        case .createPillar: return "building.columns"
        case .createGoal: return "target"
        case .exploreGhosts: return "sparkles"
        case .feedback: return "bubble.left"
        case .checklist: return "checklist"
        case .completed: return "checkmark"
        }
    }
    
    private func titleForStep(_ step: OnboardingCoordinator.Step) -> String {
        switch step {
        case .mood: return "Set today’s mood"
        case .createEvent: return "Add your first event"
        case .createPillar: return "Define a guiding pillar"
        case .createGoal: return "Capture a starter goal"
        case .exploreGhosts: return "Try a ghost suggestion"
        case .feedback: return "Tell the engine how it felt"
        case .checklist: return "You're set"
        case .completed: return "Onboarding" 
        }
    }
    
    private func detailForStep(_ step: OnboardingCoordinator.Step) -> String {
        switch step {
        case .mood: return "Mood tunes recommendations and View insights."
        case .createEvent: return "Drop something real into the timeline to ground suggestions."
        case .createPillar: return "Pillars steer priorities without auto-booking."
        case .createGoal: return "Goals help the AI understand what matters."
        case .exploreGhosts: return "Ghosts are AI suggestions — accept one you like."
        case .feedback: return "Feedback teaches the engine instantly."
        case .checklist: return "Every piece is in place."
        case .completed: return ""
        }
    }
    
    private func acceptFirstGhost() {
        guard !isAcceptingGhost else { return }
        isAcceptingGhost = true
        Task { @MainActor in
            defer { isAcceptingGhost = false }
            let context = dataManager.createEnhancedContext(date: dataManager.appState.currentDay.date)
            let suggestions: [Suggestion]
            do {
                suggestions = try await aiService.generateSuggestions(for: context)
            } catch {
                suggestions = AIService.mockSuggestions()
            }
            let resolved = dataManager.resolveMetadata(for: suggestions)
            guard var first = resolved.first else { return }
            let slot = findFirstAvailableSlot(duration: first.duration)
            first = Suggestion(
                id: first.id,
                title: first.title,
                duration: first.duration,
                suggestedTime: slot,
                energy: first.energy,
                emoji: first.emoji,
                explanation: first.explanation,
                confidence: first.confidence,
                weight: first.weight,
                relatedGoalId: first.relatedGoalId,
                relatedGoalTitle: first.relatedGoalTitle,
                relatedPillarId: first.relatedPillarId,
                relatedPillarTitle: first.relatedPillarTitle,
                reason: first.reason,
                linkHints: first.linkHints
            )
            dataManager.applySuggestion(first)
        }
    }

    private func findFirstAvailableSlot(duration: TimeInterval) -> Date {
        let sortedBlocks = dataManager.appState.currentDay.blocks.sorted { $0.startTime < $1.startTime }
        let day = dataManager.appState.currentDay.date
        let startOfDay = Calendar.current.startOfDay(for: day)
        var cursor = max(Date(), startOfDay.addingTimeInterval(8 * 3600))
        for block in sortedBlocks {
            if block.endTime <= cursor { continue }
            let gap = block.startTime.timeIntervalSince(cursor)
            if gap >= duration {
                return cursor
            }
            cursor = block.endTime
        }
        return cursor
    }
}
