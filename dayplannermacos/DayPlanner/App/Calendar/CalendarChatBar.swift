import SwiftUI

struct CalendarChatBar: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @State private var inputText: String = ""
    @State private var activeBlock: TimeBlock?
    @State private var isSending = false
    @State private var editingBlock: TimeBlock?
    @State private var undoCandidate: Record?
    @State private var showConnectionAlert = false
    @State private var lastErrorMessage: String?
    @State private var lastAssistantStatus: String?
    @FocusState private var isFocused: Bool
    
    private var currentPrompt: String {
        if let block = activeBlock {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeString = formatter.string(from: block.startTime)
            return "How did \(block.title) at \(timeString) go?"
        }
        return "What should I plan next?"
    }
    
    private var isConfirming: Bool {
        activeBlock != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { // Increased from 10 to 14
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isConfirming ? "questionmark.circle" : "sparkles")
                    .font(.title3)
                    .foregroundStyle(isConfirming ? .blue : .purple)
                Text(currentPrompt)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else if !aiService.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text("AI Offline")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let status = lastAssistantStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let record = undoCandidate {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Recorded \(record.title). Undo?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Undo", action: undoLastConfirmation)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
            }
            
            if let block = activeBlock {
                HStack(spacing: 8) {
                    ChatActionButton(title: "Confirm", systemImage: "checkmark.circle.fill", tint: .green) {
                        confirm(block: block, notes: inputText)
                    }
                    ChatActionButton(title: "Edit & Confirm", systemImage: "pencil.circle", tint: .blue) {
                        editingBlock = block
                    }
                    ChatActionButton(title: "Re-queue", systemImage: "arrow.uturn.left.circle", tint: .orange) {
                        requeue(block: block, notes: inputText)
                    }
                }
            }
            
            HStack(spacing: 12) {
                TextField("Type a quick reply…", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending || !aiService.isConnected)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit(handleSend)
                
                Button(action: handleSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(isSending ? Color.gray : (aiService.isConnected ? Color.blue : Color.red), in: Circle())
                }
                .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !aiService.isConnected)
            }
            
            HStack(spacing: 10) {
                ChatChip(title: "Tell me what you did") {
                    handleTellMeChip()
                }
                ChatChip(title: "Ask me to book") {
                    handleAskMeChip()
                }
            }
        }
        .padding(.horizontal, 20) // Increased from 18 to 20
        .padding(.vertical, 16) // Increased from 14 to 16
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .onAppear(perform: refreshPrompt)
        .onChange(of: dataManager.appState.currentDay.blocks) { _, _ in
            refreshPrompt()
        }
        .alert("AI Service Not Connected", isPresented: $showConnectionAlert) {
            Button("Test Connection") {
                Task {
                    await aiService.checkConnection()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(lastErrorMessage ?? "Please check your API configuration in Settings.")
        }
        .sheet(item: $editingBlock) { block in
            NoFlashEventDetailsSheet(
                block: block,
                allBlocks: dataManager.appState.currentDay.blocks,
                onSave: { updatedBlock in
                    dataManager.updateTimeBlock(updatedBlock)
                    dataManager.confirmBlock(updatedBlock.id, notes: updatedBlock.notes)
                    editingBlock = nil
                    refreshPrompt()
                },
                onDelete: {
                    dataManager.removeTimeBlock(block.id)
                    editingBlock = nil
                    refreshPrompt()
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    private func refreshPrompt() {
        dataManager.refreshPastBlocks()
        activeBlock = dataManager.nextUnconfirmedBlock()
        if activeBlock == nil {
            isFocused = false
        }
    }
    
    private func handleSend() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        if let block = activeBlock {
            handleConfirmationReply(trimmed, for: block)
        } else {
            sendPlanningMessage(trimmed)
        }
        inputText = ""
    }
    
    private func handleConfirmationReply(_ message: String, for block: TimeBlock) {
        let lowered = message.lowercased()
        if lowered.contains("requeue") || lowered.contains("later") || lowered.contains("tomorrow") || lowered.contains("reschedule") || lowered.contains("no") {
            requeue(block: block, notes: message)
        } else {
            confirm(block: block, notes: message)
        }
    }
    
    private func confirm(block: TimeBlock, notes: String?) {
        dataManager.confirmBlock(block.id, notes: notes)
        undoCandidate = dataManager.appState.records.last
        refreshPrompt()
    }
    
    private func requeue(block: TimeBlock, notes: String?) {
        dataManager.requeueBlock(block.id, notes: notes)
        refreshPrompt()
    }
    
    private func sendPlanningMessage(_ message: String) {
        isSending = true
        lastAssistantStatus = nil
        Task {
            let context = dataManager.createEnhancedContext(date: dataManager.appState.currentDay.date)
            do {
                let response = try await aiService.processMessage(message, context: context)
                await MainActor.run {
                    lastErrorMessage = nil
                    handleAIResponse(response, originalMessage: message)
                }
            } catch {
                await MainActor.run {
                    print("❌ Chat error: \(error.localizedDescription)")
                    if let aiError = error as? AIError, aiError == .notConnected {
                        lastErrorMessage = "AI service is not connected. Please check your API configuration in Settings."
                        showConnectionAlert = true
                        print("⚠️ AI service not connected. Check your API configuration in Settings.")
                    } else {
                        lastErrorMessage = "Failed to process request: \(error.localizedDescription)"
                        showConnectionAlert = true
                    }
                    lastAssistantStatus = "Couldn't process that right now."
                }
            }
            await MainActor.run {
                isSending = false
                refreshPrompt()
            }
        }
    }
    
    private func handleTellMeChip() {
        if let block = activeBlock {
            inputText = "I spent that time on \(block.title.lowercased())."
            isFocused = true
        } else {
            inputText = "I just wrapped something up."
            isFocused = true
        }
    }
    
    private func handleAskMeChip() {
        if isConfirming {
            if let block = activeBlock {
                requeue(block: block, notes: "Please reschedule this.")
            }
        } else {
            inputText = "Can you book the next thing for me?"
            isFocused = true
        }
    }
    
    private func undoLastConfirmation() {
        guard let record = undoCandidate else { return }
        dataManager.undoRecord(record.id)
        undoCandidate = nil
        refreshPrompt()
    }

    @MainActor
    private func handleAIResponse(_ response: AIResponse, originalMessage: String) {
        var statusText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let actionType = response.actionType {
            switch actionType {
            case .createEvent:
                if let message = handleEventCreation(response) {
                    statusText = message
                }
            case .createGoal, .createPillar, .createChain:
                if statusText.isEmpty {
                    statusText = "Captured your request."
                }
                dataManager.requestMicroUpdate(.pinChange)
            case .suggestActivities:
                if statusText.isEmpty {
                    statusText = "Sharing fresh ideas."
                }
                dataManager.requestMicroUpdate(.feedback)
            case .generalChat:
                break
            }
        }

        if statusText.isEmpty {
            statusText = "Noted."
        }

        lastAssistantStatus = statusText
    }

    @MainActor
    private func handleEventCreation(_ response: AIResponse) -> String? {
        guard var suggestion = response.suggestions.first else {
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        if suggestion.relatedGoalId == nil, let goal = findRelatedGoal(for: suggestion.title) {
            suggestion.relatedGoalId = goal.id
            suggestion.relatedGoalTitle = goal.title
        }
        if suggestion.relatedPillarId == nil, let pillar = findRelatedPillar(for: suggestion.title) {
            suggestion.relatedPillarId = pillar.id
            suggestion.relatedPillarTitle = pillar.name
        }

        suggestion.suggestedTime = resolveSuggestedStartTime(for: suggestion)
        dataManager.applySuggestion(suggestion)

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let datePart = describeDate(suggestion.suggestedTime)
        let timePart = timeFormatter.string(from: suggestion.suggestedTime)
        let schedulingLine = "Scheduled \(suggestion.title) for \(datePart) at \(timePart)."

        let trimmedResponse = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedResponse.isEmpty {
            return schedulingLine
        }
        return "\(trimmedResponse)\n\(schedulingLine)"
    }

    private func resolveSuggestedStartTime(for suggestion: Suggestion) -> Date {
        let now = Date()
        let anchor = suggestion.suggestedTime > now ? suggestion.suggestedTime : now.addingTimeInterval(300)
        return findNextAvailableTime(after: anchor)
    }

    private func findNextAvailableTime(after startTime: Date) -> Date {
        let calendar = Calendar.current
        let currentDay = dataManager.appState.currentDay.date
        guard calendar.isDate(startTime, inSameDayAs: currentDay) else {
            return startTime
        }

        let sortedBlocks = dataManager.appState.currentDay.blocks.sorted { $0.startTime < $1.startTime }
        var searchTime = startTime
        let minimumDuration: TimeInterval = 30 * 60

        for block in sortedBlocks {
            if searchTime.addingTimeInterval(minimumDuration) <= block.startTime {
                return searchTime
            }

            if block.endTime > searchTime {
                searchTime = block.endTime
            }
        }

        return searchTime
    }

    private func describeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        }
        if calendar.isDateInTomorrow(date) {
            return "tomorrow"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func findRelatedGoal(for eventTitle: String) -> Goal? {
        let lowercaseTitle = eventTitle.lowercased()
        return dataManager.appState.goals.first { goal in
            let goalWords = goal.title.lowercased().split(separator: " ")
            let titleWords = lowercaseTitle.split(separator: " ")
            return Set(goalWords).intersection(Set(titleWords)).count >= 1 && goal.isActive
        }
    }

    private func findRelatedPillar(for eventTitle: String) -> Pillar? {
        let lowercaseTitle = eventTitle.lowercased()
        return dataManager.appState.pillars.first { pillar in
            let pillarWords = pillar.name.lowercased().split(separator: " ")
            let titleWords = lowercaseTitle.split(separator: " ")
            return Set(pillarWords).intersection(Set(titleWords)).count >= 1
        }
    }
}

private struct ChatChip: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ChatActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }
}
