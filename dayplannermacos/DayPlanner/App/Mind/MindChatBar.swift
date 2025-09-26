import SwiftUI
import Foundation

struct MindChatBar: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @FocusState private var isFocused: Bool

    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var statusLine: String?
    @State private var appliedMessages: [String] = []
    @State private var clarification: String?
    @State private var errorMessage: String?

    private let helperPrompts = [
        "Create a goal to publish the launch post",
        "Pin the research node for Focus Goal",
        "Add quiet hours to my deep work pillar"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            HStack(spacing: 12) {
                TextField("Directly shape goals or pillars…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(isSending ? Color.gray : Color.purple, in: Circle())
                }
                .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                response = try await aiService.processMindCommands(message: message, context: context)
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
        if let offlineAdjustment = offlinePillarAdjustment(for: message) {
            return offlineAdjustment
        }
        if let creation = offlineCreation(for: message) {
            return creation
        }
        return nil
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
        if lowered.contains("goal") {
            let title = extractTitle(from: message, keyword: "goal") ?? "New Goal"
            let payload = MindCommandCreateGoal(
                title: title,
                description: nil,
                emoji: nil,
                importance: nil,
                nodes: [],
                relatedPillarIds: [],
                relatedPillarNames: []
            )
            return MindCommandResponse(summary: "Captured new goal \(title)", commands: [.createGoal(payload)])
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
