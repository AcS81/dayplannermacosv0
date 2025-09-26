//
//  ActionBarViews.swift
//  DayPlanner
//
//  Action Bar and AI Interaction Components
//

import SwiftUI

// MARK: - Action Bar View

struct ActionBarView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @StateObject private var speechService = SpeechService()
    @State private var messageText = ""
    @State private var isVoiceMode = false
    @State private var pendingSuggestions: [Suggestion] = []
    @State private var ephemeralInsight: String?
    @State private var showInsightTimer: Timer?
    @State private var lastResponse = ""
    @State private var lastConfidence: Double = 0.0
    @State private var messageHistory: [AIMessage] = []
    @State private var showHistory = false
    
    var body: some View {
        VStack(spacing: 8) {
                // Enhanced ephemeral insight with better styling
            if let insight = ephemeralInsight {
                HStack(spacing: 12) {
                    // Thinking indicator
                    if insight.contains("Analyzing") || insight.contains("Processing") {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    }
                    
                    Text(insight)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                        .animation(.easeInOut(duration: 0.3), value: insight)
                    
                    Spacer()
                    
                    if !insight.contains("...") {
                        Button("💬") {
                            promoteInsightToTranscript(insight)
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.blue.opacity(0.2), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)))
            }
            
            // Main action bar
            HStack(spacing: 12) {
                // History toggle
                Button(action: { showHistory.toggle() }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                // Voice/Text toggle
                Button(action: { isVoiceMode.toggle() }) {
                    Image(systemName: isVoiceMode ? "mic.fill" : "text.bubble")
                        .foregroundColor(isVoiceMode ? .red : .blue)
                }
                .buttonStyle(.plain)
                
                // Message input or voice indicator
                if isVoiceMode {
                    HStack {
                        Circle()
                            .fill(speechService.isListening ? .red : .gray)
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: speechService.isListening)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speechService.isListening ? "Listening..." : 
                                 speechService.canStartListening ? "Hold to speak" : "Speech unavailable")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            
                            // Show partial or final transcription
                            if !speechService.partialText.isEmpty {
                                Text(speechService.partialText)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .italic()
                            } else if !speechService.transcribedText.isEmpty {
                                Text(speechService.transcribedText)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onLongPressGesture(
                        minimumDuration: 0.1,
                        perform: { endVoiceInput() },
                        onPressingChanged: { pressing in
                            if pressing && speechService.canStartListening {
                                startVoiceInput()
                            } else {
                                endVoiceInput()
                            }
                        }
                    )
                    .disabled(!speechService.canStartListening)
                } else {
                    TextField("Ask AI or describe what you need...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            sendMessage()
                        }
                }
                
                // Send button (disabled in voice mode)
                if !isVoiceMode {
                    Button("Send") {
                        sendMessage()
                    }
                    .disabled(messageText.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            
            // AI Response (if available)
            if !lastResponse.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(lastResponse)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Confidence indicator
                        if lastConfidence > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(confidenceColor(lastConfidence))
                                    .frame(width: 6, height: 6)
                                
                                Text("\(Int(lastConfidence * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // TTS button
                    Button(speechService.isSpeaking ? "🔇" : "🔊") {
                        if speechService.isSpeaking {
                            speechService.stopSpeaking()
                        } else {
                            speechService.speak(text: lastResponse)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Staged suggestions with Yes/No (Nothing stages until explicit Yes)
            if !pendingSuggestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(pendingSuggestions) { suggestion in
                        StagedSuggestionView(
                            suggestion: suggestion,
                            onAccept: { acceptSuggestion(suggestion) },
                            onReject: { rejectSuggestion(suggestion) }
                        )
                    }
                    
                    // Batch actions if multiple suggestions
                    if pendingSuggestions.count > 1 {
                        HStack {
                            Button("Accept All") {
                                acceptAllSuggestions()
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Reject All") {
                                rejectAllSuggestions()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            
            // Undo countdown (10-second window)
        }
        .sheet(isPresented: $showHistory) {
            MessageHistoryView(messages: messageHistory, onDismiss: { showHistory = false })
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Message Handling
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let message = messageText
        messageText = ""
        
        // Add to history
        messageHistory.append(AIMessage(text: message, isUser: true, timestamp: Date()))
        
        Task {
            // Show enhanced thinking state
            await MainActor.run {
                showEphemeralInsight("✨ Analyzing your request...")
            }
            
            do {
                // Get AI response
                let context = createContext()
                
                await MainActor.run {
                    showEphemeralInsight("🧠 Processing with AI...")
                }
                
                let response = try await aiService.processMessage(message, context: context)
                
                   await MainActor.run {
                       lastResponse = response.text
                       lastConfidence = response.confidence

                       // Handle different types of AI responses based on confidence and action type
                       if let actionType = response.actionType {
                           handleSmartAIResponse(response, actionType: actionType, message: message)
                       } else {
                           // Fallback to legacy behavior
                           handleLegacyResponse(response, message: message)
                       }
                    
                    // Add AI response to history
                    messageHistory.append(AIMessage(text: response.text, isUser: false, timestamp: Date()))
                }
            } catch {
                await MainActor.run {
                    showEphemeralInsight("Sorry, I couldn't process that right now")
                    lastResponse = "I'm having trouble connecting right now. Please try again."
                    messageHistory.append(AIMessage(text: "Error: \(error.localizedDescription)", isUser: false, timestamp: Date()))
                }
            }
        }
    }
    
    // MARK: - Voice Input
    
    // MARK: - Suggestion Handling (Staging System)
    
    private func acceptSuggestion(_ suggestion: Suggestion) {
        // Use new staging system directly
        dataManager.applySuggestion(suggestion)
        
        // Remove from pending
        pendingSuggestions.removeAll { $0.id == suggestion.id }
        
        showEphemeralInsight("Staged '\(suggestion.title)' for your review")
    }
    
    private func rejectSuggestion(_ suggestion: Suggestion) {
        dataManager.rejectSuggestion(suggestion)
        pendingSuggestions.removeAll { $0.id == suggestion.id }
        showEphemeralInsight("No problem, I'll learn from this")
    }
    
    private func acceptAllSuggestions() {
        for suggestion in pendingSuggestions {
            dataManager.applySuggestion(suggestion)
        }
        let count = pendingSuggestions.count
        pendingSuggestions.removeAll()
        showEphemeralInsight("Staged \(count) suggestion\(count == 1 ? "" : "s") for your review")
    }
    
    private func rejectAllSuggestions() {
        for suggestion in pendingSuggestions {
            dataManager.rejectSuggestion(suggestion)
        }
        pendingSuggestions.removeAll()
        showEphemeralInsight("All rejected - I'll remember this")
    }
    
    
    // MARK: - Helper Methods
    
    private func showEphemeralInsight(_ text: String) {
        ephemeralInsight = text
        showInsightTimer?.invalidate()
        showInsightTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                ephemeralInsight = nil
            }
        }
    }
    
    private func promoteInsightToTranscript(_ insight: String) {
        // Add insight to permanent message history
        messageHistory.append(AIMessage(text: "💡 \(insight)", isUser: false, timestamp: Date()))
        ephemeralInsight = nil
        showEphemeralInsight("Added to conversation history")
    }
    
    
    private func startVoiceInput() {
        Task {
            do {
                try await speechService.startListening()
                showEphemeralInsight("🎤 Listening...")
            } catch {
                showEphemeralInsight("Speech recognition error: \(error.localizedDescription)")
            }
        }
    }
    
    private func endVoiceInput() {
        Task {
            await speechService.stopListening()
            
            // Process the transcribed text
            if !speechService.transcribedText.isEmpty {
                messageText = speechService.transcribedText
                showEphemeralInsight("Voice input captured: \(speechService.transcribedText.prefix(30))...")
                
                // Automatically send the transcribed message
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    sendMessage()
                }
            } else {
                showEphemeralInsight("No speech detected")
            }
        }
    }
    
    // Detect if user is asking AI to schedule something
    private func isSchedulingRequest(_ message: String) -> Bool {
        let schedulingKeywords = [
            "schedule", "book", "add", "create", "plan", "set up", "arrange", 
            "put in", "block", "reserve", "calendar", "time for", "remind me"
        ]
        
        let lowerMessage = message.lowercased()
        return schedulingKeywords.contains { keyword in
            lowerMessage.contains(keyword)
        }
    }
    
    // MARK: - Smart AI Response Handlers
    
    private func handleSmartAIResponse(_ response: AIResponse, actionType: AIActionType, message: String) {
        switch actionType {
        case .createEvent:
            handleEventCreation(response, message: message)
        case .createGoal:
            handleGoalCreation(response, message: message)
        case .createPillar:
            handlePillarCreation(response, message: message)
        case .createChain:
            handleChainCreation(response, message: message)
        case .suggestActivities:
            handleActivitySuggestions(response, message: message)
        case .generalChat:
            handleGeneralChat(response, message: message)
        }
    }
    
    private func handleEventCreation(_ response: AIResponse, message: String) {
        if response.confidence >= 0.7 { // Lowered threshold for better UX
            // High confidence - create the event directly with full details
            if let firstSuggestion = response.suggestions.first {
                let extractedTime = extractDateFromMessage(message)
                let suggestionTime = firstSuggestion.suggestedTime

                let proposedStart: Date
                if let extractedTime {
                    let difference = abs(extractedTime.timeIntervalSince(suggestionTime))
                    proposedStart = difference > 60 ? extractedTime : suggestionTime
                } else {
                    proposedStart = suggestionTime
                }

                let targetTime = findNextAvailableTime(near: proposedStart, duration: firstSuggestion.duration)

                // Create fully populated time block
                let timeBlock = TimeBlock(
                    title: firstSuggestion.title,
                    startTime: targetTime,
                    duration: firstSuggestion.duration,
                    energy: firstSuggestion.energy,
                    emoji: firstSuggestion.emoji,
                    glassState: .crystal, // AI-created
                    relatedGoalId: findRelatedGoal(for: firstSuggestion.title)?.id,
                    relatedPillarId: findRelatedPillar(for: firstSuggestion.title)?.id
                )
                
                dataManager.addTimeBlock(timeBlock)
                
                // Award XP for successful AI scheduling
                dataManager.appState.addXP(5, reason: "AI scheduled event")
                
                let dateString = Calendar.current.isDate(targetTime, inSameDayAs: Date()) ? "today" : targetTime.dayString
                showEphemeralInsight("✨ Created \(timeBlock.title) for \(dateString) at \(targetTime.timeString)!")
                
                // Create related suggestions if this event could be part of a chain
                suggestRelatedActivities(for: timeBlock, confidence: response.confidence)
            }
        } else if response.confidence >= 0.5 {
            // Medium confidence - show enhanced suggestion with more context
            pendingSuggestions = response.suggestions.map { suggestion in
                var enhanced = suggestion
                enhanced.explanation = "\(suggestion.explanation) (Confidence: \(Int(response.confidence * 100))%)"
                return enhanced
            }
            showEphemeralInsight("💡 I think you want to create an event. Here's my best guess:")
        } else {
            // Low confidence - ask for clarification
            showEphemeralInsight("🤔 Could you be more specific about what you'd like to schedule?")
        }
    }
    
    private func handleGoalCreation(_ response: AIResponse, message: String) {
        if response.confidence >= 0.8 { // Lowered threshold for better UX
            // High confidence - create the goal directly with full population
            if let createdItem = response.createdItems?.first(where: { $0.type == .goal }),
               let goalData = createdItem.data as? [String: Any] {
                
                // Create fully populated goal with simplified fallbacks
                    let goal = Goal(
                    title: goalData["title"] as? String ?? "New Goal",
                    description: goalData["description"] as? String ?? "AI-created goal based on your request",
                        state: .on,
                    importance: goalData["importance"] as? Int ?? 3,
                    groups: [],
                    targetDate: nil,
                    emoji: goalData["emoji"] as? String ?? "🎯",
                    relatedPillarIds: []
                )
                
                    dataManager.addGoal(goal)
                
                // Award XP for goal creation
                dataManager.appState.addXP(15, reason: "AI created goal")
                
                showEphemeralInsight("🎯 Created goal: \(goal.title) (Importance: \(goal.importance)/5)")
                
                // Suggest immediate actions with delay
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        showEphemeralInsight("💡 Create supporting activities for '\(goal.title)'?")
                    }
                }
            }
        } else if response.confidence >= 0.6 {
            // Medium confidence - show clarification with suggestions
            showEphemeralInsight("🤔 I think you want to create a goal. What's the main outcome you're hoping for?")
        } else {
            // Low confidence - ask for more details
            showEphemeralInsight("💭 I'd love to help you create a goal! Tell me what you want to achieve.")
        }
    }
    
    private func handlePillarCreation(_ response: AIResponse, message: String) {
        if response.confidence >= 0.85 { // Lowered threshold slightly
            // High confidence - create the pillar directly with full details
            if let createdItem = response.createdItems?.first(where: { $0.type == .pillar }) {
                
                // Use centralized parsing utility for consistent pillar creation
                let pillar: Pillar
                if let pillarData = createdItem.data as? [String: Any] {
                    pillar = Pillar.fromAI(pillarData)
                    pillar = Pillar(
                        name: pillarData["name"] as? String ?? "New Pillar",
                        description: pillarData["description"] as? String ?? "AI-created pillar",
                        frequency: .weekly(1),
                        quietHours: [],
                        wisdomText: pillarData["wisdom"] as? String,
                        values: pillarData["values"] as? [String] ?? [],
                        habits: pillarData["habits"] as? [String] ?? [],
                        constraints: pillarData["constraints"] as? [String] ?? [],
                        color: CodableColor(.purple),
                        emoji: pillarData["emoji"] as? String ?? "🏛️"
                    )
                } else if let pillarObject = createdItem.data as? Pillar {
                    pillar = pillarObject
                } else {
                    return
                }
                
                dataManager.addPillar(pillar)
                
                // Award XP for pillar creation
                dataManager.appState.addXP(20, reason: "AI created pillar")
                
                showEphemeralInsight("🏛️ Created principle pillar: \(pillar.name)")
                
                // Suggest scheduling if it's actionable
                if pillar.isActionable {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            showEphemeralInsight("📅 Schedule '\(pillar.name)' activity?")
                        }
                    }
                }
            }
        } else if response.confidence >= 0.6 {
            // Medium confidence - ask for clarification
            showEphemeralInsight("🤔 I think you want to create a pillar. Is this a recurring activity or a guiding principle?")
        } else {
            // Low confidence - ask for more details
            showEphemeralInsight("💭 Tell me more about this pillar - is it something you want to do regularly or a principle to guide decisions?")
        }
    }
    
    private func handleChainCreation(_ response: AIResponse, message: String) {
        if response.confidence >= 0.75 {
            // High confidence - create the chain directly with full details
            if let createdItem = response.createdItems?.first(where: { $0.type == .chain }),
               let chainData = createdItem.data as? [String: Any] {
                
                // Create fully populated chain with simplified fallbacks
                let chain = Chain(
                    name: chainData["name"] as? String ?? "New Chain",
                    blocks: [TimeBlock(title: "Activity", startTime: Date(), duration: 1800, energy: .daylight, emoji: "🌊")],
                    flowPattern: FlowPattern(rawValue: chainData["flowPattern"] as? String ?? "waterfall") ?? .waterfall,
                    emoji: chainData["emoji"] as? String ?? "🔗",
                    relatedGoalId: nil,
                    relatedPillarId: nil
                )
                
                dataManager.addChain(chain)
                
                // Award XP for chain creation
                dataManager.appState.addXP(10, reason: "AI created chain")
                
                showEphemeralInsight("🔗 Created chain: \(chain.name) with \(chain.blocks.count) activities")
                
                // Suggest applying the chain
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        showEphemeralInsight("⚡ Apply '\(chain.name)' now?")
                    }
                }
            }
        } else if response.confidence >= 0.6 {
            // Medium confidence - show suggestions but ask for clarification
            pendingSuggestions = response.suggestions
            showEphemeralInsight("💡 I think you want to create a chain. Should these activities be linked together?")
        } else {
            // Low confidence - ask for more details
            showEphemeralInsight("🤔 Tell me more about this chain - what activities should be connected?")
        }
    }
    
    private func handleActivitySuggestions(_ response: AIResponse, message: String) {
        pendingSuggestions = response.suggestions
        if !response.suggestions.isEmpty {
            showEphemeralInsight("💡 Found \(response.suggestions.count) suggestion\(response.suggestions.count == 1 ? "" : "s") for you")
        } else {
            showEphemeralInsight("Here's what I think...")
        }
    }
    
    private func handleGeneralChat(_ response: AIResponse, message: String) {
        // For general chat, just show suggestions if any
        if !response.suggestions.isEmpty {
            pendingSuggestions = response.suggestions
            showEphemeralInsight("💭 Here's a thought...")
        } else {
            showEphemeralInsight("💬 Thanks for sharing!")
        }
    }
    
    private func handleLegacyResponse(_ response: AIResponse, message: String) {
        // Enhanced legacy handling with smart confidence-based decisions
        if isSchedulingRequest(message) && !response.suggestions.isEmpty {
            // Determine if we should create directly or stage based on multiple factors
            let shouldCreateDirectly = shouldCreateEventsDirectly(response: response, message: message)
            
            if shouldCreateDirectly {
                // Create events directly with enhanced details
            let targetDate = extractDateFromMessage(message) ?? Date()
                var createdCount = 0
            
            for (index, suggestion) in response.suggestions.enumerated() {
                let baseProposal = targetDate.addingTimeInterval(Double(index * 30 * 60))
                let suggestedTime = findNextAvailableTime(near: baseProposal, duration: suggestion.duration)
                    
                    // Create fully populated time block with relationships
                    let timeBlock = TimeBlock(
                        title: suggestion.title,
                        startTime: suggestedTime,
                        duration: suggestion.duration,
                        energy: suggestion.energy,
                        emoji: suggestion.emoji,
                        glassState: .crystal, // AI-created
                        relatedGoalId: findRelatedGoal(for: suggestion.title)?.id,
                        relatedPillarId: findRelatedPillar(for: suggestion.title)?.id
                    )
                    
                    dataManager.addTimeBlock(timeBlock)
                    createdCount += 1
                }
                
            let dateString = Calendar.current.isDate(targetDate, inSameDayAs: Date()) ? "today" : targetDate.dayString
                showEphemeralInsight("✨ Created \(createdCount) event\(createdCount == 1 ? "" : "s") for \(dateString)!")
            
                // Award XP for successful AI scheduling
                dataManager.appState.addXP(createdCount * 5, reason: "AI direct scheduling")
                
            pendingSuggestions = []
        } else {
                // Stage for user approval with enhanced context
                pendingSuggestions = response.suggestions.map { suggestion in
                    var enhanced = suggestion
                    enhanced.explanation = "\(suggestion.explanation) (Auto-suggested based on your request)"
                    return enhanced
                }
                showEphemeralInsight("💡 Here's what I suggest for your request:")
            }
        } else {
            // Regular suggestion flow with confidence indication
            pendingSuggestions = response.suggestions
            if !response.suggestions.isEmpty {
                let avgConfidence = response.suggestions.map(\.confidence).reduce(0, +) / Double(response.suggestions.count)
                let confidenceText = avgConfidence > 0.8 ? "strong" : avgConfidence > 0.6 ? "good" : "rough"
                showEphemeralInsight("💡 Found \(response.suggestions.count) \(confidenceText) suggestion\(response.suggestions.count == 1 ? "" : "s") for you")
            } else {
                showEphemeralInsight("💬 I understand, but need more details to help you")
            }
        }
    }
    
    // MARK: - Smart Decision Making
    
    private func shouldCreateEventsDirectly(response: AIResponse, message: String) -> Bool {
        // Multiple factors determine if we should create directly
        let factors: [Double] = [
            response.confidence, // Base confidence
            isSchedulingRequest(message) ? 0.2 : 0.0, // Clear scheduling intent
            hasSpecificTime(message) ? 0.2 : 0.0, // Time specified
            hasUrgencyIndicators(message) ? 0.15 : 0.0, // Urgency words
            response.suggestions.count == 1 ? 0.1 : 0.0, // Single clear suggestion
            lastConfidence > 0.7 ? 0.1 : 0.0 // Recent successful interactions
        ]
        
        let combinedConfidence = factors.reduce(0, +) / Double(factors.count)
        return combinedConfidence >= 0.65 // Lower threshold for better UX
    }
    
    private func hasSpecificTime(_ message: String) -> Bool {
        let timePatterns = ["at ", ":\\d{2}", "am", "pm", "tomorrow", "today", "now", "in \\d+"]
        return timePatterns.contains { pattern in
            message.range(of: pattern, options: .regularExpression) != nil
        }
    }
    
    private func hasUrgencyIndicators(_ message: String) -> Bool {
        let urgencyWords = ["urgent", "asap", "immediately", "now", "quickly", "soon", "today"]
        let lowerMessage = message.lowercased()
        return urgencyWords.contains { lowerMessage.contains($0) }
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func createContext() -> DayContext {
        dataManager.createEnhancedContext()
    }
    
    // MARK: - AI Scheduling Helper Functions
    
    private func extractDateFromMessage(_ message: String) -> Date? {
        let lowercased = message.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if let relativeHours = try? NSRegularExpression(pattern: "in\\s+(\\d+)\\s+(hour|hours|hr|hrs)", options: .caseInsensitive),
           let match = relativeHours.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
           let valueRange = Range(match.range(at: 1), in: message),
           let value = Int(message[valueRange]) {
            return calendar.date(byAdding: .hour, value: value, to: now)
        }

        if lowercased.contains("in an hour") {
            return calendar.date(byAdding: .hour, value: 1, to: now)
        }

        if let relativeMinutes = try? NSRegularExpression(pattern: "in\\s+(\\d+)\\s+(minute|minutes|min|mins)", options: .caseInsensitive),
           let match = relativeMinutes.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
           let valueRange = Range(match.range(at: 1), in: message),
           let value = Int(message[valueRange]) {
            return calendar.date(byAdding: .minute, value: value, to: now)
        }

        var baseDate = now
        var dateSet = false

        if let explicit = parseExplicitDate(from: lowercased, calendar: calendar, now: now) {
            baseDate = explicit
            dateSet = true
        }

        if lowercased.contains("tomorrow") {
            baseDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            dateSet = true
        } else if lowercased.contains("today") {
            baseDate = now
            dateSet = true
        } else if lowercased.contains("next week") {
            baseDate = calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
            dateSet = true
        }

        let dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for (index, dayName) in dayNames.enumerated() where lowercased.contains(dayName) {
            var components = DateComponents()
            components.weekday = index + 2
            if let nextDate = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) {
                baseDate = nextDate
                dateSet = true
                break
            }
        }

        var inferredTime = parseExplicitTime(from: message)
        if inferredTime == nil {
            if lowercased.contains("tonight") || lowercased.contains("this evening") {
                inferredTime = (19, 0)
            } else if lowercased.contains("afternoon") {
                inferredTime = (15, 0)
            } else if lowercased.contains("morning") {
                inferredTime = (9, 0)
            } else if lowercased.contains("evening") {
                inferredTime = (19, 0)
            }
        }

        if !dateSet && inferredTime == nil {
            return nil
        }

        let defaultStart = dataManager.appState.preferences.preferredStartTime
        let defaultComponents = calendar.dateComponents([.hour, .minute], from: defaultStart)
        let defaultHour = defaultComponents.hour ?? 9
        let defaultMinute = defaultComponents.minute ?? 0

        var resultDate = dateSet ? calendar.startOfDay(for: baseDate) : now

        if let inferredTime {
            resultDate = calendar.date(bySettingHour: inferredTime.hour, minute: inferredTime.minute, second: 0, of: resultDate) ?? resultDate
            if !dateSet && resultDate < now {
                resultDate = calendar.date(byAdding: .day, value: 1, to: resultDate) ?? resultDate
            }
        } else {
            resultDate = calendar.date(bySettingHour: defaultHour, minute: defaultMinute, second: 0, of: resultDate) ?? resultDate
        }

        return resultDate
    }

    private func parseExplicitDate(from message: String, calendar: Calendar, now: Date) -> Date? {
        let monthLookup: [String: Int] = [
            "january": 1, "jan": 1,
            "february": 2, "feb": 2,
            "march": 3, "mar": 3,
            "april": 4, "apr": 4,
            "may": 5,
            "june": 6, "jun": 6,
            "july": 7, "jul": 7,
            "august": 8, "aug": 8,
            "september": 9, "sep": 9, "sept": 9,
            "october": 10, "oct": 10,
            "november": 11, "nov": 11,
            "december": 12, "dec": 12
        ]

        if let monthMatch = try? NSRegularExpression(pattern: "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\s+(\\d{1,2})", options: .caseInsensitive),
           let match = monthMatch.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
           let monthRange = Range(match.range(at: 1), in: message),
           let dayRange = Range(match.range(at: 2), in: message),
           let month = monthLookup[String(message[monthRange]).lowercased()],
           let day = Int(message[dayRange]) {
            var components = calendar.dateComponents([.year], from: now)
            components.month = month
            components.day = day
            if let date = calendar.date(from: components) {
                if date < now {
                    components.year = (components.year ?? calendar.component(.year, from: now)) + 1
                    return calendar.date(from: components)
                }
                return date
            }
        }

        if let numericMatch = try? NSRegularExpression(pattern: "(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?", options: .caseInsensitive),
           let match = numericMatch.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
           let monthRange = Range(match.range(at: 1), in: message),
           let dayRange = Range(match.range(at: 2), in: message),
           let month = Int(message[monthRange]),
           let day = Int(message[dayRange]) {
            var components = calendar.dateComponents([.year], from: now)
            components.month = month
            components.day = day
            if match.range(at: 3).location != NSNotFound,
               let yearRange = Range(match.range(at: 3), in: message),
               let year = Int(message[yearRange]) {
                components.year = year < 100 ? (2000 + year) : year
            }
            if let date = calendar.date(from: components) {
                if date < now, match.range(at: 3).location == NSNotFound {
                    components.year = (components.year ?? calendar.component(.year, from: now)) + 1
                    return calendar.date(from: components)
                }
                return date
            }
        }

        return nil
    }

    private func parseExplicitTime(from message: String) -> (hour: Int, minute: Int)? {
        let timeRegex = try? NSRegularExpression(pattern: "(?:at|@)\\s*(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?", options: .caseInsensitive)
        guard let regex = timeRegex else { return nil }
        let range = NSRange(location: 0, length: message.count)
        guard let match = regex.firstMatch(in: message, options: [], range: range) else { return nil }

        guard let hourRange = Range(match.range(at: 1), in: message),
              let hour = Int(message[hourRange]) else { return nil }

        var minute = 0
        if match.range(at: 2).location != NSNotFound,
           let minuteRange = Range(match.range(at: 2), in: message),
           let parsedMinute = Int(message[minuteRange]) {
            minute = parsedMinute
        }

        var adjustedHour = hour
        if match.range(at: 3).location != NSNotFound,
           let ampmRange = Range(match.range(at: 3), in: message) {
            let indicator = String(message[ampmRange]).lowercased()
            if indicator == "pm" && hour != 12 {
                adjustedHour = hour + 12
            } else if indicator == "am" && hour == 12 {
                adjustedHour = 0
            }
        }

        return (adjustedHour, minute)
    }

    private func findNextAvailableTime(near proposedStart: Date, duration: TimeInterval) -> Date {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: proposedStart)

        let currentDay = calendar.startOfDay(for: dataManager.appState.currentDay.date)
        let relevantBlocks: [TimeBlock]
        if calendar.isDate(targetDay, inSameDayAs: currentDay) {
            relevantBlocks = dataManager.appState.currentDay.blocks
        } else if let historicalDay = dataManager.appState.historicalDays.first(where: { calendar.isDate($0.date, inSameDayAs: targetDay) }) {
            relevantBlocks = historicalDay.blocks
        } else {
            relevantBlocks = []
        }

        let sortedBlocks = relevantBlocks.sorted { $0.startTime < $1.startTime }
        var candidate = proposedStart

        for block in sortedBlocks {
            if block.endTime <= candidate {
                continue
            }

            let candidateEnd = candidate.addingTimeInterval(duration)
            if candidateEnd <= block.startTime {
                break
            }

            candidate = max(block.endTime, candidate)
        }

        return candidate
    }
    
    // MARK: - Smart Relationship Detection
    
    private func findRelatedGoal(for eventTitle: String) -> Goal? {
        let lowercaseTitle = eventTitle.lowercased()
        
        return dataManager.appState.goals.first { goal in
            let goalWords = goal.title.lowercased().split(separator: " ")
            let titleWords = lowercaseTitle.split(separator: " ")
            
            // Check for word overlap
            let overlap = Set(goalWords).intersection(Set(titleWords))
            return overlap.count >= 1 && goal.isActive
        }
    }
    
    private func findRelatedPillar(for eventTitle: String) -> Pillar? {
        let lowercaseTitle = eventTitle.lowercased()
        
        return dataManager.appState.pillars.first { pillar in
            let pillarWords = pillar.name.lowercased().split(separator: " ")
            let titleWords = lowercaseTitle.split(separator: " ")
            
            // Check for word overlap or category match
            let overlap = Set(pillarWords).intersection(Set(titleWords))
            if overlap.count >= 1 { return true }
            
            // Check for category matches
            if lowercaseTitle.contains("work") && pillar.name.lowercased().contains("work") { return true }
            if lowercaseTitle.contains("exercise") && pillar.name.lowercased().contains("exercise") { return true }
            if lowercaseTitle.contains("meeting") && pillar.name.lowercased().contains("meeting") { return true }
            
            return false
        }
    }
    
    private func suggestRelatedActivities(for timeBlock: TimeBlock, confidence: Double) {
        // If confidence is high, suggest creating a chain around this event
        if confidence >= 0.8 {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds delay
                await MainActor.run {
                    showEphemeralInsight("💡 Want to create a chain around '\(timeBlock.title)'?")
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StagedSuggestionView: View {
    let suggestion: Suggestion
    let onAccept: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(suggestion.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text("\(suggestion.duration.minutes) min")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                    
                    Text(suggestion.energy.rawValue)
                        .font(.caption2)
                    
                    Text(suggestion.emoji)
                        .font(.caption2)
                }
            }
            
            Spacer()
            
            // Confidence indicator
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)
            
            // Actions
            HStack(spacing: 8) {
                Button("No") {
                    onReject()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Yes") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.blue.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
        )
    }
    
    private var confidenceColor: Color {
        switch suggestion.confidence {
        case 0.8...: return .green
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }
}

struct MessageHistoryView: View {
    let messages: [AIMessage]
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .navigationTitle("Conversation History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct MessageBubble: View {
    let message: AIMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.isUser ? .blue.opacity(0.2) : .gray.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                
                Text(message.timestamp.timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// MARK: - Supporting Data Models

struct AIMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}
