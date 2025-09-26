import Foundation

// MARK: - Context

struct MindEditorContext: Codable {
    struct GoalSummary: Codable {
        struct NodeSummary: Codable {
            let id: UUID
            let type: String
            let title: String
            let detail: String?
            let pinned: Bool
            let weight: Double
        }

        let id: UUID
        let title: String
        let description: String
        let emoji: String
        let importance: Int
        let pinnedNodeTitles: [String]
        let nodes: [NodeSummary]
    }

    struct PillarSummary: Codable {
        let id: UUID
        let name: String
        let description: String
        let frequency: String
        let wisdom: String?
        let values: [String]
        let habits: [String]
        let constraints: [String]
        let quietHours: [String]
    }

    let goals: [GoalSummary]
    let pillars: [PillarSummary]
}

// MARK: - Command core models

struct MindCommandResponse {
    let summary: String
    let commands: [MindCommand]
}

enum MindCommandType: String, Decodable {
    case createGoal = "create_goal"
    case updateGoal = "update_goal"
    case addNode = "add_node"
    case linkNodes = "link_nodes"
    case pinNode = "pin_node"
    case createPillar = "create_pillar"
    case updatePillar = "update_pillar"
    case askClarification = "ask_clarification"
    case noop = "noop"
}

struct MindCommandNodeDescriptor: Decodable {
    let type: GoalGraphNodeType?
    let title: String
    let detail: String?
    let pinned: Bool?
    let weight: Double?
}

struct MindQuietHourDescriptor: Decodable {
    let start: String
    let end: String
}

struct MindCommandUpdateDescriptor: Decodable {
    let title: String?
    let description: String?
    let emoji: String?
    let importance: Int?
    let wisdom: String?
    let frequency: String?
    let quietHours: [MindQuietHourDescriptor]?
    let principles: [String]?
    let constraints: [String]?
    let values: [String]?
    let habits: [String]?
    let focus: String?
}

struct MindCommandLinkDescriptor: Decodable {
    let fromNodeTitle: String?
    let toNodeTitle: String?
    let label: String?
}

struct MindCommandDescriptor: Decodable {
    let type: MindCommandType
    let goalId: UUID?
    let goalTitle: String?
    let pillarId: UUID?
    let pillarName: String?
    let title: String?
    let description: String?
    let emoji: String?
    let importance: Int?
    let nodes: [MindCommandNodeDescriptor]?
    let updates: MindCommandUpdateDescriptor?
    let link: MindCommandLinkDescriptor?
    let linkToTitle: String?
    let linkLabel: String?
    let targetNodeId: UUID?
    let targetNodeTitle: String?
    let pinState: Bool?
    let pillarIds: [UUID]?
    let pillarNames: [String]?
    let question: String?
    let focus: String?
}

struct MindCommandResponseModel: Decodable {
    let summary: String?
    let commands: [MindCommandDescriptor]
}

struct MindCommandGoalReference {
    let id: UUID?
    let title: String?

    var isValid: Bool {
        id != nil || !(title?.isEmpty ?? true)
    }
}

struct MindCommandPillarReference {
    let id: UUID?
    let name: String?

    var isValid: Bool {
        id != nil || !(name?.isEmpty ?? true)
    }
}

struct MindCommandNode {
    let type: GoalGraphNodeType
    let title: String
    let detail: String?
    let pinned: Bool
    let weight: Double?
}

struct MindCommandCreateGoal {
    let title: String
    let description: String?
    let emoji: String?
    let importance: Int?
    let nodes: [MindCommandNode]
    let relatedPillarIds: [UUID]
    let relatedPillarNames: [String]
}

struct MindCommandUpdateGoal {
    let reference: MindCommandGoalReference
    let title: String?
    let description: String?
    let emoji: String?
    let importance: Int?
    let focus: String?
}

struct MindCommandAddNode {
    let reference: MindCommandGoalReference
    let node: MindCommandNode
    let linkToTitle: String?
    let linkLabel: String?
}

struct MindCommandLinkNodes {
    let reference: MindCommandGoalReference
    let fromTitle: String
    let toTitle: String
    let label: String?
}

struct MindCommandPinNode {
    let reference: MindCommandGoalReference
    let nodeTitle: String
    let desiredState: Bool
}

struct MindCommandCreatePillar {
    let name: String
    let description: String?
    let emoji: String?
    let frequency: String?
    let wisdom: String?
    let values: [String]
    let habits: [String]
    let constraints: [String]
    let quietHours: [MindQuietHourDescriptor]
}

struct MindCommandUpdatePillar {
    let reference: MindCommandPillarReference
    let description: String?
    let emoji: String?
    let frequency: String?
    let wisdom: String?
    let values: [String]
    let habits: [String]
    let constraints: [String]
    let quietHours: [MindQuietHourDescriptor]
}

enum MindCommand {
    case createGoal(MindCommandCreateGoal)
    case updateGoal(MindCommandUpdateGoal)
    case addNode(MindCommandAddNode)
    case linkNodes(MindCommandLinkNodes)
    case pinNode(MindCommandPinNode)
    case createPillar(MindCommandCreatePillar)
    case updatePillar(MindCommandUpdatePillar)
    case clarification(String)
}

// MARK: - Helpers

