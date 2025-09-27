import SwiftUI

struct GhostOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selectedDate: Date
    let dayStartHour: Int
    let minuteHeight: CGFloat
    let suggestions: [Suggestion]
    @Binding var selectedGhosts: Set<UUID>
    let onToggle: (Suggestion) -> Void
    let onDismiss: (Suggestion) -> Void
    
    var body: some View {
        ForEach(suggestions) { suggestion in
            GhostEventCard(
                suggestion: suggestion,
                selectedDate: selectedDate,
                dayStartHour: dayStartHour,
                minuteHeight: minuteHeight,
                isSelected: selectedGhosts.contains(suggestion.id),
                onToggle: { onToggle(suggestion) },
                onDismiss: { onDismiss(suggestion) }
            )
            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98)))
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
    }
}

private struct GhostEventCard: View {
    let suggestion: Suggestion
    let selectedDate: Date
    let dayStartHour: Int
    let minuteHeight: CGFloat
    let isSelected: Bool
    let onToggle: () -> Void
    let onDismiss: () -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    
    private var calendar: Calendar { Calendar.current }
    
    private var startOfTimeline: Date {
        let dayStart = calendar.startOfDay(for: selectedDate)
        return calendar.date(byAdding: .hour, value: dayStartHour, to: dayStart) ?? dayStart
    }
    
    private var yPosition: CGFloat {
        let delta = suggestion.suggestedTime.timeIntervalSince(startOfTimeline)
        return CGFloat(delta / 60) * minuteHeight
    }
    
    private var eventHeight: CGFloat {
        let verticalPadding: CGFloat = 20
        let minimumTotalHeight: CGFloat = 44
        let rawTotalHeight = CGFloat(suggestion.duration / 60) * minuteHeight
        let adjustedTotalHeight = max(rawTotalHeight, minimumTotalHeight)
        return max(adjustedTotalHeight - verticalPadding, 0)
    }
    
    private var checkboxSymbol: String {
        isSelected ? "checkmark.circle.fill" : "circle"
    }
    
    private var checkboxTint: Color {
        isSelected ? .white : .blue.opacity(0.75)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.blue.opacity(0.35)
        }
        return Color.blue.opacity(0.18)
    }
    
    private var borderColor: Color {
        if isSelected {
            return Color.white.opacity(0.6)
        }
        return Color.blue.opacity(isHovering ? 0.55 : 0.35)
    }
    
    private var energyLabel: String {
        suggestion.energy.description.capitalized
    }
    
    private var linkedGoal: Goal? {
        guard let id = suggestion.relatedGoalId else { return nil }
        return dataManager.appState.goals.first { $0.id == id }
    }
    
    private var linkedPillar: Pillar? {
        guard let id = suggestion.relatedPillarId else { return nil }
        return dataManager.appState.pillars.first { $0.id == id }
    }
    
    private var connectionBadgeItems: [ConnectionBadgeItem] {
        var items: [ConnectionBadgeItem] = []
        if let goalTitle = resolvedGoalTitle {
            items.append(
                ConnectionBadgeItem(
                    kind: .goal,
                    id: suggestion.relatedGoalId,
                    fullTitle: goalTitle,
                    reason: suggestion.reason ?? suggestion.explanation,
                    icon: "target",
                    tint: .cyan
                )
            )
        }
        if let pillarTitle = resolvedPillarTitle {
            items.append(
                ConnectionBadgeItem(
                    kind: .pillar,
                    id: suggestion.relatedPillarId,
                    fullTitle: pillarTitle,
                    reason: suggestion.reason ?? suggestion.explanation,
                    icon: "building.columns",
                    tint: .purple
                )
            )
        }
        return items
    }
    
    private var resolvedGoalTitle: String? {
        if let goal = linkedGoal { return goal.title }
        return suggestion.relatedGoalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var resolvedPillarTitle: String? {
        if let pillar = linkedPillar { return pillar.name }
        return suggestion.relatedPillarTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var showSuggestionContext: Bool {
        dataManager.appState.preferences.showSuggestionContext
    }

    private var accessibilitySummary: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: suggestion.suggestedTime)
        let minutes = Int(suggestion.duration / 60)
        return "Suggested block \(suggestion.title) at \(timeString) for \(minutes) minutes"
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checkboxSymbol)
                    .font(.title3)
                    .foregroundStyle(checkboxTint)
                    .padding(.top, 2)
                    .symbolRenderingMode(.palette)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(suggestion.emoji) \(suggestion.title)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(2)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(suggestion.suggestedTime.timeString)
                                    .font(.caption2)
                                    .foregroundStyle(Color.white.opacity(0.7))
                                
                                // Dismiss button
                                Button(action: onDismiss) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.white.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .help("Dismiss this suggestion")
                            }
                            
                            // Add visual hint for interaction
                            if !isSelected {
                                Text("Tap to select")
                                    .font(.caption2)
                                    .foregroundStyle(Color.white.opacity(0.5))
                                    .italic()
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        TagView(
                            text: "\(Int(suggestion.duration / 60))m",
                            systemImage: "clock" 
                        )
                        TagView(
                            text: energyLabel,
                            systemImage: "sparkles"
                        )
                        if suggestion.confidence > 0 {
                            TagView(
                                text: "\(Int(suggestion.confidence * 100))%",
                                systemImage: "bolt.fill"
                            )
                        }
                    }

                    if showSuggestionContext && !connectionBadgeItems.isEmpty {
                        ConnectionBadgeRow(items: connectionBadgeItems)
                    }
                    
                    if showSuggestionContext && !suggestion.explanation.isEmpty {
                        Text(suggestion.explanation)
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
                    .blur(radius: 0.2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 6], dashPhase: 6))
                            .foregroundStyle(borderColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
        .accessibilityHint(Text("Activate to toggle this suggestion"))
        .accessibilityAddTraits(.isButton)
        .frame(height: eventHeight, alignment: .top)
        .offset(y: yPosition)
        .opacity(isHovering ? 0.95 : 0.85)
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
    }
}

