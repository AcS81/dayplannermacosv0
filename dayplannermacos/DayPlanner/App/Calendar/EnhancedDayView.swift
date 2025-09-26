// MARK: - Enhanced Day View

import SwiftUI

struct GhostAcceptanceInfo: Equatable {
    let totalCount: Int
    let selectedCount: Int
    let acceptAll: () -> Void
    let acceptSelected: () -> Void
    
    static func == (lhs: GhostAcceptanceInfo, rhs: GhostAcceptanceInfo) -> Bool {
        return lhs.totalCount == rhs.totalCount && lhs.selectedCount == rhs.selectedCount
    }
}


struct EnhancedDayView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var selectedDate: Date
    @Binding private var ghostSuggestions: [Suggestion]
    @Binding private var showingRecommendations: Bool
    @State private var showingBlockCreation = false
    @State private var creationTime: Date?
    @State private var draggedBlock: TimeBlock?
    @State private var selectedGhostIDs: Set<UUID> = []
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var diagnosticsOverride = false
    
    private let onAcceptanceInfoChange: (GhostAcceptanceInfo?) -> Void
    
    // Constants for precise timeline sizing - match timeline canvas (60 pixels per hour)
    private let minuteHeight: CGFloat = 60.0 / 60.0 // 60 pixels per hour = 1 pixel per minute
    private let dayStartHour: Int = 0
    private let dayEndHour: Int = 24
    private let ghostRefreshInterval: UInt64 = 8_000_000_000 // 8 seconds

    init(
        selectedDate: Binding<Date>,
        ghostSuggestions: Binding<[Suggestion]> = .constant([]),
        showingRecommendations: Binding<Bool> = .constant(true),
        onAcceptanceInfoChange: @escaping (GhostAcceptanceInfo?) -> Void = { _ in }
    ) {
        _selectedDate = selectedDate
        _ghostSuggestions = ghostSuggestions
        _showingRecommendations = showingRecommendations
        self.onAcceptanceInfoChange = onAcceptanceInfoChange
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Proportional timeline view where duration = visual height
            ScrollView {
                ProportionalTimelineView(
                    selectedDate: selectedDate,
                    blocks: allBlocksForDay,
                    draggedBlock: draggedBlock,
                    minuteHeight: minuteHeight,
                    onTap: { time in
                        creationTime = time
                        showingBlockCreation = true
                    },
                    onBlockDrag: { block, location in
                        draggedBlock = block
                    },
                    onBlockDrop: { block, newTime in
                        handleBlockDrop(block: block, newTime: newTime)
                        draggedBlock = nil
                    },
                    showGhosts: showingRecommendations,
                    ghostSuggestions: ghostSuggestions,
                    dayStartHour: dayStartHour,
                    selectedGhosts: $selectedGhostIDs,
                    onGhostToggle: toggleGhostSelection,
                    onGhostReject: rejectGhostSuggestion
                )
                .padding(.trailing, 2)
                .padding(.bottom, ghostAcceptanceInset)
                .background(Color.clear)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(draggedBlock != nil) // Disable scroll when dragging an event
        }
        .onChange(of: selectedDate) { oldValue, newValue in
            diagnosticsOverride = false
            dataManager.diagnosticsGhostOverrideActive = false
            dataManager.switchToDay(newValue)
            Task { @MainActor in
                await refreshGhosts(force: true)
            }
        }
        .onAppear {
            selectedDate = dataManager.appState.currentDay.date
            if showingRecommendations {
                startGhostRefresh(force: true)
            }
            updateAcceptanceInfo()
        }
        .onDisappear {
            stopGhostRefresh()
            onAcceptanceInfoChange(nil)
        }
        .onChange(of: showingRecommendations) { _, isEnabled in
            if isEnabled {
                startGhostRefresh(force: true)
                updateAcceptanceInfo()
            } else {
                stopGhostRefresh()
                selectedGhostIDs.removeAll()
                diagnosticsOverride = false
                dataManager.diagnosticsGhostOverrideActive = false
                onAcceptanceInfoChange(nil)
            }
        }
        .onChange(of: dataManager.appState.preferences.autoRefreshRecommendations) { _, newValue in
            if showingRecommendations {
                if newValue {
                    startGhostRefresh(force: true)
                } else {
                    stopGhostRefresh()
                }
            }
        }
        .onChange(of: ghostSuggestions.count) { _, _ in
            updateAcceptanceInfo()
        }
        .onChange(of: selectedGhostIDs) { _, _ in
            updateAcceptanceInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .diagnosticsSpawnGhosts)) { notification in
            guard let count = notification.userInfo?["count"] as? Int, count > 0 else { return }
            diagnosticsOverride = true
            dataManager.diagnosticsGhostOverrideActive = true
            stopGhostRefresh()
            selectedGhostIDs.removeAll()
            let diagnosticsSuggestions = makeDiagnosticsSuggestions(count: count)
            if reduceMotion {
                ghostSuggestions = diagnosticsSuggestions
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    ghostSuggestions = diagnosticsSuggestions
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .diagnosticsClearGhosts)) { _ in
            diagnosticsOverride = false
            dataManager.diagnosticsGhostOverrideActive = false
            ghostSuggestions.removeAll()
            selectedGhostIDs.removeAll()
            if showingRecommendations {
                startGhostRefresh(force: true)
            }
        }
        .sheet(isPresented: $showingBlockCreation) {
            BlockCreationSheet(
                suggestedTime: creationTime ?? Date(),
                onCreate: { block in
                    dataManager.addTimeBlock(block)
                    showingBlockCreation = false
                }
            )
        }
    }
    
    private var allBlocksForDay: [TimeBlock] {
        dataManager.appState.currentDay.blocks.sorted { $0.startTime < $1.startTime }
    }
    
    private func handleBlockDrop(block: TimeBlock, newTime: Date) {
        var updatedBlock = block
        updatedBlock.startTime = newTime
        dataManager.updateTimeBlock(updatedBlock)
    }

    private var ghostAcceptanceInset: CGFloat {
        (showingRecommendations && !ghostSuggestions.isEmpty) ? 168 : 24
    }

    private var acceptanceInfo: GhostAcceptanceInfo? {
        guard showingRecommendations && !ghostSuggestions.isEmpty else { return nil }
        return GhostAcceptanceInfo(
            totalCount: ghostSuggestions.count,
            selectedCount: selectedGhostIDs.count,
            acceptAll: acceptAllGhosts,
            acceptSelected: acceptSelectedGhosts
        )
    }

    private func updateAcceptanceInfo() {
        onAcceptanceInfoChange(acceptanceInfo)
    }

    private func makeDiagnosticsSuggestions(count: Int) -> [Suggestion] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let baseDuration: TimeInterval = 45 * 60
        let spacing: TimeInterval = 60 * 60
        return (0..<count).map { index in
            let start = dayStart.addingTimeInterval(TimeInterval(index) * spacing)
            return Suggestion(
                title: "Perf Test Block \(index + 1)",
                duration: baseDuration,
                suggestedTime: start,
                energy: .daylight,
                emoji: "⚙️",
                explanation: "Diagnostics sample suggestion",
                confidence: 0.9,
                weight: Double.random(in: 0.2...0.95)
            )
        }
    }

    private func rejectGhostSuggestion(_ suggestion: Suggestion) {
        dataManager.recordGhostRejectionMemory(for: suggestion)
        selectedGhostIDs.remove(suggestion.id)

        let removal = {
            ghostSuggestions.removeAll { $0.id == suggestion.id }
        }

        if reduceMotion {
            removal()
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                removal()
            }
        }

        onGhostAcceptanceChange?(acceptanceInfo)

        guard showingRecommendations, !diagnosticsOverride else { return }

        Task { @MainActor in
            await refreshGhosts(reason: .rejectedSuggestion)
        }
    }

    private func toggleGhostSelection(_ suggestion: Suggestion) {
        if selectedGhostIDs.contains(suggestion.id) {
            selectedGhostIDs.remove(suggestion.id)
        } else {
            selectedGhostIDs.insert(suggestion.id)
        }
        
        updateAcceptanceInfo()
    }
}

