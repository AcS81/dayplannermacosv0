# AI & Intelligence Overview

This guide explains how the planner integrates AI services, speech tooling, and behavioural learning so you can safely extend or debug AI-driven features.

## AIService (AI/AIService.swift)

`AIService` is the primary facade for talking to both local LM Studio endpoints and the OpenAI API. It is marked `@MainActor` because UI code frequently reads its published properties.

Key capabilities:

- **Provider switching**: The `AIProvider` enum in `Models.swift` chooses between `.local` and `.openAI`. `configure(with:)` updates base URLs, API keys, and models.
- **Connection management**: `checkConnection()` pings the selected endpoint, updating `isConnected` and `lastResponseTime`. `startConnectionMonitoring()` schedules periodic health checks.
- **Request routing**: Helpers like `performQuery`, `generateSuggestions`, `generateFollowUps`, and `analyzeDay` build JSON payloads using current `AppState` context, then dispatch via `URLSession`.
- **Confidence thresholds**: `AIConfidenceThresholds` adjusts behaviour (e.g., when to auto-apply suggestions) based on action type.
- **Speech integration**: The nested `WhisperService` wraps the Whisper transcription REST API. It produces transcripts used by voice-driven commands.

When adding new AI endpoints, keep them asynchronous (`async`/`await`) and funnel authentication through the existing `performRequest` helper to respect retry/timeout policies.

## PatternLearningEngine (Intelligence/PatternLearning.swift)

`PatternLearningEngine` is responsible for detecting behaviour patterns and exposing insights to the UI.

- **Event ingestion**: Views call `recordBehavior(_:)` with `BehaviorEvent` instances (e.g., block created, mood logged). The engine maintains a bounded history and persists it via `savePatterns()`.
- **Analysis cadence**: Uses a debounced `Task` to avoid redundant work. `performFullAnalysis()` fans out into time, energy, flow, and chain analysis concurrently via `TaskGroup`.
- **Insights & metrics**: Updates `detectedPatterns`, `insights`, `actionableInsights`, and `uiMetrics`, which power dashboards in `Views/Settings/Diagnostics` and overlays in the mind panel.
- **AI feedback loop**: Exposes aggregated recommendations through `currentRecommendation` and cooperates with `AIService` to improve prompt context.

Extend the engine by adding new analyser helpers (mirroring `analyzeEnergyPatterns()`, etc.) and append to the `Pattern`/`Insight` enums in `PatternLearningModels`.

## Mind Editor Models (Intelligence/MindEditorModels.swift)

These Codable structs translate between AI-generated commands and in-app operations:

- `MindEditorContext` summarises current goals and pillars and is serialised before being sent to AI agents.
- `MindCommandDescriptor` (and supporting descriptors) decode AI responses into strongly typed commands like `create_goal`, `update_goal`, or `link_nodes`.
- `MindCommandOutcome` (defined in `Data/Storage.swift`) is produced after applying a command, letting the UI surface success/failure feedback.

When teaching the AI new abilities, introduce a new `MindCommandType` case, extend the descriptor structs, and implement handling in `AppDataManager.executeMindCommand` (see `Data/Storage.swift`).

## Voice Capture Flow

1. `WhisperService.transcribe(audioFileURL:apiKey:)` uploads local recordings to the Whisper REST API.
2. The resulting transcript feeds into `AIService.performQuery` or higher-level helpers (e.g., `processVoiceNote`).
3. Responses are routed back through the mind editor pipeline or suggestion generators depending on intent.

Ensure microphone permissions are checked using `AudioPermissionStatus` before starting a recording. The status is stored in `UserPreferences` for persistence.

## Diagnostics & Tooling

- `App/Settings/AIDiagnosticsView.swift` visualises recent responses, latency, and errors from `AIService`.
- `PatternDiagnosticsView` (in `Views/Settings/Diagnostics`) reads `PatternLearningEngine` metrics to help tune analysis thresholds.
- `HistoryLogView` (in `Views/Settings/SettingsViews.swift`) renders `Record` entries produced by `AppDataManager` for auditability.

When debugging AI issues, capture the latest JSON payloads via the diagnostics views, verify `AppDataManager` is providing the correct context snapshot, and confirm the correct provider (local vs remote) is configured in `UserPreferences`.
