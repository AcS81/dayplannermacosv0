import SwiftUI

struct MoodPromptBanner: View {
    @EnvironmentObject private var dataManager: AppDataManager
    @State private var skipEnabled = false
    @State private var countdown: Int = 10
    private let moods: [GlassMood] = GlassMood.allCases
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How are you arriving today?")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Pick a mood to tune recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 12)
            
            ForEach(moods, id: \.self) { mood in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dataManager.captureMood(mood)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(mood.emoji)
                            .font(.title2)
                        Text(mood.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(moodBackground(for: mood), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .frame(height: 32)
                .opacity(0.3)
            
            Button(action: { dataManager.skipMoodPrompt() }) {
                if skipEnabled {
                    Text("Not now")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15), in: Capsule())
                } else {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(10 - countdown), total: 10)
                            .frame(width: 40)
                        Text("Skip in \(countdown)s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!skipEnabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        .onAppear(perform: startCountdown)
    }
    
    private func startCountdown() {
        guard !skipEnabled else { return }
        countdown = 10
        Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
            }
            skipEnabled = true
        }
    }
    
    private func moodBackground(for mood: GlassMood) -> LinearGradient {
        switch mood {
        case .crystal:
            return LinearGradient(colors: [.blue.opacity(0.2), .teal.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mist:
            return LinearGradient(colors: [.gray.opacity(0.2), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .prism:
            return LinearGradient(colors: [.purple.opacity(0.2), .orange.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .storm:
            return LinearGradient(colors: [.indigo.opacity(0.25), .black.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct MoodStatusChip: View {
    @EnvironmentObject private var dataManager: AppDataManager
    let entry: MoodEntry
    @State private var showMenu = false
    
    private let moods: [GlassMood] = GlassMood.allCases
    
    var body: some View {
        Menu {
            Section("Update mood") {
                ForEach(moods, id: \.self) { mood in
                    Button(action: { dataManager.captureMood(mood, source: .quickUpdate) }) {
                        Label(mood.description, systemImage: moodSymbol(for: mood))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(entry.mood.emoji)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's mood")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.mood.description)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
        }
        .menuStyle(.borderlessButton)
    }
    
    private func moodSymbol(for mood: GlassMood) -> String {
        switch mood {
        case .crystal: return "sparkles"
        case .mist: return "cloud.fog"
        case .prism: return "circle.lefthalf.fill"
        case .storm: return "cloud.bolt"
        }
    }
}