// MARK: - Ghost Overlay Helpers

private extension EnhancedDayView {
    func startGhostRefresh(force: Bool = false) {
        stopGhostRefresh()
        guard showingRecommendations else { return }
        guard !diagnosticsOverride else { return }
        guard dataManager.appState.preferences.autoRefreshRecommendations else {
            Task { @MainActor in
                await refreshGhosts(force: force)
            }
            return
        }
        refreshTask = Task { @MainActor in
            let initialReason = dataManager.consumePendingMicroUpdate()
            await refreshGhosts(force: force, reason: initialReason)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ghostRefreshInterval)
                let reason = dataManager.consumePendingMicroUpdate()
                await refreshGhosts(reason: reason)
            }
        }
    }
    
    func stopGhostRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    @MainActor
    func refreshGhosts(force: Bool = false, reason: MicroUpdateReason? = nil) async {
        guard showingRecommendations else { return }
        guard !diagnosticsOverride else { return }
        let rawSuggestions = await generateGhostSuggestions(for: selectedDate, reason: reason, forceLLM: force)
        var placedSuggestions = dataManager.prioritizeSuggestions(rawSuggestions)
        assignTimes(to: &placedSuggestions, for: selectedDate)
        placedSuggestions = normalizeSuggestions(placedSuggestions)
        placedSuggestions.sort { $0.suggestedTime < $1.suggestedTime }
        if force || shouldUpdateGhosts(current: ghostSuggestions, new: placedSuggestions) {
            if reduceMotion {
                ghostSuggestions = placedSuggestions
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    ghostSuggestions = placedSuggestions
                }
            }
            let validIDs = Set(placedSuggestions.map(\.id))
            selectedGhostIDs = selectedGhostIDs.intersection(validIDs)
            updateAcceptanceInfo()
        }
        if let reason { dataManager.consumeMicroUpdate(reason: reason) }
    }

    @MainActor
    func generateGhostSuggestions(for date: Date, reason: MicroUpdateReason?, forceLLM: Bool) async -> [Suggestion] {
        let gaps = computeGaps(for: date)
        let availableTime = gaps.reduce(0) { $0 + $1.duration }
        let guidance = dataManager.appState.pillars
            .map { $0.aiGuidanceText }
            .filter { !$0.isEmpty }
        let context = DayContext(
            date: date,
            existingBlocks: dataManager.appState.currentDay.blocks,
            currentEnergy: .daylight,
            preferredEmojis: ["🌊"],
            availableTime: availableTime,
            mood: dataManager.appState.currentDay.mood,
            weatherContext: dataManager.weatherService.getWeatherContext(),
            pillarGuidance: guidance
        )
        let base = await dataManager.produceSuggestions(context: context, reason: reason, forceLLM: forceLLM, aiService: aiService)
        return dataManager.resolveMetadata(for: base)
    }
    
    func assignTimes(to suggestions: inout [Suggestion], for date: Date) {
        var gaps = computeGaps(for: date)
        guard !gaps.isEmpty else {
            suggestions.removeAll()
            return
        }

        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let now = Date()
        let minimumDuration: TimeInterval = 600
        var placed: [Suggestion] = []

        for var suggestion in suggestions {
            guard let placement = placeSuggestion(
                suggestion,
                into: &gaps,
                isToday: isToday,
                now: now,
                minimumDuration: minimumDuration,
                placed: placed
            ) else {
                continue
            }

            suggestion.suggestedTime = placement.start
            suggestion.duration = placement.duration
            placed.append(suggestion)
        }

        suggestions = placed.sorted { $0.suggestedTime < $1.suggestedTime }
    }

    func placeSuggestion(
        _ suggestion: Suggestion,
        into gaps: inout [TimeGap],
        isToday: Bool,
        now: Date,
        minimumDuration: TimeInterval,
        placed: [Suggestion]
    ) -> (start: Date, duration: TimeInterval)? {
        let index = 0
        while index < gaps.count {
            var gap = gaps[index]
            let adjustedStart = isToday ? max(gap.start, now) : gap.start
            let gapDuration = gap.end.timeIntervalSince(adjustedStart)

            if gapDuration < minimumDuration {
                gaps.remove(at: index)
                continue
            }

            var startTime = snapUpToNearestFiveMinutes(adjustedStart)
            if startTime < adjustedStart {
                startTime = adjustedStart
            }

            if startTime >= gap.end {
                gaps.remove(at: index)
                continue
            }

            let available = gap.end.timeIntervalSince(startTime)
            if available < minimumDuration {
                gaps.remove(at: index)
                continue
            }

            let desiredDuration = max(minimumDuration, suggestion.duration)
            let buffer: TimeInterval = available >= desiredDuration + 120 ? 120 : 0
            let finalDuration = min(desiredDuration, available - buffer)

            if finalDuration < minimumDuration {
                gaps.remove(at: index)
                continue
            }

            let endTime = startTime.addingTimeInterval(finalDuration)

            if let conflict = placed.first(where: { existing in
                let existingEnd = existing.suggestedTime.addingTimeInterval(existing.duration)
                return startTime < existingEnd && endTime > existing.suggestedTime
            }) {
                let conflictEnd = conflict.suggestedTime.addingTimeInterval(conflict.duration)
                let snapped = snapUpToNearestFiveMinutes(conflictEnd)
                if snapped >= gap.end - minimumDuration {
                    gaps.remove(at: index)
                } else {
                    gap.start = max(snapped, adjustedStart)
                    gaps[index] = gap
                }
                continue
            }

            let consumptionEnd = endTime.addingTimeInterval(buffer)
            if consumptionEnd < gap.end - minimumDuration {
                gap.start = consumptionEnd
                gaps[index] = gap
            } else {
                gaps.remove(at: index)
            }

            return (startTime, finalDuration)
        }

        return nil
    }
    
    func computeGaps(for date: Date) -> [TimeGap] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let now = Date()
        let lowerBound = calendar.isDate(date, inSameDayAs: now) ? max(dayStart, now) : dayStart
        var gaps: [TimeGap] = []
        var cursor = lowerBound
        for block in allBlocksForDay {
            let blockStart = max(block.startTime, dayStart)
            if blockStart > cursor + 600 {
                let gapEnd = min(blockStart, dayEnd)
                gaps.append(TimeGap(start: cursor, end: gapEnd))
            }
            let blockEnd = min(block.endTime, dayEnd)
            cursor = max(cursor, blockEnd)
            if cursor >= dayEnd { break }
        }
        if dayEnd > cursor + 600 {
            gaps.append(TimeGap(start: cursor, end: dayEnd))
        }
        return subtractQuietHours(from: gaps, on: date)
    }

    func snapUpToNearestFiveMinutes(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 5
        let delta = remainder == 0 ? 0 : 5 - remainder
        return calendar.date(byAdding: .minute, value: delta, to: date) ?? date
    }
    
    func normalizeSuggestions(_ suggestions: [Suggestion]) -> [Suggestion] {
        let existingMap = Dictionary(uniqueKeysWithValues: ghostSuggestions.map { (fingerprint(for: $0), $0.id) })
        return suggestions.map { suggestion in
            let key = fingerprint(for: suggestion)
            if let existingID = existingMap[key] {
                return Suggestion(
                    id: existingID,
                    title: suggestion.title,
                    duration: suggestion.duration,
                    suggestedTime: suggestion.suggestedTime,
                    energy: suggestion.energy,
                    emoji: suggestion.emoji,
                    explanation: suggestion.explanation,
                    confidence: suggestion.confidence,
                    weight: suggestion.weight,
                    relatedGoalId: suggestion.relatedGoalId,
                    relatedGoalTitle: suggestion.relatedGoalTitle,
                    relatedPillarId: suggestion.relatedPillarId,
                    relatedPillarTitle: suggestion.relatedPillarTitle,
                    reason: suggestion.reason
                )
            }
            return suggestion
        }
    }
    
    func fingerprint(for suggestion: Suggestion) -> String {
        let startKey = Int(suggestion.suggestedTime.timeIntervalSinceReferenceDate)
        return "\(suggestion.title.lowercased())|\(Int(suggestion.duration))|\(suggestion.energy.rawValue)|\(startKey)"
    }
    
    func shouldUpdateGhosts(current: [Suggestion], new: [Suggestion]) -> Bool {
        guard current.count == new.count else { return true }
        for (lhs, rhs) in zip(current, new) {
            if fingerprint(for: lhs) != fingerprint(for: rhs) {
                return true
            }
        }
        return false
    }

    private func subtractQuietHours(from gaps: [TimeGap], on date: Date) -> [TimeGap] {
        let quietIntervals = quietTimeIntervals(for: date)
        guard !quietIntervals.isEmpty else { return gaps }

        var adjustedGaps = gaps
        for quiet in quietIntervals {
            var next: [TimeGap] = []
            for gap in adjustedGaps {
                if quiet.end <= gap.start || quiet.start >= gap.end {
                    next.append(gap)
                    continue
                }

                if quiet.start > gap.start {
                    next.append(TimeGap(start: gap.start, end: quiet.start))
                }
                if quiet.end < gap.end {
                    next.append(TimeGap(start: quiet.end, end: gap.end))
                }
            }
            adjustedGaps = next
            if adjustedGaps.isEmpty { break }
        }

        return adjustedGaps
            .filter { $0.duration >= 600 }
            .sorted { $0.start < $1.start }
    }

    private func quietTimeIntervals(for date: Date) -> [TimeGap] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)

        let rawIntervals: [TimeGap] = dataManager.appState.pillars.flatMap { pillar in
            pillar.quietHours.compactMap { window -> TimeGap? in
                guard
                    let start = calendar.date(bySettingHour: window.startHour, minute: window.startMinute, second: 0, of: dayStart),
                    let end = calendar.date(bySettingHour: window.endHour, minute: window.endMinute, second: 0, of: dayStart),
                    end > start
                else {
                    return nil
                }
                let clampedStart = max(start, dayStart)
                let clampedEnd = min(end, dayEnd)
                guard clampedEnd > clampedStart else { return nil }
                return TimeGap(start: clampedStart, end: clampedEnd)
            }
        }

        return mergeIntervals(rawIntervals)
    }

    private func mergeIntervals(_ intervals: [TimeGap]) -> [TimeGap] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [TimeGap] = []

        for interval in sorted {
            if merged.isEmpty {
                merged.append(interval)
                continue
            }

            if interval.start <= merged[merged.count - 1].end {
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, interval.end)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }
    
    func acceptAllGhosts() {
        acceptGhosts(ghostSuggestions)
    }
    
    func acceptSelectedGhosts() {
        let selected = ghostSuggestions.filter { selectedGhostIDs.contains($0.id) }
        if selected.isEmpty {
            acceptAllGhosts()
        } else {
            acceptGhosts(selected)
        }
    }
    
    func acceptGhosts(_ suggestionsToAccept: [Suggestion]) {
        guard !suggestionsToAccept.isEmpty else { return }
        let acceptedIDs = Set(suggestionsToAccept.map(\.id))
        for suggestion in suggestionsToAccept {
            dataManager.applySuggestion(suggestion)
        }
        let removal = {
            ghostSuggestions.removeAll { acceptedIDs.contains($0.id) }
        }
        if reduceMotion {
            removal()
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                removal()
            }
        }
        selectedGhostIDs.subtract(acceptedIDs)
        
        updateAcceptanceInfo()
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshGhosts(force: true, reason: .acceptedSuggestion)
        }
    }
    
    struct TimeGap {
        var start: Date
        var end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }
}

