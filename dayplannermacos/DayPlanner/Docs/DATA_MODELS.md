# Core Data Models

This guide highlights the most important model types defined in [`Data/Models.swift`](../Data/Models.swift) and how they relate to one another. Use it when extending persistence, adding new behaviours, or wiring data into SwiftUI views.

## Scheduling & Calendar

| Type | Purpose | Notable Properties |
| --- | --- | --- |
| `TimeBlock` | Primary unit scheduled on the calendar. Supports drag positions, AI provenance, and EventKit syncing. | `startTime`, `duration`, `energy`, `emoji`, `glassState`, `relatedGoalId`, `suggestionId`, `origin`, `notes`, `confirmationState` |
| `EnergyType` | Categorises the energy required for a block (e.g. `daylight`, `focus`, `dream`). Drives colour accents. | `color`, `displayName`, `icon` helpers (see extension at bottom of file). |
| `GlassState` | Visual treatment of a block within the "liquid glass" theme (`solid`, `liquid`, `vapor`). | Used across surfaces to customise backgrounds. |
| `TimePeriod` | Derived property grouping blocks into morning/afternoon/evening buckets. | Produced from `TimeBlock.startTime`. |
| `TimeWindow` | Reusable time span used by pillars and routines. | `start`, `end`, overlap helpers. |

## Goals, Pillars, and Chains

| Type | Purpose | Notable Properties |
| --- | --- | --- |
| `Pillar` | Long-term focus area. Tracks cadence rules (`frequency`, `timeWindows`) and emphasis flags. | `type`, `isEmphasized`, `timeWindows`, `overlapRule`, `xpReward`. |
| `Goal` | Concrete target linked to a pillar. Supports graph-based breakdowns and XP payouts. | `state`, `pillarId`, `tasks`, `graph`, `xpReward`, `isPinned`. |
| `Chain` | Habitual streaks of repeated actions with optional reminder windows. | `title`, `frequency`, `lastCompleted`, `streak`, `reminderTime`. |
| `GoalGraph` | Node/edge representation for mind-mapping a goal's decomposition. | `nodes`, `edges`, `history`. |
| `Routine` & `RoutineScheduleRule` | Template for recurring block suggestions, including frequency and conditions. | `pattern`, `conditions`, `blocks`. |

## Suggestions & Feedback

| Type | Purpose | Notable Properties |
| --- | --- | --- |
| `Suggestion` | AI or rule-based recommendation for a future time block. | `title`, `weight`, `confidence`, `reason`, `relatedGoalId`, `source`. |
| `SuggestionWeighting` | Tunable weights for combining suggestion scores. | `goalAlignment`, `pillarAdherence`, `feedbackBoost`. |
| `SuggestionFeedbackStats` | Aggregated feedback counts used for learning. | `accepted`, `rejected`, `snoozed`, per-target metrics. |
| `FeedbackEntry` | Logged user response (accept/snooze/reject) with optional tags. | `targetType`, `targetId`, `mood`, `tags`, `notes`. |
| `FollowUpMetadata` | Captures automatic follow-up prompts and deadlines for deferred work. | `dueDate`, `reason`, `relatedGoalId`. |

## App State & Persistence

| Type | Purpose | Notable Properties |
| --- | --- | --- |
| `AppState` | Snapshot of the entire planner: days, suggestions, mood history, preferences. | `days`, `suggestions`, `userXP`, `userXXP`, `onboardingState`, `pendingFeedback`. |
| `Day` | Collection of blocks, reflections, and stats for a single date. | `date`, `blocks`, `mood`, `notes`, `patternSummary`. |
| `Record` | Audit-style history entry (used by History view). | `timestamp`, `summary`, `details`, `tags`. |
| `UserPreferences` | User-configurable settings including AI connectivity, EventKit policy, interface toggles. | `aiProvider`, `customApiEndpoint`, `calendarSyncEnabled`, `preferredTheme`. |
| `EventKitWritePolicy` | Tri-state toggle for Calendar write behaviour (`readOnly`, `prompt`, `alwaysAllow`). | Consumed by `AppDataManager`. |
| `OnboardingState` | Tracks guided onboarding progress, tasks completed, and outstanding prompts. | `phase`, `capturedMood`, `createdBlocks`, `feedbackSubmitted`. |

## Mood & Wellbeing

| Type | Purpose | Notable Properties |
| --- | --- | --- |
| `MoodEntry` | Captured mood sample with energy and optional note. | `rating`, `energy`, `source`, `tags`. |
| `MoodCaptureSource` | Labels where a mood entry came from (`onboarding`, `dailyPrompt`, `manual`). | Useful for analytics dashboards. |
| `GlassMood` | Visualises overall mood climate used by glass effects. | `primaryColor`, `secondaryColor`. |

## Intake & Mind Editor

| Type | Purpose | Notable Properties |
| --- | --- | --- |
| `DreamConcept` | Short-form idea captured during brainstorming, tagged for follow-ups. | `tag`, `impact`, `xpReward`. |
| `IntakeQuestion` | Dynamic question used during onboarding or AI intake flows. | `category`, `prompt`, `placeholder`, `answer`, `followUps`. |
| `TimeframeSelector` | Enum bridging UI timeframe filters between mind components. | Cases for `.now`, `.week`, `.month`, `.season`, `.year`. |
| `ChainTemplate` & `QuickTemplate` | Pre-baked scaffolds for rapidly creating chains or time blocks. | Provide canonical emoji/energy combinations. |

## Helper Extensions

At the end of the file there are convenience extensions that:

- Provide computed titles/colours for enums (`EnergyType`, `GlassState`, `PillarType`, `GoalState`).
- Offer factory helpers for common templates (`Pillar.sample`, `Goal.sample`).
- Support drag-and-drop (`TimeBlock` conforms to `Transferable`).

## Storage & State Manager

[`Data/Storage.swift`](../Data/Storage.swift) implements `AppDataManager`, the central observable object. Key responsibilities:

- Persist and load `AppState` to JSON using `FileManager` and `JSONEncoder`/`Decoder`.
- Provide mutation APIs for calendar content (`addTimeBlock`, `updateTimeBlock`, `moveTimeBlock`, `removeTimeBlock`).
- Manage pillars/goals (pinning, emphasis, AI-backed creation) and maintain suggestion queues.
- Track onboarding progress, mood prompts, EventKit sync metadata, and AI feedback weighting.
- Expose helper structs like `MindCommandOutcome`, `SuggestionSnapshot`, and `DateFormatters` for use across the UI.

When adding new model properties ensure they are encoded/decoded inside the relevant `CodingKeys`, and update any derived logic in `AppDataManager` so persisted state stays consistent.
