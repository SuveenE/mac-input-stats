import Foundation

/// Installs the Claude Code hook script and registers it in settings.
enum HookInstaller {
    private static let hookFileName = "claude-activity-hook.sh"

    private static var hooksDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks")
    }

    private static var settingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private static let hookScript = """
    #!/bin/bash
    # Claude Code activity hook - forwards events via Unix socket

    SOCKET_PATH="/tmp/notchi.sock"

    # Exit silently if socket doesn't exist (app not running)
    [ -S "$SOCKET_PATH" ] || exit 0

    # Detect non-interactive (claude -p / --print) sessions
    IS_INTERACTIVE=true
    for CHECK_PID in $PPID $(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' '); do
        if ps -o args= -p "$CHECK_PID" 2>/dev/null | grep -qE '(^| )(-p|--print)( |$)'; then
            IS_INTERACTIVE=false
            break
        fi
    done
    export NOTCHI_INTERACTIVE=$IS_INTERACTIVE

    # Parse input and send to socket using Python
    /usr/bin/python3 -c "
    import json
    import os
    import socket
    import sys

    try:
        input_data = json.load(sys.stdin)
    except:
        sys.exit(0)

    hook_event = input_data.get('hook_event_name', '')

    status_map = {
        'UserPromptSubmit': 'processing',
        'PreCompact': 'compacting',
        'SessionStart': 'waiting_for_input',
        'SessionEnd': 'ended',
        'PreToolUse': 'running_tool',
        'PostToolUse': 'processing',
        'PermissionRequest': 'waiting_for_input',
        'Stop': 'waiting_for_input',
        'SubagentStop': 'waiting_for_input'
    }

    output = {
        'session_id': input_data.get('session_id', ''),
        'transcript_path': input_data.get('transcript_path', ''),
        'cwd': input_data.get('cwd', ''),
        'event': hook_event,
        'status': input_data.get('status', status_map.get(hook_event, 'unknown')),
        'pid': None,
        'tty': None,
        'interactive': os.environ.get('NOTCHI_INTERACTIVE', 'true') == 'true',
        'permission_mode': input_data.get('permission_mode', 'default')
    }

    # Pass user prompt directly for UserPromptSubmit
    if hook_event == 'UserPromptSubmit':
        prompt = input_data.get('prompt', '')
        if prompt:
            output['user_prompt'] = prompt

    tool = input_data.get('tool_name', '')
    if tool:
        output['tool'] = tool

    tool_id = input_data.get('tool_use_id', '')
    if tool_id:
        output['tool_use_id'] = tool_id

    tool_input = input_data.get('tool_input', {})
    if tool_input:
        output['tool_input'] = tool_input

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect('$SOCKET_PATH')
        sock.sendall(json.dumps(output).encode())
        sock.close()
    except:
        pass
    "
    """

    private static let hookEvents = [
        "PreToolUse", "PostToolUse", "UserPromptSubmit",
        "Stop", "SubagentStop", "PreCompact",
        "SessionStart", "SessionEnd",
    ]

    static func install() {
        do {
            try installScript()
            try registerHooks()
        } catch {
            print("[HookInstaller] Installation failed: \(error)")
        }
    }

    // MARK: - Script Installation

    private static func installScript() throws {
        let fm = FileManager.default

        // Ensure hooks directory exists
        if !fm.fileExists(atPath: hooksDir.path) {
            try fm.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        }

        let scriptURL = hooksDir.appendingPathComponent(hookFileName)
        let existingContent = try? String(contentsOf: scriptURL, encoding: .utf8)

        // Only write if content changed
        if existingContent != hookScript {
            try hookScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        }

        // Ensure executable
        var attrs = try fm.attributesOfItem(atPath: scriptURL.path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        if perms & 0o111 == 0 {
            attrs[.posixPermissions] = 0o755
            try fm.setAttributes(attrs, ofItemAtPath: scriptURL.path)
        }
    }

    // MARK: - Hook Registration

    private static func registerHooks() throws {
        let fm = FileManager.default
        let scriptPath = hooksDir.appendingPathComponent(hookFileName).path

        // Read existing settings or start fresh
        var settings: [String: Any]
        if fm.fileExists(atPath: settingsPath.path),
           let data = try? Data(contentsOf: settingsPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = parsed
        } else {
            settings = [:]
        }

        // Build hook command
        let hookCommand: [String: Any] = [
            "type": "command",
            "command": scriptPath,
            "timeout": 5000,
        ]

        // Claude Code hook format: each event has an array of matcher groups
        // {"EventName": [{"matcher": "", "hooks": [{"type": "command", "command": "..."}]}]}
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for eventName in hookEvents {
            var matcherGroups = hooks[eventName] as? [[String: Any]] ?? []

            // Check if our hook is already registered in any matcher group
            let alreadyRegistered = matcherGroups.contains { group in
                guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    (hook["command"] as? String)?.contains(hookFileName) == true
                }
            }

            if !alreadyRegistered {
                let matcherGroup: [String: Any] = [
                    "matcher": "",
                    "hooks": [hookCommand],
                ]
                matcherGroups.append(matcherGroup)
                hooks[eventName] = matcherGroups
            }
        }

        settings["hooks"] = hooks

        // Write back
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsPath, options: .atomic)
    }
}
