//
//  InfiniteDayScrollView.swift
//  DayPlanner
//
//  Infinite day scrolling with dynamic date buffers and animated date header
//

import SwiftUI

struct InfiniteDayScrollView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    @Binding var selectedDate: Date
    @State private var daySections: [DaySection] = []
    @State private var showingBlockCreation = false
    @State private var creationTime: Date?
    @State private var draggedBlock: TimeBlock?
    @State private var ghostSuggestions: [Suggestion] = []
    @State private var showingRecommendations = true
    @State private var selectedGhostIDs: Set<UUID> = []
    
    // Constants for infinite scrolling
    private let dayHeight: CGFloat = 1440 // 24 hours * 60 minutes
    private let bufferDays: Int = 5 // Days to render before/after current
    private let viewportThreshold: CGFloat = 0.33 // One-third viewport for date selection
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated date header
            AnimatedDateHeader(
                selectedDate: $selectedDate
            )
            
            // Infinite scroll view with day sections
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(daySections, id: \.date) { section in
                            DaySectionView(
                                section: section,
                                selectedDate: $selectedDate,
                                draggedBlock: $draggedBlock,
                                ghostSuggestions: $ghostSuggestions,
                                selectedGhostIDs: $selectedGhostIDs,
                                showingRecommendations: $showingRecommendations,
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
                                }
                            )
                            .id("day-\(section.date.timeIntervalSinceReferenceDate)")
                            .frame(height: dayHeight)
                        }
                    }
                }
                .scrollDisabled(draggedBlock != nil)
                .onAppear {
                    initializeDaySections()
                    scrollToCurrentDay(proxy: proxy)
                }
            }
        }
        .onChange(of: selectedDate) { oldValue, newValue in
            dataManager.switchToDay(newValue)
            updateDaySections(around: newValue)
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
    
    // MARK: - Day Section Management
    
    private func initializeDaySections() {
        let today = Date()
        updateDaySections(around: today)
    }
    
    private func updateDaySections(around date: Date) {
        let calendar = Calendar.current
        var newSections: [DaySection] = []
        
        for i in -bufferDays...bufferDays {
            if let sectionDate = calendar.date(byAdding: .day, value: i, to: date) {
                let blocks = getBlocksForDate(sectionDate)
                let section = DaySection(
                    date: sectionDate,
                    blocks: blocks,
                    isToday: calendar.isDate(sectionDate, inSameDayAs: Date())
                )
                newSections.append(section)
            }
        }
        
        daySections = newSections
    }
    
    private func getBlocksForDate(_ date: Date) -> [TimeBlock] {
        // Get blocks for the specific date
        if Calendar.current.isDate(date, inSameDayAs: dataManager.appState.currentDay.date) {
            return dataManager.appState.currentDay.blocks
        } else {
            // Load from historical data
            return dataManager.appState.historicalDays
                .first { Calendar.current.isDate($0.date, inSameDayAs: date) }?
                .blocks ?? []
        }
    }
    
    
    private func scrollToCurrentDay(proxy: ScrollViewProxy) {
        let today = Date()
        let todayID = "day-\(today.timeIntervalSinceReferenceDate)"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.6)) {
                proxy.scrollTo(todayID, anchor: .center)
            }
        }
    }
    
    private func handleBlockDrop(block: TimeBlock, newTime: Date) {
        var updatedBlock = block
        updatedBlock.startTime = newTime
        dataManager.updateTimeBlock(updatedBlock)
    }
}

// MARK: - Day Section Model

struct DaySection: Identifiable {
    let id = UUID()
    let date: Date
    let blocks: [TimeBlock]
    let isToday: Bool
}

// MARK: - Animated Date Header

struct AnimatedDateHeader: View {
    @Binding var selectedDate: Date
    
    @State private var headerOpacity: Double = 1.0
    @State private var headerScale: CGFloat = 1.0
    
    var body: some View {
        HStack {
            // Previous day button
            Button(action: previousDay) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Animated date display
            VStack(spacing: 2) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(headerOpacity)
                
                Text(selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .scaleEffect(headerScale)
            }
            
            Spacer()
            
            // Next day button
            Button(action: nextDay) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassBackground(.ultraThinMaterial)
    }
    
    private func previousDay() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        }
    }
    
    private func nextDay() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        }
    }
    
}

// MARK: - Day Section View

