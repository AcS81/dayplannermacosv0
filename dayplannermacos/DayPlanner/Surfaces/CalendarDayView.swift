//
//  CalendarDayView.swift
//  DayPlanner
//
//  Redesigned day view with proper time slots, drag & drop, and chain integration
//

import SwiftUI

// MARK: - Main Calendar Day View

/// A proper calendar-style day view with aligned time slots, drag & drop, and infinite day scrolling
struct CalendarDayView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var visibleDates: [Date] = []
    @State private var draggedBlock: TimeBlock?
    @State private var dragOffset: CGSize = .zero
    @State private var showingBlockCreation = false
    @State private var creationTime: Date?
    @State private var headerDirection: ScrollDirection = .none
    @State private var pendingScrollTarget: Date?
    @State private var hasInitializedScroll = false

    // Constants for layout calculations
    private let hourHeight: CGFloat = 80
    private let pixelsPerMinute: CGFloat = 80 / 60 // 80px per hour = ~1.33px per minute
    private let sidebarWidth: CGFloat = 70
    private let maxVisibleDays: Int = 9
    private let calendar = Calendar.current

    private static let dayIdentifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private var dayHeight: CGFloat { hourHeight * 24 }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                AnimatedDateHeader(date: selectedDate, direction: headerDirection)
                    .padding(.horizontal)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleDates, id: \.self) { date in
                                let dayId = dayIdentifier(for: date)
                                DayTimelineSection(
                                    date: date,
                                    idPrefix: dayId,
                                    blocks: blocks(for: date),
                                    hourHeight: hourHeight,
                                    pixelsPerMinute: pixelsPerMinute,
                                    sidebarWidth: sidebarWidth,
                                    containerWidth: geometry.size.width - sidebarWidth,
                                    draggedBlock: $draggedBlock,
                                    dragOffset: dragOffset,
                                    onEventTap: handleEventTap,
                                    onEventDrag: handleEventDrag,
                                    onEventDrop: handleEventDrop,
                                    onEventResize: handleEventResize,
                                    onTimelineTap: handleTimelineClick
                                )
                                .frame(height: dayHeight)
                                .id(dayId)
                                .background(
                                    GeometryReader { sectionGeometry in
                                        Color.clear.preference(
                                            key: DayPositionPreferenceKey.self,
                                            value: [calendar.startOfDay(for: date): sectionGeometry.frame(in: .named("timelineScroll")).minY]
                                        )
                                    }
                                )
                                .onAppear {
                                    handleDayAppear(date)
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "timelineScroll")
                    .scrollDisabled(draggedBlock != nil)
                    .onPreferenceChange(DayPositionPreferenceKey.self) { positions in
                        updateSelectedDateIfNeeded(positions: positions, containerHeight: geometry.size.height)
                    }
                    .onChange(of: visibleDates) { _ in
                        guard let pendingScrollTarget else { return }
                        if visibleDates.contains(where: { calendar.isDate($0, inSameDayAs: pendingScrollTarget) }) {
                            DispatchQueue.main.async {
                                scrollToDate(pendingScrollTarget, proxy: proxy, animated: hasInitializedScroll)
                                hasInitializedScroll = true
                                self.pendingScrollTarget = nil
                            }
                        }
                    }
                    .onChange(of: selectedDate) { _, newValue in
                        dataManager.switchToDay(newValue)
                        guard let pendingScrollTarget else { return }
                        if visibleDates.contains(where: { calendar.isDate($0, inSameDayAs: pendingScrollTarget) }) {
                            DispatchQueue.main.async {
                                scrollToDate(pendingScrollTarget, proxy: proxy, animated: hasInitializedScroll)
                                hasInitializedScroll = true
                                self.pendingScrollTarget = nil
                            }
                        } else {
                            ensureDatesInclude(pendingScrollTarget)
                        }
                    }
                    .onAppear {
                        if visibleDates.isEmpty {
                            let initial = calendar.startOfDay(for: dataManager.appState.currentDay.date)
                            selectedDate = initial
                            initializeVisibleDates(centeredOn: initial)
                            pendingScrollTarget = initial
                            dataManager.switchToDay(initial)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DatePicker(
                    "Select Date",
                    selection: Binding(
                        get: { selectedDate },
                        set: { newValue in
                            selectDate(newValue, shouldScroll: true)
                        }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
            }
        }
        .sheet(isPresented: $showingBlockCreation) {
            if let creationTime {
                EventCreationSheet(
                    startTime: creationTime,
                    onSave: { block in
                        dataManager.addTimeBlock(block)
                        showingBlockCreation = false
                    },
                    onCancel: {
                        showingBlockCreation = false
                    }
                )
            }
        }
    }

    // MARK: - Event Handlers

    private func handleEventTap(_ block: TimeBlock) {
        // Handle event tap - could show details or quick actions
        print("Tapped event: \(block.title)")
    }

    private func handleEventDrag(_ block: TimeBlock, dragValue: DragGesture.Value) {
        draggedBlock = block
        dragOffset = dragValue.translation
    }

    private func handleEventDrop(_ block: TimeBlock, newStartTime: Date) {
        var updatedBlock = block
        updatedBlock.startTime = newStartTime
        updatedBlock.glassState = .solid

        dataManager.updateTimeBlock(updatedBlock)

        // Clear drag state
        draggedBlock = nil
        dragOffset = .zero

        dataManager.save()
    }

    private func handleEventResize(_ block: TimeBlock, newDuration: TimeInterval) {
        var updatedBlock = block
        updatedBlock.duration = max(15 * 60, newDuration) // Minimum 15 minutes
        dataManager.updateTimeBlock(updatedBlock)
    }

    private func handleTimelineClick(for date: Date, location: CGPoint) {
        guard draggedBlock == nil else { return }

        if !calendar.isDate(date, inSameDayAs: selectedDate) {
            selectDate(date, shouldScroll: false)
        }

        let constrainedY = max(0, min(location.y, dayHeight))
        let hour = max(0, min(23, Int(constrainedY / hourHeight)))
        let minute = Int((constrainedY.truncatingRemainder(dividingBy: hourHeight)) / pixelsPerMinute)

        let normalizedDate = calendar.startOfDay(for: date)
        if let newTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: normalizedDate) {
            creationTime = newTime
            showingBlockCreation = true
        }
    }

    // MARK: - Timeline Management

    private func initializeVisibleDates(centeredOn date: Date) {
        visibleDates = generateDates(around: date, radius: 3)
    }

    private func generateDates(around date: Date, radius: Int) -> [Date] {
        let normalized = calendar.startOfDay(for: date)
        return (-radius...radius).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: normalized)
        }
    }

    private func ensureDatesInclude(_ date: Date) {
        if !visibleDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            visibleDates = generateDates(around: date, radius: 3)
        }
    }

    private func handleDayAppear(_ date: Date) {
        guard let index = visibleDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) else { return }

        if index == 0, let previous = calendar.date(byAdding: .day, value: -1, to: date) {
            prependDay(previous)
        }

        if index == visibleDates.count - 1, let next = calendar.date(byAdding: .day, value: 1, to: date) {
            appendDay(next)
        }
    }

    private func prependDay(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        guard !visibleDates.contains(where: { calendar.isDate($0, inSameDayAs: normalized) }) else { return }
        visibleDates.insert(normalized, at: 0)
        trimVisibleDatesIfNeeded()
    }

    private func appendDay(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        guard !visibleDates.contains(where: { calendar.isDate($0, inSameDayAs: normalized) }) else { return }
        visibleDates.append(normalized)
        trimVisibleDatesIfNeeded()
    }

    private func trimVisibleDatesIfNeeded() {
        while visibleDates.count > maxVisibleDays {
            guard let first = visibleDates.first, let last = visibleDates.last else { break }
            let firstDistance = abs(first.timeIntervalSince(selectedDate))
            let lastDistance = abs(last.timeIntervalSince(selectedDate))
            if firstDistance > lastDistance {
                visibleDates.removeFirst()
            } else {
                visibleDates.removeLast()
            }
        }
    }

    private func updateSelectedDateIfNeeded(positions: [Date: CGFloat], containerHeight: CGFloat) {
        guard !positions.isEmpty else { return }
        let threshold = containerHeight / 3

        for (date, minY) in positions {
            let lowerBound = minY
            let upperBound = minY + dayHeight
            if threshold >= lowerBound && threshold < upperBound {
                selectDate(date, shouldScroll: false)
                break
            }
        }
    }

    private func selectDate(_ date: Date, shouldScroll: Bool) {
        let normalized = calendar.startOfDay(for: date)
        guard normalized != selectedDate else { return }

        headerDirection = normalized > selectedDate ? .forward : .backward

        if shouldScroll {
            pendingScrollTarget = normalized
        } else {
            pendingScrollTarget = nil
        }

        selectedDate = normalized
    }

    private func scrollToDate(_ date: Date, proxy: ScrollViewProxy, animated: Bool) {
        let normalized = calendar.startOfDay(for: date)
        let hour = calendar.isDateInToday(normalized) ? calendar.component(.hour, from: Date()) : 8
        let anchorY: CGFloat = calendar.isDateInToday(normalized) ? 0.33 : 0.0
        let targetId = hourIdentifier(for: normalized, hour: hour)

        let scrollAction = {
            proxy.scrollTo(targetId, anchor: UnitPoint(x: 0.5, y: anchorY))
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                scrollAction()
            }
        } else {
            scrollAction()
        }
    }

    private func blocks(for date: Date) -> [TimeBlock] {
        let normalized = calendar.startOfDay(for: date)
        if calendar.isDate(normalized, inSameDayAs: dataManager.appState.currentDay.date) {
            return dataManager.appState.currentDay.blocks.sorted { $0.startTime < $1.startTime }
        }

        if let historicalDay = dataManager.appState.historicalDays.first(where: { calendar.isDate($0.date, inSameDayAs: normalized) }) {
            return historicalDay.blocks.sorted { $0.startTime < $1.startTime }
        }

        return []
    }

    private func dayIdentifier(for date: Date) -> String {
        Self.dayIdentifierFormatter.string(from: calendar.startOfDay(for: date))
    }

    private func hourIdentifier(for date: Date, hour: Int) -> String {
        "\(dayIdentifier(for: date))-hour-\(hour)"
    }
}