extension MindCommandResponseModel {
    func toMindCommandResponse() -> MindCommandResponse {
        let converted = commands.compactMap { MindCommand.fromDescriptor($0) }
        return MindCommandResponse(summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", commands: converted)
    }
}

extension MindCommand {
    static func fromDescriptor(_ descriptor: MindCommandDescriptor) -> MindCommand? {
        switch descriptor.type {
        case .createGoal:
            guard let title = normalized(descriptor.title) else { return nil }
            let nodes = descriptor.nodes?.compactMap { MindCommandNode(descriptor: $0) } ?? []
            let payload = MindCommandCreateGoal(
                title: title,
                description: normalized(descriptor.description),
                emoji: normalized(descriptor.emoji),
                importance: descriptor.importance,
                nodes: nodes,
                relatedPillarIds: descriptor.pillarIds ?? [],
                relatedPillarNames: descriptor.pillarNames?.compactMap(normalized) ?? []
            )
            return .createGoal(payload)

        case .updateGoal:
            let reference = MindCommandGoalReference(id: descriptor.goalId, title: normalized(descriptor.goalTitle ?? descriptor.title))
            guard reference.isValid else { return nil }
            let updates = descriptor.updates
            let payload = MindCommandUpdateGoal(
                reference: reference,
                title: normalized(updates?.title ?? descriptor.title),
                description: normalized(updates?.description ?? descriptor.description),
                emoji: normalized(updates?.emoji ?? descriptor.emoji),
                importance: updates?.importance ?? descriptor.importance,
                focus: normalized(updates?.focus ?? descriptor.focus)
            )
            return .updateGoal(payload)

        case .addNode:
            let reference = MindCommandGoalReference(id: descriptor.goalId, title: normalized(descriptor.goalTitle))
            guard reference.isValid, let nodeDescriptor = descriptor.nodes?.first, let node = MindCommandNode(descriptor: nodeDescriptor) else { return nil }
            let payload = MindCommandAddNode(
                reference: reference,
                node: node,
                linkToTitle: normalized(descriptor.linkToTitle ?? descriptor.link?.fromNodeTitle),
                linkLabel: normalized(descriptor.linkLabel ?? descriptor.link?.label)
            )
            return .addNode(payload)

        case .linkNodes:
            let reference = MindCommandGoalReference(id: descriptor.goalId, title: normalized(descriptor.goalTitle))
            guard reference.isValid,
                  let link = descriptor.link,
                  let from = normalized(link.fromNodeTitle ?? descriptor.title),
                  let to = normalized(link.toNodeTitle ?? descriptor.linkToTitle) else { return nil }
            let payload = MindCommandLinkNodes(
                reference: reference,
                fromTitle: from,
                toTitle: to,
                label: normalized(link.label ?? descriptor.linkLabel)
            )
            return .linkNodes(payload)

        case .pinNode:
            let reference = MindCommandGoalReference(id: descriptor.goalId, title: normalized(descriptor.goalTitle))
            guard reference.isValid else { return nil }
            let nodeTitle = normalized(descriptor.targetNodeTitle ?? descriptor.title)
            guard let nodeTitle else { return nil }
            let payload = MindCommandPinNode(
                reference: reference,
                nodeTitle: nodeTitle,
                desiredState: descriptor.pinState ?? true
            )
            return .pinNode(payload)

        case .createPillar:
            guard let name = normalized(descriptor.title ?? descriptor.pillarName) else { return nil }
            let payload = MindCommandCreatePillar(
                name: name,
                description: normalized(descriptor.description),
                emoji: normalized(descriptor.emoji),
                frequency: normalized(descriptor.updates?.frequency ?? descriptor.focus),
                wisdom: normalized(descriptor.updates?.wisdom),
                values: descriptor.updates?.values?.compactMap(normalized) ?? descriptor.updates?.principles?.compactMap(normalized) ?? [],
                habits: descriptor.updates?.habits?.compactMap(normalized) ?? [],
                constraints: descriptor.updates?.constraints?.compactMap(normalized) ?? [],
                quietHours: descriptor.updates?.quietHours ?? []
            )
            return .createPillar(payload)

        case .updatePillar:
            let reference = MindCommandPillarReference(id: descriptor.pillarId, name: normalized(descriptor.pillarName ?? descriptor.title))
            guard reference.isValid else { return nil }
            let updates = descriptor.updates
            if updates == nil && descriptor.description == nil && descriptor.emoji == nil && descriptor.focus == nil { return nil }
            let payload = MindCommandUpdatePillar(
                reference: reference,
                description: normalized(updates?.description ?? descriptor.description),
                emoji: normalized(updates?.emoji ?? descriptor.emoji),
                frequency: normalized(updates?.frequency ?? descriptor.focus),
                wisdom: normalized(updates?.wisdom),
                values: updates?.values?.compactMap(normalized) ?? updates?.principles?.compactMap(normalized) ?? [],
                habits: updates?.habits?.compactMap(normalized) ?? [],
                constraints: updates?.constraints?.compactMap(normalized) ?? [],
                quietHours: updates?.quietHours ?? []
            )
            return .updatePillar(payload)

        case .askClarification:
            if let question = normalized(descriptor.question ?? descriptor.description ?? descriptor.title) {
                return .clarification(question)
            }
            return nil

        case .noop:
            return nil
        }
    }
}

extension MindCommandNode {
    init?(descriptor: MindCommandNodeDescriptor) {
        let trimmedTitle = normalized(descriptor.title)
        guard let trimmedTitle else { return nil }
        let type = descriptor.type ?? .note
        self.init(
            type: type,
            title: trimmedTitle,
            detail: normalized(descriptor.detail),
            pinned: descriptor.pinned ?? false,
            weight: descriptor.weight
        )
    }
}

private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
