import SwiftUI

// MARK: - Mind Pillars Surface

struct MindPillarsSection: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.highlightedPillarId) private var highlightedPillarId

    @State private var showingPillarCreator = false
    @State private var selectedPillar: Pillar?
    @State private var editingPillar: Pillar?

    private var pillars: [Pillar] {
        let emphasized = dataManager.appState.emphasizedPillarIds
        return dataManager.appState.pillars.sorted { lhs, rhs in
            let lhsEmphasis = emphasized.contains(lhs.id)
            let rhsEmphasis = emphasized.contains(rhs.id)
            if lhsEmphasis != rhsEmphasis {
                return lhsEmphasis && !rhsEmphasis
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Pillars",
                subtitle: "Principles that bias the engine, never auto-book",
                systemImage: "building.columns.circle",
                gradient: LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                onAction: { showingPillarCreator = true }
            )

            if pillars.isEmpty {
                MindEmptyPillarsCard {
                    showingPillarCreator = true
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(pillars) { pillar in
                        let isEmphasized = dataManager.isPillarEmphasized(pillar.id)
                        MindPillarCard(
                            pillar: pillar,
                            isEmphasized: isEmphasized,
                            isHighlighted: highlightedPillarId == pillar.id,
                            onTap: {
                                selectedPillar = dataManager.appState.pillars.first(where: { $0.id == pillar.id }) ?? pillar
                            },
                            onToggleEmphasis: {
                                dataManager.togglePillarEmphasis(pillar.id)
                            },
                            onEdit: {
                                editingPillar = dataManager.appState.pillars.first(where: { $0.id == pillar.id }) ?? pillar
                            },
                            onDelete: {
                                dataManager.removePillar(pillar.id)
                            }
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingPillarCreator) {
            ComprehensivePillarCreatorSheet { newPillar in
                dataManager.addPillar(newPillar)
                selectedPillar = dataManager.appState.pillars.first(where: { $0.id == newPillar.id })
            }
        }
        .sheet(item: $selectedPillar) { pillar in
            PillarDetailSheet(
                pillar: pillar,
                isEmphasized: dataManager.isPillarEmphasized(pillar.id),
                onToggleEmphasis: {
                    dataManager.togglePillarEmphasis(pillar.id)
                },
                onEdit: {
                    editingPillar = dataManager.appState.pillars.first(where: { $0.id == pillar.id }) ?? pillar
                },
                onDelete: {
                    dataManager.removePillar(pillar.id)
                    selectedPillar = nil
                }
            )
        }
        .sheet(item: $editingPillar) { pillar in
            ComprehensivePillarEditorSheet(pillar: pillar) { updatedPillar in
                dataManager.updatePillar(updatedPillar)
                if let refreshed = dataManager.appState.pillars.first(where: { $0.id == updatedPillar.id }) {
                    selectedPillar = refreshed
                }
            }
        }
    }
}

// MARK: - Pillar Cards & Detail

struct MindPillarCard: View {
    let pillar: Pillar
    let isEmphasized: Bool
    let isHighlighted: Bool
    let onTap: () -> Void
    let onToggleEmphasis: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var borderColor: Color {
        pillar.color.color.opacity(isHighlighted ? 0.9 : 0.35)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(pillar.emoji)
                        .font(.title2)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pillar.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(pillar.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if isEmphasized {
                        Label("Boosted", systemImage: "sparkles")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.15), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }

                if let wisdom = pillar.wisdomText?.nilIfEmpty {
                    Text("“\(wisdom)”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                }

                PillarSummaryRow(icon: "diamond.fill", title: "Values", items: pillar.values, limit: 3)
                PillarSummaryRow(icon: "figure.run", title: "Habits", items: pillar.habits, limit: 2)
                PillarSummaryRow(icon: "shield.lefthalf.filled", title: "Constraints", items: pillar.constraints, limit: 2)

                HStack {
                    Label(pillar.frequencyDescription, systemImage: "metronome")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !pillar.quietHours.isEmpty {
                        Label("\(pillar.quietHours.count) quiet \(pillar.quietHours.count == 1 ? "window" : "windows")", systemImage: "moon.zzz")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isHighlighted ? 2.5 : 1)
        )
        .shadow(color: borderColor.opacity(isHighlighted ? 0.45 : 0.0), radius: isHighlighted ? 12 : 0, x: 0, y: 6)
        .contextMenu {
            Button {
                onToggleEmphasis()
            } label: {
                Label(isEmphasized ? "Drop emphasis" : "Emphasize pillar", systemImage: isEmphasized ? "star.slash" : "star.fill")
            }

            Button(action: onEdit) {
                Label("Edit pillar", systemImage: "square.and.pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete pillar", systemImage: "trash")
            }
        }
    }
}

struct MindEmptyPillarsCard: View {
    let onCreate: () -> Void

    var body: some View {
        Button(action: onCreate) {
            VStack(spacing: 12) {
                Text("🧭")
                    .font(.largeTitle)
                    .opacity(0.7)

                Text("Define your first pillar")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Pillars capture the principles you want the planner to defend. They bias ghost suggestions — nothing auto-books without you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Create pillar")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
        )
    }
}

struct PillarSummaryRow: View {
    let icon: String
    let title: String
    let items: [String]
    let limit: Int

    private var displayItems: [String] {
        Array(items.prefix(limit))
    }

    var body: some View {
        Group {
            if !displayItems.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Text(displayItems.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

struct PillarDetailSheet: View {
    let pillar: Pillar
    private let onToggleEmphasis: () -> Void
    private let onEdit: () -> Void
    private let onDelete: () -> Void

    @State private var isEmphasized: Bool
    @State private var showingDeleteConfirmation = false

    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.dismiss) private var dismiss

    init(
        pillar: Pillar,
        isEmphasized: Bool,
        onToggleEmphasis: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.pillar = pillar
        self.onToggleEmphasis = onToggleEmphasis
        self.onEdit = onEdit
        self.onDelete = onDelete
        self._isEmphasized = State(initialValue: isEmphasized)
    }

    private var relatedGoal: Goal? {
        dataManager.appState.goals.first(where: { $0.id == pillar.relatedGoalId })
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    emphasisControls
                    if let wisdom = pillar.wisdomText?.nilIfEmpty { wisdomSection(wisdom) }
                    detailSection(icon: "diamond.fill", title: "Values", items: pillar.values)
                    detailSection(icon: "figure.run", title: "Habits", items: pillar.habits)
                    detailSection(icon: "shield.lefthalf.filled", title: "Constraints", items: pillar.constraints)
                    quietHoursSection
                    if let goal = relatedGoal { relatedGoalSection(goal) }
                    guidanceSection
                    footerMeta
                    deleteButton
                }
                .padding(24)
            }
            .background(.ultraThinMaterial)
            .navigationTitle("Pillar detail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        dismiss()
                        onEdit()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 540)
        .confirmationDialog("Delete this pillar?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete pillar", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the pillar and its influence on future suggestions.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(pillar.emoji)
                    .font(.system(size: 44))

                VStack(alignment: .leading, spacing: 6) {
                    Text(pillar.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(pillar.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Label(pillar.frequencyDescription, systemImage: "metronome")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.12), in: Capsule())
                if !pillar.quietHours.isEmpty {
                    Label("Quiet hours", systemImage: "moon.zzz")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.indigo.opacity(0.12), in: Capsule())
                }
                if isEmphasized {
                    Label("Boosted", systemImage: "sparkles")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.purple.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private var emphasisControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Influence scheduling")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Emphasized pillars appear more often in ghost suggestions, but nothing auto-books without you.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                onToggleEmphasis()
                isEmphasized.toggle()
            } label: {
                Label(isEmphasized ? "Drop emphasis" : "Emphasize pillar", systemImage: isEmphasized ? "star.slash" : "star.fill")
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(isEmphasized ? .purple : .blue)
        }
    }

    private func wisdomSection(_ wisdom: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Principle", systemImage: "lightbulb")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(wisdom)
                .font(.body)
        }
    }

    private func detailSection(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
            if items.isEmpty {
                Text("No entries yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                PillarTagList(items: items)
            }
        }
    }

    private var quietHoursSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quiet hours", systemImage: "moon.zzz")
                .font(.subheadline)
                .fontWeight(.semibold)
            if pillar.quietHours.isEmpty {
                Text("No quiet hours defined")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                PillarTagList(items: pillar.quietHours.map { $0.description })
            }
        }
    }

    private func relatedGoalSection(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Supports goal", systemImage: "target")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\(goal.emoji) \(goal.title)")
                .font(.body)
            Text(goal.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Guidance to AI", systemImage: "brain.head.profile")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(pillar.aiGuidanceText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footerMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Created \(pillar.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let goal = relatedGoal {
                Text("Biasing toward \(goal.title) when planning")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("Delete pillar", systemImage: "trash")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

struct PillarTagList: View {
    let items: [String]

    private let columns = [
        GridItem(.flexible(minimum: 60), spacing: 6),
        GridItem(.flexible(minimum: 60), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

// MARK: - Comprehensive Pillar Creator

struct ComprehensivePillarEditorSheet: View {
    let pillar: Pillar
    let onPillarUpdated: (Pillar) -> Void
    @EnvironmentObject private var dataManager: AppDataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var frequency: PillarFrequency
    @State private var valuesText: String
    @State private var habitsText: String
    @State private var constraintsText: String
    @State private var quietHoursText: String
    @State private var wisdomText: String
    @State private var emoji: String
    @State private var selectedColor: Color
    @State private var relatedGoalId: UUID?
    
    init(pillar: Pillar, onPillarUpdated: @escaping (Pillar) -> Void) {
        self.pillar = pillar
        self.onPillarUpdated = onPillarUpdated
        self._name = State(initialValue: pillar.name)
        self._description = State(initialValue: pillar.description)
        self._frequency = State(initialValue: pillar.frequency)
        self._valuesText = State(initialValue: pillar.values.joined(separator: ", "))
        self._habitsText = State(initialValue: pillar.habits.joined(separator: ", "))
        self._constraintsText = State(initialValue: pillar.constraints.joined(separator: ", "))
        self._quietHoursText = State(initialValue: pillar.quietHours.map { $0.description }.joined(separator: ", "))
        self._wisdomText = State(initialValue: pillar.wisdomText ?? "")
        self._emoji = State(initialValue: pillar.emoji)
        self._selectedColor = State(initialValue: pillar.color.color)
        self._relatedGoalId = State(initialValue: pillar.relatedGoalId)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    identitySection
                    rhythmSection
                    valuesSection
                    habitsSection
                    constraintsSection
                    quietHoursSection
                    wisdomSection
                    linkingSection
                    appearanceSection
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 700)
        .overlay(alignment: .topTrailing) {
            Button("Done") {
                savePillar()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .overlay(alignment: .topLeading) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Identity", subtitle: "Give this pillar a memorable anchor", systemImage: "person.circle", gradient: LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Emoji")
                        .font(.caption)
                        .fontWeight(.medium)

                    EmojiPickerButton(selectedEmoji: $emoji)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption)
                        .fontWeight(.medium)

                    TextField("Deep Work", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .fontWeight(.medium)

                TextField("What this pillar defends in your life", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var rhythmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Rhythm", subtitle: "How often this principle should surface", systemImage: "metronome", gradient: LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing))

            Picker("How often", selection: $frequency) {
                ForEach(PillarFrequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)

            Text("The learner prioritises pillars with higher cadence when creating ghosts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var valuesSection: some View {
        PillarListEditor(
            title: "Values",
            subtitle: "Comma-separated values this pillar protects (e.g. focus, craft, calm).",
            placeholder: "focus, craft, calm",
            text: $valuesText
        )
    }

    private var habitsSection: some View {
        PillarListEditor(
            title: "Habits",
            subtitle: "What behaviours should the engine encourage when this pillar is active?",
            placeholder: "90-minute deep work, midday reset walk",
            text: $habitsText
        )
    }

    private var constraintsSection: some View {
        PillarListEditor(
            title: "Constraints",
            subtitle: "Boundaries to respect when trading against this pillar.",
            placeholder: "no meetings before 11, defend Fridays for focus",
            text: $constraintsText
        )
    }

    private var quietHoursSection: some View {
        PillarListEditor(
            title: "Quiet Hours",
            subtitle: "Format each window as HH:MM-HH:MM. Separate multiple ranges with commas or line breaks.",
            placeholder: "06:00-08:30, 21:00-23:00",
            text: $quietHoursText
        )
    }

    private var wisdomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Wisdom", subtitle: "Short principle statement sent to the AI", systemImage: "lightbulb", gradient: LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))

            TextField("Reminder phrase", text: $wisdomText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var linkingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Connections", subtitle: "Tie this pillar to a goal (optional)", systemImage: "target", gradient: LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing))

            Picker("Supports goal", selection: $relatedGoalId) {
                Text("None").tag(nil as UUID?)
                ForEach(dataManager.appState.goals) { goal in
                    Text(goal.title).tag(goal.id as UUID?)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Appearance", subtitle: "Color cues in calendar & Mind view", systemImage: "paintpalette", gradient: LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))

            ColorPicker("Accent", selection: $selectedColor, supportsOpacity: false)
            Text("Used for chips, badges, and goal graph references.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func savePillar() {
        let updatedPillar = Pillar(
            id: pillar.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            frequency: frequency,
            quietHours: sanitizedQuietHours(from: quietHoursText),
            wisdomText: wisdomText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            values: sanitizedPillarStrings(from: valuesText),
            habits: sanitizedPillarStrings(from: habitsText),
            constraints: sanitizedPillarStrings(from: constraintsText),
            color: CodableColor(selectedColor),
            emoji: emoji.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "🏛️",
            relatedGoalId: relatedGoalId,
            createdAt: pillar.createdAt
        )

        onPillarUpdated(updatedPillar)
    }
}

private struct PillarListEditor: View {
    let title: String
    let subtitle: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle, systemImage: "list.bullet", gradient: LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing))

            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private func sanitizedPillarStrings(from text: String) -> [String] {
    let separators = CharacterSet(charactersIn: ",\n")
    var seen = Set<String>()
    return text
        .components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { item in
            let lowered = item.lowercased()
            if seen.contains(lowered) {
                return false
            } else {
                seen.insert(lowered)
                return true
            }
        }
}

private func sanitizedQuietHours(from text: String) -> [TimeWindow] {
    let separators = CharacterSet(charactersIn: ",\n")
    var windows: [TimeWindow] = []
    var seen = Set<String>()

    for candidate in text.components(separatedBy: separators) {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let window = parseTimeWindowString(trimmed) else { continue }
        let key = "\(window.startHour):\(window.startMinute)-\(window.endHour):\(window.endMinute)"
        if seen.insert(key).inserted {
            windows.append(window)
        }
    }

    return windows
}

private func parseTimeWindowString(_ text: String) -> TimeWindow? {
    let parts = text.split(separator: "-")
    guard parts.count == 2,
          let start = parseClockString(String(parts[0])),
          let end = parseClockString(String(parts[1])) else { return nil }
    let startMinutes = start.hour * 60 + start.minute
    let endMinutes = end.hour * 60 + end.minute
    guard endMinutes > startMinutes else { return nil }
    return TimeWindow(startHour: start.hour, startMinute: start.minute, endHour: end.hour, endMinute: end.minute)
}

private func parseClockString(_ text: String) -> (hour: Int, minute: Int)? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = trimmed.split(separator: ":")
    guard components.count == 2,
          let hour = Int(components[0]),
          let minute = Int(components[1]),
          (0..<24).contains(hour),
          (0..<60).contains(minute) else { return nil }
    return (hour, minute)
}

struct ComprehensivePillarCreatorSheet: View {
    let onPillarCreated: (Pillar) -> Void
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @Environment(\.dismiss) private var dismiss
    
    @State private var pillarName = ""
    @State private var pillarDescription = ""
    @State private var selectedFrequency: PillarFrequency = .daily
    @State private var valuesText = ""
    @State private var habitsText = ""
    @State private var constraintsText = ""
    @State private var quietHoursText = ""
    @State private var wisdomText = ""
    @State private var selectedColor: Color = .blue
    @State private var selectedEmoji = "🏛️"
    @State private var relatedGoalId: UUID?
    @State private var isGeneratingAI = false
    @State private var aiSuggestions = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    identitySection
                    rhythmSection
                    valuesSection
                    habitsSection
                    constraintsSection
                    quietHoursSection
                    wisdomSection
                    linkingSection
                    appearanceSection
                    aiAssistSection
                }
                .padding(24)
            }
            .navigationTitle("Create Pillar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createPillar()
                    }
                    .disabled(pillarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 620, height: 720)
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Identity", subtitle: "Give the pillar a clear signal", systemImage: "person.crop.square", gradient: LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
            
            HStack(spacing: 12) {
                TextField("Pillar name", text: $pillarName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                
                EmojiPickerButton(selectedEmoji: $selectedEmoji)
            }
            
            TextField("Describe why this matters", text: $pillarDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var rhythmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Rhythm", subtitle: "How often should this principle surface?", systemImage: "metronome", gradient: LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing))

            Picker("Cadence", selection: $selectedFrequency) {
                ForEach(PillarFrequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)

            Text("This hints to the learner how frequently to bias ghosts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var valuesSection: some View {
        PillarListEditor(
            title: "Values",
            subtitle: "Comma-separated values this pillar defends (e.g. focus, craft, calm)",
            placeholder: "focus, craft, calm",
            text: $valuesText
        )
    }

    private var habitsSection: some View {
        PillarListEditor(
            title: "Habits",
            subtitle: "Behaviours the AI should encourage when this pillar is active.",
            placeholder: "90-minute deep work, midday reset walk",
            text: $habitsText
        )
    }

    private var constraintsSection: some View {
        PillarListEditor(
            title: "Constraints",
            subtitle: "Hard boundaries that shape scheduling decisions.",
            placeholder: "no meetings before 11, defend Fridays for focus",
            text: $constraintsText
        )
    }

    private var quietHoursSection: some View {
        PillarListEditor(
            title: "Quiet Hours",
            subtitle: "Use HH:MM-HH:MM (comma or newline separated)",
            placeholder: "06:00-08:30, 21:00-23:00",
            text: $quietHoursText
        )
    }

    private var wisdomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Wisdom", subtitle: "Short principle for the AI to remember", systemImage: "lightbulb", gradient: LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
            TextField("Guiding phrase", text: $wisdomText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var linkingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Connections", subtitle: "Optionally link to a goal", systemImage: "target", gradient: LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing))
            Picker("Supports goal", selection: $relatedGoalId) {
                Text("None").tag(nil as UUID?)
                ForEach(dataManager.appState.goals) { goal in
                    Text(goal.title).tag(goal.id as UUID?)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Appearance", subtitle: "Color accents for this pillar", systemImage: "paintpalette", gradient: LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
            ColorPicker("Accent", selection: $selectedColor, supportsOpacity: false)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var aiAssistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "AI Assist", subtitle: "Let the planner suggest details", systemImage: "sparkles", gradient: LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))

            HStack(spacing: 12) {
                Button {
                    generateAISuggestions()
                } label: {
                    Label("Generate Suggestions", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingAI || pillarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isGeneratingAI {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Button {
                createPillarWithAI()
            } label: {
                Label("Create & Enhance with AI", systemImage: "sparkle")
            }
            .buttonStyle(.bordered)
            .disabled(pillarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !aiSuggestions.isEmpty {
                Text(aiSuggestions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func createPillar() {
        let pillar = buildPillar()
        onPillarCreated(pillar)
        dismiss()
    }

    private func buildPillar() -> Pillar {
        Pillar(
            name: pillarName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: pillarDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "",
            frequency: selectedFrequency,
            quietHours: sanitizedQuietHours(from: quietHoursText),
            wisdomText: wisdomText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            values: sanitizedPillarStrings(from: valuesText),
            habits: sanitizedPillarStrings(from: habitsText),
            constraints: sanitizedPillarStrings(from: constraintsText),
            color: CodableColor(selectedColor),
            emoji: selectedEmoji.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "🏛️",
            relatedGoalId: relatedGoalId
        )
    }

    private func generateAISuggestions() {
        let trimmedName = pillarName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !isGeneratingAI else { return }

        isGeneratingAI = true
        aiSuggestions = ""

        Task {
            let prompt = """
            You are helping define a personal planning pillar for a local-first calendar.
            Return ONLY valid JSON matching this schema:
            {
              "description": "string",
              "wisdom": "string",
              "values": ["string"],
              "habits": ["string"],
              "constraints": ["string"],
              "quiet_hours": ["HH:MM-HH:MM"],
              "frequency": "daily|weekly|monthly|as needed"
            }

            Current inputs:
            Name: \(trimmedName)
            Description: \(pillarDescription)
            Values: \(valuesText)
            Habits: \(habitsText)
            Constraints: \(constraintsText)
            QuietHours: \(quietHoursText)

            Respond with JSON only.
            """

            do {
                let context = dataManager.createEnhancedContext()
                let response = try await aiService.processMessage(prompt, context: context)

                await MainActor.run {
                    if let suggestion = decodeSuggestion(from: response.text) {
                        applySuggestion(suggestion)
                        aiSuggestions = summary(for: suggestion)
                    } else {
                        aiSuggestions = response.text
                    }
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiSuggestions = "Assistant unavailable. Try again in a moment."
                    isGeneratingAI = false
                }
            }
        }
    }

    private func createPillarWithAI() {
        Task {
            let newPillar = buildPillar()
            
            do {
                let enhancedPillar = try await enhancePillarWithAI(newPillar)
                
                await MainActor.run {
                    onPillarCreated(enhancedPillar)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    onPillarCreated(newPillar)
                    dismiss()
                }
            }
        }
    }
    
    private func enhancePillarWithAI(_ pillar: Pillar) async throws -> Pillar {
        let context = dataManager.createEnhancedContext()
        let prompt = """
        Improve the following planning pillar using user context. Return ONLY valid JSON with the same schema as earlier.

        Pillar:
        Name: \(pillar.name)
        Description: \(pillar.description)
        Values: \(pillar.values.joined(separator: ", "))
        Habits: \(pillar.habits.joined(separator: ", "))
        Constraints: \(pillar.constraints.joined(separator: ", "))
        QuietHours: \(pillar.quietHours.map { $0.description }.joined(separator: ", "))
        Wisdom: \(pillar.wisdomText ?? "")
        Frequency: \(pillar.frequency.displayName)

        User context: \(context.summary)
        """
        
        let response = try await aiService.processMessage(prompt, context: context)
        if let suggestion = decodeSuggestion(from: response.text) {
            var enhanced = pillar
            if let description = suggestion.description?.nilIfEmpty {
                enhanced.description = description
            }
            if let wisdom = suggestion.wisdom?.nilIfEmpty {
                enhanced.wisdomText = wisdom
            }
            if let values = suggestion.values, !values.isEmpty {
                enhanced.values = sanitizedPillarStrings(from: values.joined(separator: ", "))
            }
            if let habits = suggestion.habits, !habits.isEmpty {
                enhanced.habits = sanitizedPillarStrings(from: habits.joined(separator: ", "))
            }
            if let constraints = suggestion.constraints, !constraints.isEmpty {
                enhanced.constraints = sanitizedPillarStrings(from: constraints.joined(separator: ", "))
            }
            if let quiet = suggestion.quiet_hours, !quiet.isEmpty {
                enhanced.quietHours = sanitizedQuietHours(from: quiet.joined(separator: ", "))
            }
            if let freq = suggestion.frequency {
                enhanced.frequency = resolveFrequency(freq)
            }
            return enhanced
        }

        var fallback = pillar
        if pillar.description.isEmpty {
            fallback.description = response.text
        }
        if fallback.wisdomText?.isEmpty != false {
            fallback.wisdomText = response.text
        }
        return fallback
    }

    private func applySuggestion(_ suggestion: PillarSuggestion) {
        if let description = suggestion.description?.nilIfEmpty {
            pillarDescription = description
        }
        if let wisdom = suggestion.wisdom?.nilIfEmpty {
            wisdomText = wisdom
        }
        if let values = suggestion.values, !values.isEmpty {
            valuesText = values.joined(separator: ", ")
        }
        if let habits = suggestion.habits, !habits.isEmpty {
            habitsText = habits.joined(separator: ", ")
        }
        if let constraints = suggestion.constraints, !constraints.isEmpty {
            constraintsText = constraints.joined(separator: ", ")
        }
        if let quiet = suggestion.quiet_hours, !quiet.isEmpty {
            quietHoursText = quiet.joined(separator: ", ")
        }
        if let frequency = suggestion.frequency {
            selectedFrequency = resolveFrequency(frequency)
        }
    }

    private func decodeSuggestion(from responseText: String) -> PillarSuggestion? {
        let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else { return nil }
        let jsonSlice = cleaned[start...end]
        guard let data = jsonSlice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PillarSuggestion.self, from: data)
    }

    private func summary(for suggestion: PillarSuggestion) -> String {
        var lines: [String] = []
        if let description = suggestion.description?.nilIfEmpty {
            lines.append("Description → \(description)")
        }
        if let values = suggestion.values, !values.isEmpty {
            lines.append("Values → \(values.joined(separator: ", "))")
        }
        if let habits = suggestion.habits, !habits.isEmpty {
            lines.append("Habits → \(habits.joined(separator: ", "))")
        }
        if let constraints = suggestion.constraints, !constraints.isEmpty {
            lines.append("Constraints → \(constraints.joined(separator: ", "))")
        }
        if let quiet = suggestion.quiet_hours, !quiet.isEmpty {
            lines.append("Quiet hours → \(quiet.joined(separator: ", "))")
        }
        if let freq = suggestion.frequency?.nilIfEmpty {
            lines.append("Frequency → \(freq)")
        }
        if let wisdom = suggestion.wisdom?.nilIfEmpty {
            lines.append("Wisdom → \(wisdom)")
        }
        return lines.joined(separator: "\n")
    }

    private func resolveFrequency(_ text: String) -> PillarFrequency {
        let lower = text.lowercased()
        if lower.contains("need") { return .asNeeded }
        if lower.contains("daily") { return .daily }
        if lower.contains("month") {
            let count = Int(lower.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            return .monthly(max(1, count))
        }
        if lower.contains("week") {
            let count = Int(lower.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            return .weekly(max(1, count))
        }
        return .weekly(1)
    }

    private struct PillarSuggestion: Decodable {
        let description: String?
        let wisdom: String?
        let values: [String]?
        let habits: [String]?
        let constraints: [String]?
        let quiet_hours: [String]?
        let frequency: String?
        
        private enum CodingKeys: String, CodingKey {
            case description, wisdom, values, habits, constraints
            case quiet_hours = "quiet_hours"
            case frequency
        }
    }
}

struct TimeWindowCreatorSheet: View {
    let onWindowCreated: (TimeWindow) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var startHour = 9
    @State private var startMinute = 0
    @State private var endHour = 10
    @State private var endMinute = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Time Window")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("When is this activity best scheduled?")
                    .font(.subheadline)
                
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Time")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        HStack {
                            Picker("Hour", selection: $startHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text("\(hour):00").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                            
                            Picker("Minute", selection: $startMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text(":\(String(format: "%02d", minute))").tag(minute)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 60)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("End Time")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        HStack {
                            Picker("Hour", selection: $endHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text("\(hour):00").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                            
                            Picker("Minute", selection: $endMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text(":\(String(format: "%02d", minute))").tag(minute)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 60)
                        }
                    }
                }
            }
            
            Text("Current window: \(String(format: "%02d:%02d", startHour, startMinute)) - \(String(format: "%02d:%02d", endHour, endMinute))")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Add Window") {
                    let newWindow = TimeWindow(
                        startHour: startHour,
                        startMinute: startMinute,
                        endHour: endHour,
                        endMinute: endMinute
                    )
                    onWindowCreated(newWindow)
                }
                .buttonStyle(.borderedProminent)
                .disabled(endHour < startHour || (endHour == startHour && endMinute <= startMinute))
            }
        }
        .padding(24)
        .frame(width: 400, height: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct EnhancedPillarCard: View {
    let pillar: Pillar
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var isHovering = false
    @State private var showingPillarDetail = false
    
    var body: some View {
        Button(action: { showingPillarDetail = true }) {
            VStack(spacing: 8) {
                // Pillar emoji
                Text(pillar.emoji)
                    .font(.title2)
                    .frame(height: 24)
                
                Text(pillar.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                // Frequency status
                VStack(spacing: 2) {
                    Text(pillar.frequencyDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    if let wisdom = pillar.wisdomText?.nilIfEmpty {
                        Text(wisdom)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !pillar.values.isEmpty {
                        Text(pillar.values.prefix(2).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !pillar.habits.isEmpty {
                        Text(pillar.habits.prefix(1).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(isHovering ? 0.6 : 0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(pillar.color.color.opacity(isHovering ? 0.5 : 0.2), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        // No animation to prevent flashing
        .onHover { hovering in 
            isHovering = hovering 
        }
        .sheet(isPresented: $showingPillarDetail) {
            ComprehensivePillarEditorSheet(pillar: pillar) { updatedPillar in
                dataManager.updatePillar(updatedPillar)
            }
        }
    }
}

struct EnhancedGoalsSection: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @State private var showingGoalCreator = false
    @State private var showingGoalBreakdown = false
    @State private var selectedGoal: Goal?
    @State private var showingGoalDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
            SectionHeader(
                title: "Goals",
                    subtitle: "Smart breakdown & tracking", 
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
}

struct AuroraDreamBuilderSection: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var showingDreamBuilder = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Dreams",
                subtitle: "Future visions",
                systemImage: "sparkles.circle", 
                gradient: LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing)
            )
            
            // Simplified dream builder interface
            VStack(spacing: 8) {
                AuroraDreamCard()
                
                Button("✨ Build New Vision") {
                    showingDreamBuilder = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
            }
        }
        .sheet(isPresented: $showingDreamBuilder) {
            Text("Dream Builder - Coming Soon")
                .padding()
        }
    }
}

// MARK: - Emoji Picker Button

struct EmojiPickerButton: View {
    @Binding var selectedEmoji: String
    @State private var showingEmojiPicker = false
    
    private let commonEmojis = [
        "🏛️", "💪", "🧠", "❤️", "🎯", "📚", "🏃‍♀️", "🍎",
        "💼", "🎨", "🌱", "⚡", "🔥", "🌊", "☀️", "🌙",
        "🎵", "📝", "💡", "🚀", "🏆", "🎪", "🌈", "⭐",
        "🔮", "💎", "🌸", "🍀", "🦋", "🌺", "🌻", "🌹"
    ]
    
    var body: some View {
        Button(action: {
            showingEmojiPicker.toggle()
        }) {
            Text(selectedEmoji.isEmpty ? "🏛️" : selectedEmoji)
                .font(.title2)
                .frame(width: 60, height: 40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingEmojiPicker) {
            EmojiPickerView(selectedEmoji: $selectedEmoji, emojis: commonEmojis) {
                showingEmojiPicker = false
            }
        }
    }
}

struct EmojiPickerView: View {
    @Binding var selectedEmoji: String
    let emojis: [String]
    let onSelection: () -> Void
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Emoji")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button(action: {
                            selectedEmoji = emoji
                            onSelection()
                        }) {
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(
                                    selectedEmoji == emoji ? 
                                        .blue.opacity(0.2) : 
                                        .clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 300)
        }
        .padding(.vertical)
        .frame(width: 360)
    }
}
