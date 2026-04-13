import Foundation

// MARK: - Hook Event Types

enum ClaudeEventType: String, Codable {
    case userPromptSubmit = "UserPromptSubmit"
    case preCompact = "PreCompact"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case subagentStop = "SubagentStop"
}

enum ClaudeStatus: String, Codable {
    case processing
    case compacting
    case waitingForInput = "waiting_for_input"
    case ended
    case runningTool = "running_tool"
    case unknown
}

/// JSON payload received from the hook script via Unix socket.
struct ClaudeEvent: Codable {
    let sessionId: String
    let transcriptPath: String?
    let cwd: String?
    let event: ClaudeEventType
    let status: ClaudeStatus
    let pid: Int?
    let tty: String?
    let interactive: Bool?
    let permissionMode: String?
    let userPrompt: String?
    let tool: String?
    let toolUseId: String?
    let toolInput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd, event, status, pid, tty, interactive
        case permissionMode = "permission_mode"
        case userPrompt = "user_prompt"
        case tool
        case toolUseId = "tool_use_id"
        case toolInput = "tool_input"
    }
}

/// Type-erased Codable wrapper for arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

// MARK: - Sprite State

enum SpriteState: Equatable {
    case idle
    case working
    case sleeping
    case compacting
    case needsPermission
}

// MARK: - Session Model

struct ClaudeSession: Identifiable {
    let id: String
    var spriteState: SpriteState = .idle
    var cwd: String?
    var lastEvent: ClaudeEventType?
    var lastTool: String?
    var eventCount: Int = 0
    var startedAt: Date = Date()
    var lastActivityAt: Date = Date()
    var interactive: Bool = true
    var recentEvents: [ActivityItem] = []

    static let maxRecentEvents = 50

    mutating func appendEvent(_ item: ActivityItem) {
        recentEvents.append(item)
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - Self.maxRecentEvents)
        }
    }
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let event: ClaudeEventType
    let tool: String?
    let status: ClaudeStatus
}
