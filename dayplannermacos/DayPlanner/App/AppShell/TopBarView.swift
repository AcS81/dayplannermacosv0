// MARK: - Status Bar

import SwiftUI

struct StatusBar: View {
    let aiConnected: Bool
    let onSettingsTap: () -> Void
    let onDiagnosticsTap: () -> Void
    
    var body: some View {
        HStack {
            // AI connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(aiConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                
                Text(aiConnected ? "AI Ready" : "AI Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onTapGesture { onDiagnosticsTap() }
            
            Spacer()
            
            // App title
            Text("🌊 Day Planner")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Settings button
            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

// MARK: - Top Bar View

struct TopBarView: View {
    let xp: Int
    let xxp: Int
    let aiConnected: Bool
    @Binding var showingMindPanel: Bool
    let hideSettingsButton: Bool
    @Binding var isHoveringSettings: Bool
    let onSettingsTap: () -> Void
    let onDiagnosticsTap: () -> Void
    
    var body: some View {
        HStack {
            // XP and XXP display - HIDDEN BY DEFAULT
            // Will be shown in animated settings panel instead
            Spacer()
            
            // AI connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(aiConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                
                Text(aiConnected ? "AI Ready" : "AI Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onTapGesture { onDiagnosticsTap() }
            
            Spacer()
            
            // Settings button - hidden when overlay is showing
            if !isHoveringSettings {
                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isHoveringSettings = hovering
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Hover Settings Overlay

struct HoverSettingsOverlay: View {
    let xp: Int
    let xxp: Int
    let isVisible: Bool
    let onSettingsTap: () -> Void
    
    @State private var xpOpacity: Double = 0
    @State private var xpScale: CGFloat = 0.8
    
    var body: some View {
        // Darker overlay that covers the entire top bar area - matches TopBarView exactly
        HStack {
            // XP and XXP display - positioned where the original spacer was
            Spacer()
            
            // AI connection status (hidden in overlay)
            HStack(spacing: 6) {
                Circle()
                    .fill(.clear) // Hidden
                    .frame(width: 8, height: 8)
                
                Text("") // Hidden
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .opacity(0) // Completely hidden
            
            Spacer()
            
            // XP/XXP Display - positioned to the left of settings
            HStack(spacing: 12) {
                // XP Display
                HStack(spacing: 6) {
                    Text("XP")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    Text("\(xp)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.1), in: Capsule())
                .opacity(xpOpacity)
                .scaleEffect(xpScale)
                
                // XXP Display
                HStack(spacing: 6) {
                    Text("XXP")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                    Text("\(xxp)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.1), in: Capsule())
                .opacity(xpOpacity)
                .scaleEffect(xpScale)
                
                // Settings button (unchanged) - this will overlay the original button
                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            // Darker version of the tab section background
            .regularMaterial.opacity(0.9),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            if isVisible {
                withAnimation(.easeInOut(duration: 0.3)) {
                    xpOpacity = 1.0
                    xpScale = 1.0
                }
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.3)) {
                    xpOpacity = 1.0
                    xpScale = 1.0
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    xpOpacity = 0
                    xpScale = 0.8
                }
            }
        }
    }
}

