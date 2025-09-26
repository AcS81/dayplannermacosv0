import SwiftUI
import Foundation

struct MindChatBar: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var patternEngine: PatternLearningEngine
    @StateObject private var speechService = SpeechService()
    @FocusState private var isFocused: Bool

    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var statusLine: String?
    @State private var appliedMessages: [String] = []
    @State private var clarification: String?
    @State private var errorMessage: String?
    @State private var showingInsights = false
    @State private var isVoiceEnabled = false

    private let helperPrompts = [
        "Create a goal to publish the launch post",
        "Pin the research node for Focus Goal",
        "Add quiet hours to my deep work pillar"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Voice transcription display
            if !speechService.transcribedText.isEmpty {
                HStack {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("Voice: \(speechService.transcribedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use") {
                        inputText = speechService.transcribedText
                        speechService.transcribedText = ""
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.purple)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 8) {
                Image(systemName: clarification == nil ? "brain.head.profile" : "questionmark.bubble")
                    .font(.title3)
                    .foregroundStyle(clarification == nil ? .purple : .orange)
                Text(clarification == nil ? "Mind chat" : "Mind chat needs detail")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if isSending {
                    ProgressView().controlSize(.small)
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

            if let status = statusLine, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appliedMessages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appliedMessages, id: \.self) { message in
                        Text("• \(message)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }

            if let clarification {
                Text("Clarify for me: \(clarification)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            // Pattern Insights Display
            if !patternEngine.actionableInsights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Text("Pattern Insights")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                        Spacer()
                        Button(showingInsights ? "Hide" : "Show") {
                            showingInsights.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.purple)
                    }
                    
                    if showingInsights {
                        ForEach(patternEngine.actionableInsights.prefix(3)) { insight in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: insightIcon(for: insight.actionType))
                                    .font(.caption2)
                                    .foregroundStyle(insightColor(for: insight.actionType))
                                    .frame(width: 12)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(insight.title)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    
                                    Text(insight.suggestedAction)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                Text("\(Int(insight.confidence * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(insightBackgroundColor(for: insight.actionType), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                TextField("Directly shape goals or pillars…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending || !aiService.isConnected)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                
                // Voice button
                Button(action: toggleVoiceInput) {
                    Image(systemName: speechService.isListening ? "mic.fill" : "mic")
                        .font(.headline)
                        .foregroundStyle(speechService.isListening ? .red : .purple)
                        .padding(10)
                        .background(speechService.isListening ? Color.red.opacity(0.1) : Color.purple.opacity(0.1), in: Circle())
                }
                .disabled(isSending || speechService.authorizationStatus == .denied)
                .help(speechService.authorizationStatus == .denied ? "Microphone permission denied" : "Voice input")
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(isSending ? Color.gray : (aiService.isConnected ? Color.purple : Color.red), in: Circle())
                }
                .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !aiService.isConnected)
            }

            HStack(spacing: 10) {
                ForEach(helperPrompts.prefix(2), id: \.self) { prompt in
                    MindChatChip(title: prompt) {
                        inputText = prompt
                        isFocused = true
                    }
                }
                if let clarification {
                    MindChatChip(title: "Answer question") {
                        inputText = clarification
                        self.clarification = nil
                        isFocused = true
                    }
                } else if let suggestion = helperPrompts.last {
                    MindChatChip(title: suggestion) {
                        inputText = suggestion
                        isFocused = true
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        let message = trimmed
        inputText = ""
        errorMessage = nil
        statusLine = nil
        isSending = true

        Task {
            let response: MindCommandResponse?
            do {
                let context = await MainActor.run { dataManager.makeMindEditorContext() }
                response = try await aiService.processMindCommands(message: message, context: context, patternInsights: patternEngine.actionableInsights)
            } catch {
                response = fallbackResponse(for: message)
                if response == nil {
                    await MainActor.run {
                        errorMessage = nil
                        appliedMessages.removeAll()
                        clarification = nil
                        statusLine = friendlyOfflineMessage(for: error)
                        isSending = false
                    }
                    return
                }
            }

            if let response {
                let outcome = dataManager.applyMindCommands(response.commands)
                await MainActor.run {
                    statusLine = response.summary.isEmpty ? nil : response.summary
                    appliedMessages = outcome.appliedMessages
                    clarification = outcome.clarification
                    if outcome.hasChanges {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            appliedMessages.removeAll()
                        }
                    }
                    if clarification != nil {
                        isFocused = true
                    }
                }
            }

            await MainActor.run {
                if statusLine == nil && appliedMessages.isEmpty && clarification == nil {
                    statusLine = "No changes applied"
                }
                isSending = false
            }
        }
    }

    private func fallbackResponse(for message: String) -> MindCommandResponse? {
        if let goalAdjustment = offlineGoalAdjustment(for: message) {
            return goalAdjustment
        }
        if let offlineAdjustment = offlinePillarAdjustment(for: message) {
            return offlineAdjustment
        }
        if let creation = offlineCreation(for: message) {
            return creation
        }
        let clarification = clarificationPrompt(for: message)
        return MindCommandResponse(summary: "Need clarification", commands: [.clarification(clarification)])
    }

    private func extractTitle(from message: String, keyword: String) -> String? {
        let lower = message.lowercased()
        guard let range = lower.range(of: keyword) else { return nil }
        let remainder = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? nil : remainder.capitalizedFirst
    }

    private func friendlyOfflineMessage(for error: Error) -> String {
        if let aiError = error as? AIError, aiError == .timeout {
            return "Mind engine timed out — request not applied."
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Mind engine offline — reconnect and try again."
        }
        return "Mind engine unavailable — try again soon."
    }

    private func offlineCreation(for message: String) -> MindCommandResponse? {
        let lowered = message.lowercased()
        if lowered.contains("goal") || lowered.contains("finish") || lowered.contains("complete") {
            // Extract goal title more intelligently
            var title = "New Goal"
            var description = ""
            
            // Try to extract a meaningful title
            if let goalTitle = extractTitle(from: message, keyword: "goal") {
                title = goalTitle
            } else if let finishTitle = extractTitle(from: message, keyword: "finish") {
                title = "Finish \(finishTitle)"
            } else if let completeTitle = extractTitle(from: message, keyword: "complete") {
                title = "Complete \(completeTitle)"
            } else {
                // Try to extract the main subject
                let words = message.components(separatedBy: .whitespacesAndNewlines)
                if let appIndex = words.firstIndex(where: { $0.lowercased() == "app" }) {
                    let beforeApp = words[..<appIndex].joined(separator: " ")
                    if !beforeApp.isEmpty {
                        title = "Finish \(beforeApp) app"
                    }
                }
            }
            
            // Extract deadline information
            if lowered.contains("october") {
                description = "Target completion: October"
            } else if lowered.contains("by") {
                if let byRange = lowered.range(of: "by") {
                    let afterBy = String(lowered[byRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !afterBy.isEmpty {
                        description = "Target completion: \(afterBy.capitalizedFirst)"
                    }
                }
            }
            
            let payload = MindCommandCreateGoal(
                title: title,
                description: description.isEmpty ? nil : description,
                emoji: "🎯",
                importance: 4, // High importance for completion goals
                nodes: [],
                relatedPillarIds: [],
                relatedPillarNames: []
            )
            return MindCommandResponse(summary: "Created goal: \(title)", commands: [.createGoal(payload)])
        }
        if lowered.contains("pillar") {
            let name = extractTitle(from: message, keyword: "pillar") ?? "New Pillar"
            let baseDescription = extractContent(after: "pillar", in: message, terminators: [" with", " including", " values", " habits", " constraints", "."])
            let values = parseList(after: ["values", "principles"], in: message)
            let habits = parseList(after: ["habits"], in: message)
            let constraints = parseList(after: ["constraints"], in: message)
            let quietRanges = parseQuietHours(from: message)
            let payload = MindCommandCreatePillar(
                name: name,
                description: baseDescription,
                emoji: nil,
                frequency: nil,
                wisdom: nil,
                values: values,
                habits: habits,
                constraints: constraints,
                quietHours: quietRanges
            )
            return MindCommandResponse(summary: "Captured new pillar \(name)", commands: [.createPillar(payload)])
        }
        return nil
    }

    private func offlineGoalAdjustment(for message: String) -> MindCommandResponse? {
        guard let goal = findGoalMatch(in: message) else { return nil }

        let newTitle = extractRenameTarget(in: message, goal: goal)
        let newDescription = extractDescriptionUpdate(in: message)
        let newFocus = extractFocusUpdate(in: message)
        let newImportance = parseImportanceLevel(from: message)
        let nodes = parseGoalNodes(from: message)

        var commands: [MindCommand] = []
        var summaryParts: [String] = []

        if newTitle != nil || newDescription != nil || newImportance != nil || newFocus != nil {
            let payload = MindCommandUpdateGoal(
                reference: MindCommandGoalReference(id: goal.id, title: goal.title),
                title: newTitle,
                description: newDescription,
                emoji: nil,
                importance: newImportance,
                focus: newFocus
            )
            commands.append(.updateGoal(payload))
            summaryParts.append("Updated \(goal.title)")
        }

        if !nodes.isEmpty {
            for node in nodes {
                let payload = MindCommandAddNode(
                    reference: MindCommandGoalReference(id: goal.id, title: goal.title),
                    node: node,
                    linkToTitle: nil,
                    linkLabel: nil
                )
                commands.append(.addNode(payload))
            }
            summaryParts.append("Added \(nodes.count) node\(nodes.count == 1 ? "" : "s")")
        }

        guard !commands.isEmpty else { return nil }
        let summary = summaryParts.joined(separator: " • ")
        return MindCommandResponse(
            summary: summary.isEmpty ? "Applied quick changes" : summary,
            commands: commands
        )
    }

    private func offlinePillarAdjustment(for message: String) -> MindCommandResponse? {
        guard let pillar = findPillarMatch(in: message) else { return nil }
        let values = parseList(after: ["add value", "add values", "reinforce"], in: message)
        let habits = parseList(after: ["add habit", "add habits", "track"], in: message)
        let constraints = parseList(after: ["add constraint", "add constraints", "avoid"], in: message)
        let quietHours = parseQuietHours(from: message)
        let trimmedDescription = extractContent(after: "update description", in: message, terminators: [" for", " on", "."])
        let trimmedWisdom = extractContent(after: "principle", in: message, terminators: [" for", " on", "."])

        guard !values.isEmpty || !habits.isEmpty || !constraints.isEmpty || !quietHours.isEmpty || trimmedDescription != nil || trimmedWisdom != nil else {
            return nil
        }

        let payload = MindCommandUpdatePillar(
            reference: MindCommandPillarReference(id: pillar.id, name: pillar.name),
            description: trimmedDescription,
            emoji: nil,
            frequency: nil,
            wisdom: trimmedWisdom,
            values: values,
            habits: habits,
            constraints: constraints,
            quietHours: quietHours
        )

        var summaryChunks: [String] = []
        if !values.isEmpty { summaryChunks.append("values") }
        if !habits.isEmpty { summaryChunks.append("habits") }
        if !constraints.isEmpty { summaryChunks.append("constraints") }
        if !quietHours.isEmpty { summaryChunks.append("quiet hours") }
        if trimmedDescription != nil { summaryChunks.append("description") }
        if trimmedWisdom != nil { summaryChunks.append("wisdom") }
        let summary = "Adjusted \(pillar.name): \(summaryChunks.joined(separator: ", "))"

        return MindCommandResponse(summary: summary, commands: [.updatePillar(payload)])
    }

    private func findPillarMatch(in message: String) -> Pillar? {
        let lowered = message.lowercased()
        return dataManager.appState.pillars
            .sorted { $0.name.count > $1.name.count }
            .first { lowered.contains($0.name.lowercased()) }
    }

    private func findGoalMatch(in message: String) -> Goal? {
        let lowered = message.lowercased()
        return dataManager.appState.goals
            .sorted { $0.title.count > $1.title.count }
            .first { lowered.contains($0.title.lowercased()) }
    }

    private func parseList(after triggers: [String], in message: String) -> [String] {
        for trigger in triggers {
            if let segment = extractContent(after: trigger, in: message, terminators: [" to ", " for ", " on ", ".", " and quiet", " quiet"]) {
                return splitList(from: segment)
            }
        }
        return []
    }

    private func extractContent(after trigger: String, in message: String, terminators: [String]) -> String? {
        let lower = message.lowercased()
        guard let triggerRange = lower.range(of: trigger) else { return nil }
        let startIndex = triggerRange.upperBound
        let remainder = message[startIndex...]
        let lowerRemainder = lower[startIndex...]
        var endIndex = remainder.endIndex
        for terminator in terminators {
            if let range = lowerRemainder.range(of: terminator) {
                endIndex = range.lowerBound
                break
            }
        }
        let segment = remainder[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return segment.isEmpty ? nil : segment
    }

    private func splitList(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        let replaced = text.replacingOccurrences(of: " and ", with: ",")
        let chunks = replaced.components(separatedBy: separators)
        return chunks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func parseQuietHours(from message: String) -> [MindQuietHourDescriptor] {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*[-–]\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(location: 0, length: message.utf16.count)
        let matches = regex.matches(in: message, options: [], range: range)
        var descriptors: [MindQuietHourDescriptor] = []
        for match in matches {
            guard let startHourRange = Range(match.range(at: 1), in: message) else { continue }
            let startHour = Int(message[startHourRange]) ?? 0
            let startMinuteRange = match.range(at: 2)
            let startMinute: Int
            if startMinuteRange.location != NSNotFound, let minuteRange = Range(startMinuteRange, in: message) {
                startMinute = Int(message[minuteRange]) ?? 0
            } else {
                startMinute = 0
            }
            let startMeridiem: String?
            if match.range(at: 3).location != NSNotFound, let meridiemRange = Range(match.range(at: 3), in: message) {
                startMeridiem = String(message[meridiemRange])
            } else {
                startMeridiem = nil
            }

            guard let endHourRange = Range(match.range(at: 4), in: message) else { continue }
            let endHour = Int(message[endHourRange]) ?? 0
            let endMinuteRange = match.range(at: 5)
            let endMinute: Int
            if endMinuteRange.location != NSNotFound, let minuteRange = Range(endMinuteRange, in: message) {
                endMinute = Int(message[minuteRange]) ?? 0
            } else {
                endMinute = 0
            }
            let endMeridiem: String?
            if match.range(at: 6).location != NSNotFound, let meridiemRange = Range(match.range(at: 6), in: message) {
                endMeridiem = String(message[meridiemRange])
            } else {
                endMeridiem = nil
            }

            let startString = formatTime(hour: startHour, minute: startMinute, meridiem: startMeridiem)
            let endString = formatTime(hour: endHour, minute: endMinute, meridiem: endMeridiem)
            descriptors.append(MindQuietHourDescriptor(start: startString, end: endString))
        }
        return descriptors
    }

    private func formatTime(hour: Int, minute: Int, meridiem: String?) -> String {
        var adjustedHour = max(0, min(23, hour % 24))
        let clampedMinute = max(0, min(59, minute))
        if let meridiem {
            let lower = meridiem.lowercased()
            if lower.hasPrefix("p") {
                if adjustedHour < 12 { adjustedHour += 12 }
            } else if lower.hasPrefix("a") {
                if adjustedHour == 12 { adjustedHour = 0 }
            }
        }
        return String(format: "%02d:%02d", adjustedHour, clampedMinute)
    }

    private func extractRenameTarget(in message: String, goal: Goal) -> String? {
        let lower = message.lowercased()
        if lower.contains("rename") || lower.contains("retitle") || lower.contains("call it") {
            let direct = extractContent(after: "rename \(goal.title.lowercased()) to", in: message, terminators: [".", ",", " and", " with"])
            if let direct, !direct.isEmpty { return direct.capitalizedFirst }
            if let generic = extractContent(after: "rename to", in: message, terminators: [".", ",", " and"]) ??
                extractContent(after: "call it", in: message, terminators: [".", ",", " and"]) {
                return generic.capitalizedFirst
            }
        }
        return nil
    }

    private func extractDescriptionUpdate(in message: String) -> String? {
        if let explicit = extractContent(after: "description to", in: message, terminators: [".", ","]) ??
            extractContent(after: "describe it as", in: message, terminators: [".", ","]) ??
            extractContent(after: "set description", in: message, terminators: [".", ","]) {
            return explicit
        }
        return nil
    }

    private func extractFocusUpdate(in message: String) -> String? {
        if let focus = extractContent(after: "focus on", in: message, terminators: [".", ","]) ??
            extractContent(after: "make focus", in: message, terminators: [".", ","]) ??
            extractContent(after: "active focus", in: message, terminators: [".", ","]) {
            return focus
        }
        return nil
    }

    private func parseImportanceLevel(from message: String) -> Int? {
        let lower = message.lowercased()
        if lower.contains("critical") || lower.contains("urgent") { return 5 }
        if lower.contains("high priority") || lower.contains("top priority") { return 4 }
        if lower.contains("low priority") { return 2 }
        if lower.contains("deprioritize") { return 1 }
        let digits = [5, 4, 3, 2, 1]
        for digit in digits {
            if lower.contains("priority \(digit)") || lower.contains("importance \(digit)") {
                return digit
            }
        }
        if lower.contains("medium priority") { return 3 }
        return nil
    }

    private func parseGoalNodes(from message: String) -> [MindCommandNode] {
        var results: [MindCommandNode] = []
        let subgoals = parseList(after: ["add subgoal", "add sub-goal", "subgoal"], in: message)
        results.append(contentsOf: subgoals.map { MindCommandNode(type: .subgoal, title: $0, detail: nil, pinned: false, weight: nil) })

        let tasks = parseList(after: ["add task", "add tasks", "task"], in: message)
        results.append(contentsOf: tasks.map { MindCommandNode(type: .task, title: $0, detail: nil, pinned: false, weight: nil) })

        let notes = parseList(after: ["add note", "note"], in: message)
        results.append(contentsOf: notes.map { MindCommandNode(type: .note, title: $0, detail: nil, pinned: false, weight: nil) })

        let resources = parseList(after: ["add resource", "resource"], in: message)
        results.append(contentsOf: resources.map { MindCommandNode(type: .resource, title: $0, detail: nil, pinned: false, weight: nil) })

        let metrics = parseList(after: ["add metric", "metric"], in: message)
        results.append(contentsOf: metrics.map { MindCommandNode(type: .metric, title: $0, detail: nil, pinned: false, weight: nil) })

        return results
    }

    private func clarificationPrompt(for message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("pillar") {
            return "Which pillar should I adjust, and what should change?"
        }
        if lower.contains("goal") {
            return "Which goal should I update, and how?"
        }
        return "Could you specify the goal or pillar you want me to adjust?"
    }
}

private struct MindChatChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

// MARK: - Pattern Insights Helpers

extension MindChatBar {
    private func insightIcon(for actionType: InsightActionType) -> String {
        switch actionType {
        case .createBlock: return "plus.circle"
        case .modifySchedule: return "calendar"
        case .createChain: return "link"
        case .updateGoal: return "target"
        case .createPillar: return "pillar"
        case .adjustEnergy: return "bolt"
        case .optimizeTiming: return "clock"
        }
    }
    
    private func insightColor(for actionType: InsightActionType) -> Color {
        switch actionType {
        case .createBlock: return .blue
        case .modifySchedule: return .green
        case .createChain: return .purple
        case .updateGoal: return .orange
        case .createPillar: return .pink
        case .adjustEnergy: return .yellow
        case .optimizeTiming: return .cyan
        }
    }
    
    private func insightBackgroundColor(for actionType: InsightActionType) -> Color {
        switch actionType {
        case .createBlock: return Color.blue.opacity(0.1)
        case .modifySchedule: return Color.green.opacity(0.1)
        case .createChain: return Color.purple.opacity(0.1)
        case .updateGoal: return Color.orange.opacity(0.1)
        case .createPillar: return Color.pink.opacity(0.1)
        case .adjustEnergy: return Color.yellow.opacity(0.1)
        case .optimizeTiming: return Color.cyan.opacity(0.1)
        }
    }
    
    private func toggleVoiceInput() {
        if speechService.isListening {
            Task {
                await speechService.stopListening()
            }
        } else {
            Task {
                do {
                    try await speechService.startListening()
                } catch {
                    await MainActor.run {
                        errorMessage = "Voice input error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