struct DaySectionView: View {
    let section: DaySection
    @Binding var selectedDate: Date
    @Binding var draggedBlock: TimeBlock?
    @Binding var ghostSuggestions: [Suggestion]
    @Binding var selectedGhostIDs: Set<UUID>
    @Binding var showingRecommendations: Bool
    let onTap: (Date) -> Void
    let onBlockDrag: (TimeBlock, CGPoint) -> Void
    let onBlockDrop: (TimeBlock, Date) -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    
    private let minuteHeight: CGFloat = 1.0 // 1 pixel per minute
    
    var body: some View {
        VStack(spacing: 0) {
            // Day timeline with unique hour anchors
            InfiniteTimelineView(
                date: section.date,
                blocks: section.blocks,
                draggedBlock: draggedBlock,
                minuteHeight: minuteHeight,
                isToday: section.isToday,
                onTap: onTap,
                onBlockDrag: onBlockDrag,
                onBlockDrop: onBlockDrop
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Infinite Timeline View

struct InfiniteTimelineView: View {
    let date: Date
    let blocks: [TimeBlock]
    let draggedBlock: TimeBlock?
    let minuteHeight: CGFloat
    let isToday: Bool
    let onTap: (Date) -> Void
    let onBlockDrag: (TimeBlock, CGPoint) -> Void
    let onBlockDrop: (TimeBlock, Date) -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time sidebar with unique hour anchors
            InfiniteTimeSidebar(
                date: date,
                isToday: isToday
            )
            .frame(width: 80)
            
            // Main timeline canvas
            ZStack(alignment: .topLeading) {
                // Background grid
                InfiniteTimelineCanvas(
                    date: date,
                    isToday: isToday,
                    onTap: onTap
                )
                
                // Events positioned at exact times
                ForEach(blocks) { block in
                    InfiniteEventCard(
                        block: block,
                        date: date,
                        minuteHeight: minuteHeight,
                        isDragged: draggedBlock?.id == block.id,
                        onDrag: { location in
                            onBlockDrag(block, location)
                        },
                        onDrop: { newTime in
                            onBlockDrop(block, newTime)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Infinite Time Sidebar

struct InfiniteTimeSidebar: View {
    let date: Date
    let isToday: Bool
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                VStack(spacing: 0) {
                    // Hour label with unique ID
                    Text(hourLabel(for: hour))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(isCurrentHour(hour) ? .blue : .primary)
                        .frame(height: 15, alignment: .bottom)
                    
                    // Quarter hour markers
                    VStack(spacing: 0) {
                        ForEach([15, 30, 45], id: \.self) { minute in
                            HStack {
                                Spacer()
                                Text(":\(minute)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(height: 15)
                        }
                    }
                }
                .frame(height: 60) // 60 pixels per hour
                .id("hour-\(date.timeIntervalSinceReferenceDate)-\(hour)") // Unique ID
            }
        }
    }
    
    private func hourLabel(for hour: Int) -> String {
        let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        switch hour {
        case 6: return "🌅 \(formatter.string(from: hourDate))"
        case 12: return "☀️ \(formatter.string(from: hourDate))"
        case 18: return "🌇 \(formatter.string(from: hourDate))"
        case 21: return "🌙 \(formatter.string(from: hourDate))"
        case 0: return "🌛 \(formatter.string(from: hourDate))"
        default: return formatter.string(from: hourDate)
        }
    }
    
    private func isCurrentHour(_ hour: Int) -> Bool {
        return isToday && calendar.component(.hour, from: Date()) == hour
    }
}

// MARK: - Infinite Timeline Canvas

struct InfiniteTimelineCanvas: View {
    let date: Date
    let isToday: Bool
    let onTap: (Date) -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    @EnvironmentObject private var aiService: AIService
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Rectangle()
                    .fill(hourBackgroundColor(for: hour))
                    .frame(height: 60)
                    .overlay(
                        // Quarter hour grid lines
                        VStack(spacing: 0) {
                            ForEach([15, 30, 45], id: \.self) { minute in
                                Rectangle()
                                    .fill(.quaternary.opacity(0.1))
                                    .frame(height: 1)
                                    .frame(maxWidth: .infinity)
                                    .offset(y: CGFloat(minute - 15))
                            }
                        },
                        alignment: .top
                    )
                    .overlay(
                        // Current time indicator
                        currentTimeIndicator(for: hour),
                        alignment: .topLeading
                    )
                    .overlay(
                        // Hour separator
                        Rectangle()
                            .fill(.quaternary.opacity(0.3))
                            .frame(height: 1),
                        alignment: .bottom
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let hourTime = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
                        onTap(hourTime)
                    }
            }
        }
    }
    
    private func hourBackgroundColor(for hour: Int) -> Color {
        AstronomicalTimeCalculator.shared.getTimeColor(for: hour, date: date)
    }
    
    @ViewBuilder
    private func currentTimeIndicator(for hour: Int) -> some View {
        if isToday && isCurrentHour(hour) {
            let now = Date()
            let minute = calendar.component(.minute, from: now)
            let offsetY = CGFloat(minute)
            
            HStack(spacing: 8) {
                Rectangle()
                    .fill(.blue)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .opacity(0.8)
                    .shadow(color: .blue, radius: 1)
                
                Text("now")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                    .opacity(0.9)
            }
            .offset(y: offsetY)
        }
    }
    
    private func isCurrentHour(_ hour: Int) -> Bool {
        return calendar.component(.hour, from: Date()) == hour
    }
}

// MARK: - Infinite Event Card

struct InfiniteEventCard: View {
    let block: TimeBlock
    let date: Date
    let minuteHeight: CGFloat
    let isDragged: Bool
    let onDrag: (CGPoint) -> Void
    let onDrop: (Date) -> Void
    
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isHovering = false
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                // Energy and flow indicators
                VStack(spacing: 1) {
                    Text(block.energy.rawValue)
                        .font(.caption)
                    Text(block.emoji)
                        .font(.caption2)
                }
                .opacity(0.8)
                .frame(width: 25)
                
                // Block content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if !block.emoji.isEmpty {
                            Text(block.emoji)
                                .font(.caption)
                        }
                        
                        Text(block.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(durationBasedLineLimit)
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 4) {
                        Text(block.startTime.preciseTwoLineTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        
                        Text("\(block.durationMinutes)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                // Glass state indicator
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: eventHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.crystal)
        .scaleEffect(isDragging ? 0.98 : 1.0)
        .offset(x: dragOffset.width, y: dragOffset.height + yPosition)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    dragOffset = value.translation
                    onDrag(value.location)
                }
                .onEnded { value in
                    isDragging = false
                    dragOffset = .zero
                    
                    let newTime = calculateNewTime(from: value.translation)
                    onDrop(newTime)
                }
        )
    }
    
    // MARK: - Computed Properties
    
    private var yPosition: CGFloat {
        let dayStart = calendar.startOfDay(for: date)
        let totalMinutesFromStart = block.startTime.timeIntervalSince(dayStart) / 60
        return CGFloat(totalMinutesFromStart) * minuteHeight
    }
    
    private var eventHeight: CGFloat {
        CGFloat(block.durationMinutes) * minuteHeight
    }
    
    private var durationBasedLineLimit: Int {
        switch block.durationMinutes {
        case 0..<30: return 1
        case 30..<90: return 2
        default: return 3
        }
    }
    
    private var stateColor: Color {
        switch block.glassState {
        case .solid: return .green
        case .liquid: return .blue
        case .mist: return .orange
        case .crystal: return .cyan
        }
    }
    
    private var borderColor: Color {
        switch block.glassState {
        case .solid: return .clear
        case .liquid: return .blue.opacity(0.6)
        case .mist: return .orange.opacity(0.5)
        case .crystal: return .cyan.opacity(0.7)
        }
    }
    
    private func calculateNewTime(from translation: CGSize) -> Date {
        let minuteChange = Int(translation.height / minuteHeight)
        let newTime = calendar.date(byAdding: .minute, value: minuteChange, to: block.startTime) ?? block.startTime
        
        // Round to nearest 15-minute interval
        let minute = calendar.component(.minute, from: newTime)
        let roundedMinute = (minute / 15) * 15
        
        return calendar.date(bySettingHour: calendar.component(.hour, from: newTime),
                           minute: roundedMinute,
                           second: 0,
                           of: newTime) ?? newTime
    }
}

// MARK: - Preview

#if DEBUG
struct InfiniteDayScrollView_Previews: PreviewProvider {
    static var previews: some View {
        InfiniteDayScrollView(selectedDate: .constant(Date()))
            .environmentObject(AppDataManager.preview)
            .frame(width: 800, height: 600)
    }
}
#endif