// MARK: - Animated Header & Section Views

private struct AnimatedDateHeader: View {
    let date: Date
    let direction: ScrollDirection

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    var body: some View {
        ZStack {
            Text(Self.formatter.string(from: date))
                .font(.title2.weight(.semibold))
                .id(date)
                .transition(transition)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.3), value: date)
    }

    private var transition: AnyTransition {
        switch direction {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .none:
            return .opacity
        }
    }
}

private struct DayTimelineSection: View {
    let date: Date
    let idPrefix: String
    let blocks: [TimeBlock]
    let hourHeight: CGFloat
    let pixelsPerMinute: CGFloat
    let sidebarWidth: CGFloat
    let containerWidth: CGFloat
    @Binding var draggedBlock: TimeBlock?
    let dragOffset: CGSize
    let onEventTap: (TimeBlock) -> Void
    let onEventDrag: (TimeBlock, DragGesture.Value) -> Void
    let onEventDrop: (TimeBlock, Date) -> Void
    let onEventResize: (TimeBlock, TimeInterval) -> Void
    let onTimelineTap: (Date, CGPoint) -> Void

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            TimeSidebar(hourHeight: hourHeight, date: date, idPrefix: idPrefix)
                .frame(width: sidebarWidth)

            ZStack(alignment: .topLeading) {
                TimelineGrid(
                    hourHeight: hourHeight,
                    width: containerWidth
                )

                EventsOverlay(
                    blocks: blocks,
                    hourHeight: hourHeight,
                    pixelsPerMinute: pixelsPerMinute,
                    containerWidth: containerWidth,
                    selectedDate: date,
                    onEventTap: onEventTap,
                    onEventDrag: onEventDrag,
                    onEventDrop: onEventDrop,
                    onEventResize: onEventResize,
                    draggedBlock: $draggedBlock
                )

                if let draggedBlock,
                   calendar.isDate(draggedBlock.startTime, inSameDayAs: date) {
                    DragIndicatorLine(
                        draggedBlock: draggedBlock,
                        dragOffset: dragOffset,
                        hourHeight: hourHeight,
                        pixelsPerMinute: pixelsPerMinute,
                        containerWidth: containerWidth
                    )
                }
            }
            .frame(height: hourHeight * 24)
            .contentShape(Rectangle())
            .onTapGesture { location in
                onTimelineTap(date, location)
            }
        }
    }
}