// MARK: - Hour With Events (Simplified Layout)

struct HourWithEvents: View {
    let hour: Int
    let selectedDate: Date
    let blocks: [TimeBlock]
    let draggedBlock: TimeBlock?
    let onTap: (Date) -> Void
    let onBlockDrag: (TimeBlock, CGPoint) -> Void
    let onBlockDrop: (TimeBlock, Date) -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var isHovering = false
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Events for this hour
            ForEach(blocks) { block in
                CleanEventCard(
                    block: block,
                    onDrag: { location in
                        onBlockDrag(block, location)
                    },
                    onDrop: { newTime in
                        onBlockDrop(block, newTime)
                    }
                )
            }
            
            // Empty space for creating new blocks
            if blocks.isEmpty {
                Rectangle()
                    .fill(.clear)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHovering ? .blue.opacity(0.05) : hourBackgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        isHovering ? .blue.opacity(0.3) : .clear,
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                                    )
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let hourTime = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                        onTap(hourTime)
                    }
                    .onHover { hovering in
                        isHovering = hovering
                    }
            }
            
            // Hour separator line
            if hour < 23 {
                Rectangle()
                    .fill(.quaternary.opacity(0.2))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 60) // Minimum hour height
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var hourBackgroundColor: Color {
        AstronomicalTimeCalculator.shared.getTimeColor(for: hour, date: selectedDate)
    }
}

