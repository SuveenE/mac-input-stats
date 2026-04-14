import Foundation

/// Installs hook scripts and registers them in settings for Claude Code and Cursor.
enum HookInstaller {
    private static let claudeHookFileName = "claude-activity-hook.sh"
    private static let cursorHookFileName = "cursor-activity-hook.sh"

    private static var claudeHooksDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks")
    }

    private static var claudeSettingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private static var cursorHooksPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
    }

    // MARK: - Claude Code Hook Script

    private static let claudeHookScript = """
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

    // MARK: - Cursor Hook Script

    private static let cursorHookScript = """
    #!/bin/bash
    # Cursor activity hook - forwards events via Unix socket to notchi
    # Mirrors claude-activity-hook.sh but maps Cursor events to ClaudeEventType

    SOCKET_PATH="/tmp/notchi.sock"

    # Exit silently if socket doesn't exist (app not running)
    [ -S "$SOCKET_PATH" ] || { cat > /dev/null 2>&1; exit 0; }

    # Stable session ID: hash of workspace path + today's date so it persists
    # across hook invocations but resets daily
    SESSION_ID="cursor-$(echo "${PWD}-$(date +%Y-%m-%d)" | shasum | cut -c1-12)"

    EVENT_TYPE="$1"

    # Pass stdin directly to Python (avoids shell injection from $INPUT variable)
    /usr/bin/python3 -c "
    import json
    import os
    import socket
    import sys

    event_type = '$EVENT_TYPE'

    # Map Cursor events to ClaudeEventType values that the app can decode
    event_map = {
        'beforeSubmitPrompt': 'UserPromptSubmit',
        'afterFileEdit': 'PostToolUse',
        'stop': 'Stop',
        'beforeReadFile': 'PreToolUse',
        'beforeShellExecution': 'PreToolUse',
        'beforeMCPExecution': 'PreToolUse'
    }

    mapped_event = event_map.get(event_type)
    if not mapped_event:
        sys.exit(0)

    status_map = {
        'UserPromptSubmit': 'processing',
        'PostToolUse': 'processing',
        'Stop': 'waiting_for_input',
        'PreToolUse': 'running_tool'
    }

    output = {
        'session_id': '$SESSION_ID',
        'cwd': os.getcwd(),
        'event': mapped_event,
        'status': status_map.get(mapped_event, 'unknown'),
        'pid': None,
        'tty': None,
        'interactive': True
    }

    # Try to parse Cursor's JSON input from stdin for extra context
    try:
        input_data = json.load(sys.stdin)
        if isinstance(input_data, dict):
            # Extract prompt for word counting on submit events
            for key in ('prompt', 'message', 'content', 'text', 'query'):
                if key in input_data and isinstance(input_data[key], str):
                    output['user_prompt'] = input_data[key]
                    break
            if 'filePath' in input_data:
                output['tool'] = 'Read'
                output['tool_input'] = {'file': input_data['filePath']}
            if 'command' in input_data:
                output['tool'] = 'Bash'
                output['tool_input'] = {'command': input_data['command']}
    except:
        pass

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect('$SOCKET_PATH')
        sock.sendall(json.dumps(output).encode())
        sock.close()
    except:
        pass
    "
    """

    // MARK: - Hook Events

    private static let claudeHookEvents = [
        "PreToolUse", "PostToolUse", "UserPromptSubmit",
        "Stop", "SubagentStop", "PreCompact",
        "SessionStart", "SessionEnd",
    ]

    private static let cursorHookEvents = [
        "beforeSubmitPrompt", "stop", "afterFileEdit",
        "beforeReadFile", "beforeShellExecution", "beforeMCPExecution",
    ]

    // MARK: - Public API

    static func install() {
        do {
            try installScript(fileName: claudeHookFileName, content: claudeHookScript, dir: claudeHooksDir)
            try registerClaudeHooks()
        } catch {
            print("[HookInstaller] Claude hook installation failed: \(error)")
        }

        do {
            try installScript(fileName: cursorHookFileName, content: cursorHookScript, dir: claudeHooksDir)
            try registerCursorHooks()
        } catch {
            print("[HookInstaller] Cursor hook installation failed: \(error)")
        }
    }

    // MARK: - Script Installation

    private static func installScript(fileName: String, content: String, dir: URL) throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let scriptURL = dir.appendingPathComponent(fileName)
        let existingContent = try? String(contentsOf: scriptURL, encoding: .utf8)

        if existingContent != content {
            try content.write(to: scriptURL, atomically: true, encoding: .utf8)
        }

        var attrs = try fm.attributesOfItem(atPath: scriptURL.path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        if perms & 0o111 == 0 {
            attrs[.posixPermissions] = 0o755
            try fm.setAttributes(attrs, ofItemAtPath: scriptURL.path)
        }
    }

    // MARK: - Claude Code Hook Registration

    private static func registerClaudeHooks() throws {
        let fm = FileManager.default
        let scriptPath = claudeHooksDir.appendingPathComponent(claudeHookFileName).path

        var settings: [String: Any]
        if fm.fileExists(atPath: claudeSettingsPath.path),
           let data = try? Data(contentsOf: claudeSettingsPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = parsed
        } else {
            settings = [:]
        }

        let hookCommand: [String: Any] = [
            "type": "command",
            "command": scriptPath,
            "timeout": 5000,
        ]

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var needsWrite = false

        for eventName in claudeHookEvents {
            var matcherGroups = hooks[eventName] as? [[String: Any]] ?? []

            let alreadyRegistered = matcherGroups.contains { group in
                guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    (hook["command"] as? String)?.contains(claudeHookFileName) == true
                }
            }

            if !alreadyRegistered {
                let matcherGroup: [String: Any] = [
                    "matcher": "",
                    "hooks": [hookCommand],
                ]
                matcherGroups.append(matcherGroup)
                hooks[eventName] = matcherGroups
                needsWrite = true
            }
        }

        guard needsWrite else { return }

        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeSettingsPath, options: .atomic)
    }

    // MARK: - Cursor Hook Registration

    private static func registerCursorHooks() throws {
        let fm = FileManager.default
        let scriptPath = claudeHooksDir.appendingPathComponent(cursorHookFileName).path

        // Read existing hooks.json or start fresh
        var root: [String: Any]
        if fm.fileExists(atPath: cursorHooksPath.path),
           let data = try? Data(contentsOf: cursorHooksPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            root = parsed
        } else {
            root = ["version": 1]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var needsWrite = false

        for eventName in cursorHookEvents {
            var entries = hooks[eventName] as? [[String: Any]] ?? []

            let alreadyRegistered = entries.contains { entry in
                (entry["command"] as? String)?.contains(cursorHookFileName) == true
            }

            if !alreadyRegistered {
                entries.append([
                    "command": "\(scriptPath) \(eventName)",
                ])
                hooks[eventName] = entries
                needsWrite = true
            }
        }

        guard needsWrite else { return }

        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: cursorHooksPath, options: .atomic)
    }
}