private struct DayPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]

    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private enum ScrollDirection {
    case none, forward, backward
}

// MARK: - Time Sidebar

struct TimeSidebar: View {
    let hourHeight: CGFloat
    let date: Date
    let idPrefix: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                VStack(spacing: 2) {
                    Text(formatHour(hour))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isCurrentHour(hour) ? .blue : .secondary)

                    if hour < 23 {
                        Spacer()
                            .frame(height: hourHeight - 20)
                    }
                }
                .frame(height: hourHeight, alignment: .top)
                .id("\(idPrefix)-hour-\(hour)")
            }
        }
        .padding(.top, 10)
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let referenceDate = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        return formatter.string(from: referenceDate)
    }

    private func isCurrentHour(_ hour: Int) -> Bool {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let isToday = Calendar.current.isDateInToday(date)
        return isToday && hour == currentHour
    }
}

// MARK: - Timeline Grid

struct TimelineGrid: View {
    let hourHeight: CGFloat
    let width: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Rectangle()
                    .frame(width: width, height: 1)
                    .foregroundColor(hour == 0 || hour == 12 ? .primary.opacity(0.3) : .secondary.opacity(0.2))
                
                if hour < 23 {
                    Spacer()
                        .frame(height: hourHeight - 1)
                }
            }
        }
    }
}

