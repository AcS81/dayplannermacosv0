import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject, OnboardingProgressDelegate {
    enum Step: Int, CaseIterable {
        case mood
        case createEvent
        case createPillar
        case createGoal
        case exploreGhosts
        case feedback
        case checklist
        case completed
    }
    
    @Published var isActive: Bool = false
    @Published var step: Step = .mood
    @Published var checklistAcknowledged = false
    
    private unowned let dataManager: AppDataManager
    private unowned let aiService: AIService
    private let calendar = Calendar.current
    
    init(dataManager: AppDataManager, aiService: AIService) {
        self.dataManager = dataManager
        self.aiService = aiService
        self.dataManager.onboardingDelegate = self
        restoreFromState()
    }
    
    func restoreFromState() {
        let state = dataManager.appState.onboarding
        if state.isComplete {
            isActive = false
            step = .completed
        } else {
            isActive = true
            switch state.phase {
            case .notStarted, .mood:
                step = .mood
            case .createEvent:
                step = .createEvent
            case .createPillar:
                step = .createPillar
            case .createGoal:
                step = .createGoal
            case .exploreGhosts:
                step = .exploreGhosts
            case .feedback:
                step = .feedback
            case .checklist:
                step = .checklist
            case .completed:
                step = .completed
                isActive = false
            }
        }
    }
    
    func startIfNeeded() {
        if !dataManager.appState.onboarding.isComplete {
            isActive = true
            if dataManager.appState.onboarding.phase == .notStarted {
                updateState { state in
                    state.phase = .mood
                    state.startedAt = Date()
                }
                step = .mood
            }
        }
    }
    
    func completeOnboarding() {
        updateState { state in
            state.phase = .completed
            state.completedAt = Date()
        }
        checklistAcknowledged = true
        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
            step = .completed
            isActive = false
        }
    }
    
    // MARK: - Guided Actions
    
    func createGuidedEvent() {
        let start = calendar.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTimePreservingSmallerComponents) ?? Date().addingTimeInterval(900)
        let block = TimeBlock(
            title: "Focus Sprint",
            startTime: start,
            duration: 45 * 60,
            energy: .sunrise,
            emoji: "💡",
            glassState: .liquid,
            origin: .onboarding,
            notes: "First guided event"
        )
        dataManager.addTimeBlock(block)
    }
    
    func createGuidedPillar() {
        let pillar = Pillar(
            name: "Morning Clarity",
            description: "Start the day with 30 minutes of focus",
            type: .principle,
            frequency: .daily,
            minDuration: 20 * 60,
            maxDuration: 45 * 60,
            preferredTimeWindows: [TimeWindow(startHour: 8, startMinute: 0, endHour: 10, endMinute: 0)],
            quietHours: [],
            eventConsiderationEnabled: false,
            wisdomText: "Create space to think before reacting",
            color: CodableColor(.mint),
            emoji: "🌅"
        )
        dataManager.addPillar(pillar)
    }
    
    func createGuidedGoal() {
        let goal = Goal(
            title: "Ship one meaningful thing",
            description: "Move a single project forward every day",
            state: .on,
            importance: 4,
            groups: [],
            emoji: "🚀"
        )
        dataManager.addGoal(goal)
    }
    
    func requestGuidedGhost() {
        dataManager.requestMicroUpdate(.onboarding)
    }
    
    func createGuidedFeedback() {
        if let block = dataManager.appState.currentDay.blocks.last(where: { $0.origin == .suggestion || $0.origin == .onboarding || $0.origin == .manual }) {
            dataManager.recordFeedback(
                target: .suggestion,
                targetId: block.id,
                tags: [.useful],
                comment: "Great fit",
                linkedGoalId: block.relatedGoalId,
                linkedPillarId: block.relatedPillarId
            )
        }
    }
    
    // MARK: - Delegate callbacks
    
    func onboardingDidCaptureMood(_ entry: MoodEntry) {
        updateState { state in
            state.didCaptureMood = true
            state.phase = .createEvent
        }
        advance(to: .createEvent)
    }
    
    func onboardingDidCreateBlock(_ block: TimeBlock, acceptedSuggestion: Bool) {
        if acceptedSuggestion {
            updateState { state in
                state.didAcceptGhost = true
                state.phase = .feedback
            }
            advance(to: .feedback)
        } else {
            updateState { state in
                state.didCreateEvent = true
                state.phase = .createPillar
            }
            advance(to: .createPillar)
        }
    }
    
    func onboardingDidCreatePillar(_ pillar: Pillar) {
        updateState { state in
            state.didCreatePillar = true
            state.phase = .createGoal
        }
        advance(to: .createGoal)
    }
    
    func onboardingDidCreateGoal(_ goal: Goal) {
        updateState { state in
            state.didCreateGoal = true
            state.phase = .exploreGhosts
        }
        advance(to: .exploreGhosts)
        requestGuidedGhost()
    }
    
    func onboardingDidSubmitFeedback(_ entry: FeedbackEntry) {
        updateState { state in
            state.didSubmitFeedback = true
            state.phase = .checklist
        }
        advance(to: .checklist)
    }
    
    // MARK: - Private helpers
    
    private func advance(to newStep: Step) {
        guard newStep != step else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            step = newStep
        }
    }
    
    private func updateState(_ update: (inout OnboardingState) -> Void) {
        update(&dataManager.appState.onboarding)
    }
}
