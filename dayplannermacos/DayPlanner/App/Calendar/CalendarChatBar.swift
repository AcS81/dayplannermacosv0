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
    @State private var lastAIResponse: String?
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
            
            if let response = lastAIResponse {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text(response)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Button("×", action: { lastAIResponse = nil })
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
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
        lastAIResponse = nil // Clear previous response
        Task {
            let context = dataManager.createEnhancedContext(date: dataManager.appState.currentDay.date)
            do {
                let response = try await aiService.processMessage(message, context: context)
                await MainActor.run {
                    // Show the AI response to the user
                    if !response.text.isEmpty {
                        lastAIResponse = response.text
                        print("🤖 AI Response: \(response.text)")
                        
                        // Auto-schedule confident event creations
                        if let _ = response.actionType, 
                           let createdItems = response.createdItems,
                           response.confidence > 0.8 {
                            
                            for item in createdItems {
                                switch item.type {
                                case .event:
                                    if let suggestion = item.data as? Suggestion {
                                        dataManager.applySuggestion(suggestion)
                                        print("✅ Auto-scheduled confident event: \(suggestion.title)")
                                    }
                                case .goal, .pillar, .chain:
                                    // These are handled by the mind editor
                                    break
                                }
                            }
                        }
                        
                        // If there are suggestions, they'll be automatically processed by the suggestion system
                        if !response.suggestions.isEmpty {
                            print("📝 Generated \(response.suggestions.count) suggestions")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ Chat error: \(error.localizedDescription)")
                    // Show user feedback for connection issues
                    if let aiError = error as? AIError, aiError == .notConnected {
                        lastErrorMessage = "AI service is not connected. Please check your API configuration in Settings."
                        showConnectionAlert = true
                        print("⚠️ AI service not connected. Check your API configuration in Settings.")
                    } else {
                        lastErrorMessage = "Failed to process request: \(error.localizedDescription)"
                        showConnectionAlert = true
                    }
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