// MARK: - Events Overlay

struct EventsOverlay: View {
    let blocks: [TimeBlock]
    let hourHeight: CGFloat
    let pixelsPerMinute: CGFloat
    let containerWidth: CGFloat
    let selectedDate: Date
    let onEventTap: (TimeBlock) -> Void
    let onEventDrag: (TimeBlock, DragGesture.Value) -> Void
    let onEventDrop: (TimeBlock, Date) -> Void
    let onEventResize: (TimeBlock, TimeInterval) -> Void
    @Binding var draggedBlock: TimeBlock?
    
    var body: some View {
        ForEach(blocks) { block in
            EventCard(
                block: block,
                hourHeight: hourHeight,
                pixelsPerMinute: pixelsPerMinute,
                containerWidth: containerWidth,
                selectedDate: selectedDate,
                isDragged: draggedBlock?.id == block.id,
                onTap: { onEventTap(block) },
                onDragChanged: { dragValue in
                    onEventDrag(block, dragValue)
                },
                onDragEnded: { dragValue in
                    let minutesChanged = dragValue.translation.height / pixelsPerMinute
                    let newStartTime = block.startTime.addingTimeInterval(TimeInterval(minutesChanged * 60))
                    onEventDrop(block, newStartTime)
                },
                onResize: { newDuration in
                    onEventResize(block, newDuration)
                }
            )
        }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let block: TimeBlock
    let hourHeight: CGFloat
    let pixelsPerMinute: CGFloat
    let containerWidth: CGFloat
    let selectedDate: Date
    let isDragged: Bool
    let onTap: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onResize: (TimeInterval) -> Void
    
    @State private var isHovering = false
    @State private var dragOffset: CGSize = .zero
    @State private var isResizing = false
    @EnvironmentObject private var dataManager: AppDataManager
    
    var body: some View {
        let position = calculatePosition()
        let eventHeight = calculateHeight()
        
        VStack(alignment: .leading, spacing: 0) {
            // Main event content
            HStack(spacing: 8) {
                // Energy indicator
                Rectangle()
                    .fill(block.energy.color)
                    .frame(width: 4)
                    .cornerRadius(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Title with AI enhancement
                    Text(block.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    // Time and duration info
                    HStack {
                        Text(timeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(block.durationMinutes)m")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(block.energy.color)
                    }
                    
                    // AI description (show when expanded or hovering)
                    if isHovering || eventHeight > 60 {
                        Text(generateAIDescription())
                            .font(.caption2)
                            .italic()
                            .foregroundColor(block.energy.color.opacity(0.8))
                            .lineLimit(2)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                
                Spacer()
                
                // Chain buttons (show when hovering and there's space)
                if isHovering && eventHeight > 40 {
                    VStack(spacing: 2) {
                        if hasSpaceBefore {
                            ChainButton(direction: .before, onTap: {
                                addChainBefore()
                            })
                        }
                        
                        if hasSpaceAfter {
                            ChainButton(direction: .after, onTap: {
                                addChainAfter()
                            })
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            // Resize handle at bottom
            if isHovering && !isResizing {
                ResizeHandle(onDrag: { dragValue in
                    isResizing = true
                    let newHeight = eventHeight + dragValue.height
                    let newDuration = TimeInterval((newHeight / pixelsPerMinute) * 60)
                    onResize(newDuration)
                })
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: containerWidth - 16, height: eventHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(eventBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isDragged ? .blue.opacity(0.8) : block.energy.color.opacity(0.3),
                            lineWidth: isDragged ? 2 : 1
                        )
                )
        )
        .scaleEffect(isDragged ? 0.95 : (isHovering ? 1.02 : 1.0))
        .shadow(
            color: .black.opacity(isDragged ? 0.2 : (isHovering ? 0.1 : 0.05)),
            radius: isDragged ? 8 : (isHovering ? 4 : 2),
            y: isDragged ? 4 : (isHovering ? 2 : 1)
        )
        .offset(x: position.x, y: position.y)
        .offset(dragOffset)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isResizing {
                        dragOffset = CGSize(width: 0, height: value.translation.height)
                        onDragChanged(value)
                    }
                }
                .onEnded { value in
                    if !isResizing {
                        dragOffset = .zero
                        onDragEnded(value)
                    }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragged)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
    
    // MARK: - Computed Properties
    
    private func calculatePosition() -> CGPoint {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let minutesSinceStartOfDay = block.startTime.timeIntervalSince(startOfDay) / 60
        let yPosition = CGFloat(minutesSinceStartOfDay) * pixelsPerMinute
        return CGPoint(x: 8, y: yPosition)
    }
    
    private func calculateHeight() -> CGFloat {
        return max(30, CGFloat(block.duration / 60) * pixelsPerMinute)
    }
    
    private var eventBackgroundColor: Color {
        switch block.glassState {
        case .solid:
            return .white.opacity(0.9)
        case .liquid:
            return .blue.opacity(0.1)
        case .mist:
            return .gray.opacity(0.1)
        case .crystal:
            return .cyan.opacity(0.1)
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: block.startTime)
    }
    
    private var hasSpaceBefore: Bool {
        // Check if there's free time before this event
        let tenMinutesBefore = block.startTime.addingTimeInterval(-10 * 60)
        return !dataManager.appState.currentDay.blocks.contains { otherBlock in
            otherBlock.id != block.id && 
            otherBlock.startTime <= tenMinutesBefore && 
            otherBlock.endTime > tenMinutesBefore
        }
    }
    
    private var hasSpaceAfter: Bool {
        // Check if there's free time after this event
        let tenMinutesAfter = block.endTime.addingTimeInterval(10 * 60)
        return !dataManager.appState.currentDay.blocks.contains { otherBlock in
            otherBlock.id != block.id && 
            otherBlock.startTime < tenMinutesAfter && 
            otherBlock.endTime >= tenMinutesAfter
        }
    }
    
    private func generateAIDescription() -> String {
        let flowEmoji = block.emoji
        let energyDesc = block.energy.description.lowercased()
        let timeContext = getTimeContext(for: block.startTime)
        
        let descriptions = [
            "\(flowEmoji) Perfect \(timeContext) activity for \(energyDesc) energy",
            "\(flowEmoji) Designed for your \(energyDesc) \(timeContext) state",
            "\(flowEmoji) Optimized for \(timeContext) \(energyDesc) focus",
            "\(flowEmoji) AI-placed for peak \(energyDesc) performance"
        ]
        
        return descriptions.randomElement() ?? "AI-optimized timing"
    }
    
    private func getTimeContext(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 6..<9: return "morning"
        case 9..<12: return "mid-morning"
        case 12..<14: return "midday"
        case 14..<17: return "afternoon"
        case 17..<20: return "evening"
        default: return "quiet"
        }
    }
    
    private func addChainBefore() {
        // Create a chain before this event
        let chainStartTime = block.startTime.addingTimeInterval(-30 * 60) // 30 min before
        showChainSuggestions(at: chainStartTime, direction: .before)
    }
    
    private func addChainAfter() {
        // Create a chain after this event
        let chainStartTime = block.endTime.addingTimeInterval(5 * 60) // 5 min after
        showChainSuggestions(at: chainStartTime, direction: .after)
    }
    
    private func showChainSuggestions(at time: Date, direction: ChainDirection) {
        // Get relevant chains from the data manager
        let availableChains = dataManager.appState.recentChains.filter { $0.isActive && !$0.blocks.isEmpty }
        
        if !availableChains.isEmpty {
            // For now, apply the first suitable chain
            let chain = availableChains.first!
            dataManager.applyChain(chain, startingAt: time)
        } else {
            // Create a default productivity chain
            createDefaultChain(at: time, direction: direction)
        }
    }
    
    private func createDefaultChain(at time: Date, direction: ChainDirection) {
        _ = direction == .before ? "Prep for \(block.title)" : "Follow-up to \(block.title)"
        
        let prepBlock = TimeBlock(
            title: direction == .before ? "Prepare" : "Wrap up",
            startTime: time,
            duration: 15 * 60, // 15 minutes
            energy: block.energy,
            emoji: block.emoji,
            glassState: .solid
        )
        
        dataManager.addTimeBlock(prepBlock)
    }
}

// MARK: - Chain Button

enum ChainDirection {
    case before, after
}

struct ChainButton: View {
    let direction: ChainDirection
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Image(systemName: direction == .before ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                )
        }
        .buttonStyle(.plain)
        .help(direction == .before ? "Add chain before" : "Add chain after")
    }
}

// MARK: - Drag Indicator Line

struct DragIndicatorLine: View {
    let draggedBlock: TimeBlock
    let dragOffset: CGSize
    let hourHeight: CGFloat
    let pixelsPerMinute: CGFloat
    let containerWidth: CGFloat
    
    var body: some View {
        let startOfDay = Calendar.current.startOfDay(for: draggedBlock.startTime)
        let originalY = CGFloat(draggedBlock.startTime.timeIntervalSince(startOfDay) / 60) * pixelsPerMinute
        let newY = originalY + dragOffset.height
        
        Rectangle()
            .fill(.blue.opacity(0.8))
            .frame(width: containerWidth - 16, height: 2)
            .offset(x: 8, y: newY)
        
        // Time indicator
        HStack {
            let newTime = draggedBlock.startTime.addingTimeInterval(TimeInterval(dragOffset.height / pixelsPerMinute * 60))
            Text(timeFormatter.string(from: newTime))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.blue.opacity(0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(.blue.opacity(0.3), lineWidth: 1)
                        )
                )
            Spacer()
        }
        .offset(x: 8, y: newY - 15)
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Event Creation Sheet

struct EventCreationSheet: View {
    let startTime: Date
    let onSave: (TimeBlock) -> Void
    let onCancel: () -> Void
    
    @State private var title = ""
    @State private var duration: TimeInterval = 3600 // 1 hour default
    @State private var energy: EnergyType = .daylight
    @State private var emoji: String = "🎯"
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Event title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    
                    VStack(alignment: .leading) {
                        Text("Duration: \(Int(duration / 60)) minutes")
                            .font(.subheadline)
                        Slider(value: $duration, in: 15*60...4*3600, step: 15*60) // 15 min to 4 hours, 15 min steps
                    }
                }
                
                Section("Energy & Flow") {
                    Picker("Energy Level", selection: $energy) {
                        ForEach(EnergyType.allCases, id: \.self) { energy in
                            HStack {
                                Text(energy.rawValue)
                                Text(energy.description)
                            }.tag(energy)
                        }
                    }
                    
                    // Flow state picker removed - using emoji system instead
                    TextField("Emoji", text: $emoji)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Timing") {
                    LabeledContent("Start Time", value: startTime.formatted(date: .omitted, time: .shortened))
                    LabeledContent("End Time", value: startTime.addingTimeInterval(duration).formatted(date: .omitted, time: .shortened))
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newBlock = TimeBlock(
                            title: title,
                            startTime: startTime,
                            duration: duration,
                            energy: energy,
                            emoji: "🎯",
                            glassState: .crystal
                        )
                        onSave(newBlock)
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Resize Handle (defined in TodayGlass.swift)

// MARK: - Preview

#if DEBUG
struct CalendarDayView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarDayView()
            .environmentObject(AppDataManager.preview)
            .frame(width: 800, height: 600)
    }
}
#endif