// MARK: - Enhanced Hour Slot

struct EnhancedHourSlot: View {
    let hour: Int
    let selectedDate: Date
    let blocks: [TimeBlock]
    let onTap: (Date) -> Void
    let onBlockDrag: (TimeBlock, CGPoint) -> Void
    let onBlockDrop: (TimeBlock, Date) -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var isHovering = false
    
    private var hourTime: Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        return calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: hourTime)
    }
    
    private var isCurrentHour: Bool {
        Calendar.current.component(.hour, from: Date()) == hour &&
        Calendar.current.isDate(selectedDate, inSameDayAs: Date())
    }
    
    private var isCurrentMinute: Bool {
        let now = Date()
        let currentHour = Calendar.current.component(.hour, from: now)
        return currentHour == hour && Calendar.current.isDate(selectedDate, inSameDayAs: now)
    }
    
    private var currentTimeOffset: CGFloat {
        guard isCurrentMinute else { return 0 }
        let now = Date()
        let minute = Calendar.current.component(.minute, from: now)
        return CGFloat(minute) * 0.8 // Rough positioning within hour slot
    }
    
    private var dayNightBackground: Color {
        AstronomicalTimeCalculator.shared.getTimeColor(for: hour, date: selectedDate)
    }
    
    private var timeLabel: String {
        switch hour {
        case 6: return "🌅 \(timeString)"
        case 18: return "🌅 \(timeString)"
        case 0: return "🌙 \(timeString)"
        default: return timeString
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time label with enhanced styling and day/night indicators
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(isCurrentHour ? .blue : .primary)
                
                if isCurrentHour {
                    Circle()
                        .fill(.blue)
                        .frame(width: 4, height: 4)
                        .overlay(
                            Circle()
                                .stroke(.blue, lineWidth: 1)
                                .scaleEffect(1.5)
                                .opacity(0.3)
                        )
                }
            }
            .frame(width: 60, alignment: .trailing)
            
            // Hour content area
            VStack(alignment: .leading, spacing: 4) {
                ForEach(blocks) { block in
                    EnhancedTimeBlockCard(
                        block: block,
                        onTap: { },
                        onDrag: { location in
                            onBlockDrag(block, location)
                        },
                        onDrop: { newTime in
                            onBlockDrop(block, newTime)
                        },
                        allBlocks: blocksForCurrentDay()
                    )
                }
                
                // Empty space for creating new blocks
                if blocks.isEmpty {
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isHovering ? .blue.opacity(0.05) : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            isHovering ? .blue.opacity(0.3) : .clear,
                                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                                        )
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTap(hourTime)
                        }
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isHovering = hovering
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                // Current time line indicator
                isCurrentMinute ?
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(.blue)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .opacity(0.8)
                        
                        Text("now")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .opacity(0.9)
                    }
                    .offset(y: currentTimeOffset - 20)
                    : nil,
                alignment: .topLeading
            )
        }
        .padding(.vertical, 4)
        .background(
            Group {
                if isCurrentHour {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.blue.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(dayNightBackground)
                }
            }
        )
    }
    
    private func blocksForCurrentDay() -> [TimeBlock] {
        // Return all blocks for the current day for gap checking
        return dataManager.appState.currentDay.blocks
    }
}
