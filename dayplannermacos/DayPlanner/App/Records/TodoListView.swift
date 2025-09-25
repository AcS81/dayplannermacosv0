//
//  TodoListView.swift
//  DayPlanner
//
//  To-Do list with follow-up cluster for re-queued items
//

import SwiftUI

struct TodoListView: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var showingAddTodo = false
    @State private var followUpEditor: FollowUpEditorState?
    private let dragEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    private var followUpItems: [TodoItem] {
        dataManager.appState.todoItems.filter { $0.isFollowUp && !$0.isCompleted }
    }
    
    private var activeItems: [TodoItem] {
        dataManager.appState.todoItems.filter { !$0.isFollowUp && !$0.isCompleted }
    }
    
    private var completedItems: [TodoItem] {
        dataManager.appState.todoItems.filter { $0.isCompleted }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.05)
            content
        }
        .background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .sheet(isPresented: $showingAddTodo) {
            AddTodoSheet { title, dueDate in
                let item = TodoItem(title: title, dueDate: dueDate)
                dataManager.addTodoItem(item)
            }
        }
        .sheet(item: $followUpEditor) { editor in
            FollowUpConfirmSheet(editor: editor) { updated in
                dataManager.confirmFollowUpTodo(
                    updated.item.id,
                    updatedTitle: updated.title,
                    startTime: updated.start,
                    endTime: updated.end,
                    notes: updated.notes
                )
                followUpEditor = nil
            }
        }
    }
    
    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("To-Do")
                    .font(.headline)
                    .fontWeight(.semibold)
                if !followUpItems.isEmpty {
                    Text("Follow-ups: \(followUpItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }
            Spacer()
            Button {
                showingAddTodo = true
            } label: {
                Label("Add", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .padding(6)
                    .background(.blue.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add new to-do")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.3))
    }
    
    @ViewBuilder
    private var content: some View {
        if followUpItems.isEmpty && activeItems.isEmpty && completedItems.isEmpty {
            EmptyTodosView(onAdd: { showingAddTodo = true })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    if !followUpItems.isEmpty {
                        Section(header: sectionHeader(title: "Follow-up")) {
                            VStack(spacing: 12) {
                                ForEach(followUpItems) { item in
                                    FollowUpRow(
                                        item: item,
                                        onConfirm: { followUpEditor = FollowUpEditorState(item: item) },
                                        onDelete: { dataManager.removeTodoItem(item.id) },
                                        onDrag: { dragProvider(for: item) }
                                    )
                                }
                            }
                        }
                    }
                    
                    if !activeItems.isEmpty {
                        Section(header: sectionHeader(title: "Tasks")) {
                            VStack(spacing: 10) {
                                ForEach(activeItems) { item in
                                    TodoRow(
                                        item: item,
                                        onToggle: { dataManager.toggleTodoCompletion(item.id) },
                                        onDelete: { dataManager.removeTodoItem(item.id) },
                                        onDrag: { dragProvider(for: item) }
                                    )
                                }
                            }
                        }
                    }
                    
                    if !completedItems.isEmpty {
                        Section(header: sectionHeader(title: "Completed")) {
                            VStack(spacing: 8) {
                                ForEach(completedItems) { item in
                                    CompletedRow(
                                        item: item,
                                        onToggle: { dataManager.toggleTodoCompletion(item.id) },
                                        onDelete: { dataManager.removeTodoItem(item.id) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
        }
    }
    
    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func dragProvider(for item: TodoItem) -> NSItemProvider {
        let payload = TodoDragPayload(
            id: item.id,
            title: item.title,
            dueDate: item.dueDate,
            isCompleted: item.isCompleted,
            followStart: item.followUp?.startTime,
            followDuration: item.followUp?.duration,
            notes: item.notes
        )
        guard let data = try? dragEncoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return NSItemProvider(object: NSString(string: "todo_item:{}"))
        }
        return NSItemProvider(object: NSString(string: "todo_item:\(json)"))
    }
}

// MARK: - Follow-up UI

private struct FollowUpRow: View {
    let item: TodoItem
    let onConfirm: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider
    
    private var followUp: FollowUpMetadata {
        item.followUp ?? FollowUpMetadata(
            blockId: item.id,
            originalTitle: item.title,
            startTime: item.createdDate,
            endTime: item.createdDate.addingTimeInterval(1800),
            energy: .daylight,
            emoji: "📋",
            notesSnapshot: item.notes,
            capturedAt: item.createdDate
        )
    }
    
    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: followUp.startTime)
        let end = formatter.string(from: followUp.endTime)
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        let day = dayFormatter.string(from: followUp.startTime)
        return "\(day) • \(start) – \(end)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(followUp.originalTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onConfirm) {
                    Label("Confirm now", systemImage: "checkmark.circle")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens confirmation editor for this past item")
                
                Menu {
                    Button("Remove", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 8) {
                Text("Past/Unconfirmed")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                
                Text(timeRangeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if let notes = item.notes, !notes.isEmpty {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .onDrag { onDrag() }
    }
}

// MARK: - Standard To-Do Rows

private struct TodoRow: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider
    
    private var dueDateText: String? {
        guard let dueDate = item.dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: dueDate)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .strikethrough(item.isCompleted, color: .primary.opacity(0.3))
                
                if let dueDateText {
                    Text("Due \(dueDateText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Menu {
                Button(item.isCompleted ? "Mark as open" : "Mark as done", action: onToggle)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .onDrag { onDrag() }
    }
}

private struct CompletedRow: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Empty State

private struct EmptyTodosView: View {
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("All clear")
                .font(.headline)
            Text("Capture follow-ups or quick tasks to keep momentum.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Add a to-do", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}

// MARK: - Follow-up Editor

private struct FollowUpEditorState: Identifiable {
    let id = UUID()
    let item: TodoItem
    var title: String
    var start: Date
    var end: Date
    var notes: String
    
    init(item: TodoItem) {
        self.item = item
        if let follow = item.followUp {
            title = item.title
            start = follow.startTime
            end = follow.endTime
            notes = item.notes ?? follow.notesSnapshot ?? ""
        } else {
            title = item.title
            start = item.createdDate
            end = item.createdDate.addingTimeInterval(1800)
            notes = item.notes ?? ""
        }
    }
}

private struct FollowUpConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let editor: FollowUpEditorState
    let onConfirm: (FollowUpEditorState) -> Void
    
    @State private var workingTitle: String
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String
    
    init(editor: FollowUpEditorState, onConfirm: @escaping (FollowUpEditorState) -> Void) {
        self.editor = editor
        self.onConfirm = onConfirm
        _workingTitle = State(initialValue: editor.title)
        _start = State(initialValue: editor.start)
        _end = State(initialValue: editor.end)
        _notes = State(initialValue: editor.notes)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Summary") {
                    TextField("What happened?", text: $workingTitle)
                    DatePicker("Start", selection: $start)
                    DatePicker("End", selection: $end)
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Confirm past item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }
                        .disabled(workingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 420)
    }
    
    private func submit() {
        var updated = editor
        updated.title = workingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.start = start
        updated.end = end
        updated.notes = notes
        onConfirm(updated)
        dismiss()
    }
}

private struct TodoDragPayload: Codable {
    let id: UUID
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let followStart: Date?
    let followDuration: TimeInterval?
    let notes: String?
}

// MARK: - Add To-Do Sheet

struct AddTodoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    
    let onAdd: (String, Date?) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To-do title")
                        .font(.headline)
                    TextField("Enter to-do…", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Add to-do")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(title.trimmingCharacters(in: .whitespacesAndNewlines), hasDueDate ? dueDate : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 420, height: 320)
    }
}
