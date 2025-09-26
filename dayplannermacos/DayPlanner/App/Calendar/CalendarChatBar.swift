import SwiftUI
import Foundation

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
                                        let adjusted = adjustedSuggestion(suggestion, for: message)
                                        dataManager.applySuggestion(adjusted)
                                        print("✅ Auto-scheduled confident event: \(adjusted.title) at \(adjusted.suggestedTime.timeString)")
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

    // MARK: - Scheduling Helpers

    private func adjustedSuggestion(_ suggestion: Suggestion, for message: String) -> Suggestion {
        var updated = suggestion
        let extractedTime = extractDateFromMessage(message)

        let proposedStart: Date
        if let extractedTime {
            let difference = abs(extractedTime.timeIntervalSince(suggestion.suggestedTime))
            proposedStart = difference > 60 ? extractedTime : suggestion.suggestedTime
        } else {
            proposedStart = suggestion.suggestedTime
        }

        if updated.rawSuggestedTime == nil {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            updated.rawSuggestedTime = formatter.string(from: suggestion.suggestedTime)
        }

        let scheduledStart = findNextAvailableTime(near: proposedStart, duration: suggestion.duration)
        updated.suggestedTime = scheduledStart
        return updated
    }

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