private struct TagView: View {
    let text: String
    let systemImage: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.white.opacity(0.8))
    }
}

struct ConnectionBadgeRow: View {
    let items: [ConnectionBadgeItem]
    @EnvironmentObject private var mindNavigator: MindNavigationModel
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    mindNavigator.open(to: destination(for: item))
                } label: {
                    ConnectionBadgeLabel(item: item)
                }
                .buttonStyle(.plain)
                if index < items.count - 1 {
                    Rectangle()
                        .fill(item.dividerColor)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 4)
                }
            }
            Spacer(minLength: 0)
        }
    }
    
    private func destination(for item: ConnectionBadgeItem) -> MindDestination {
        switch item.kind {
        case .goal:
            return .goals(targetId: item.id)
        case .pillar:
            return .pillars(targetId: item.id)
        }
    }
    
    private struct ConnectionBadgeLabel: View {
        let item: ConnectionBadgeItem
        
        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.caption2)
                Text(item.shortTitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(item.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(item.tint)
            .help(item.tooltip)
        }
    }
}

struct ConnectionBadgeItem {
    enum Kind {
        case goal
        case pillar
    }
    
    let kind: Kind
    let id: UUID?
    let fullTitle: String
    let reason: String?
    let icon: String
    let tint: Color
    
    var shortTitle: String {
        fullTitle.badgeShortTitle()
    }
    
    var tooltip: String {
        let trimmedTitle = fullTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedReason.isEmpty else { return trimmedTitle }
        return "\(trimmedTitle)\n\(trimmedReason)"
    }
    
    var dividerColor: Color {
        tint.opacity(0.35)
    }
}

struct GhostAcceptanceBar: View {
    let totalCount: Int
    let selectedCount: Int
    let onAcceptAll: () -> Void
    let onAcceptSelected: () -> Void
    
    private var buttonTitle: String {
        selectedCount > 0 ? "Accept selected" : "Accept all"
    }
    
    private var subtitle: String {
        if selectedCount > 0 {
            return "Ready to stage \(selectedCount) pick\(selectedCount == 1 ? "" : "s")"
        }
        return "\(totalCount) ghost recommendation\(totalCount == 1 ? "" : "s") queued"
    }
    
    private var buttonAction: () -> Void {
        selectedCount > 0 ? onAcceptSelected : onAcceptAll
    }
    
    private var instructionText: String {
        if selectedCount == 0 {
            return "Tap suggestions above to select, or accept all"
        } else {
            return "Selected \(selectedCount) of \(totalCount) suggestions"
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Color.blue.opacity(0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommendations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(subtitle)
                            .font(.footnote)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
                
                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .padding(.vertical, 2)
                    .accessibilityHint(Text(selectedCount > 0 ? "Stages the selected suggestions" : "Stages all suggestions"))
            }
            
            // Add instruction text for better discoverability
            Text(instructionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(subtitle))
    }
}
