# AI integrations

LaunchScope ships a local stdio MCP server and a repository skill. MCP is the cross-client capability surface; the skill and agent pointer files teach repository-aware agents when and how to use it.

## What AI can do

The launchscope MCP server exposes:

- launchscope_get_status: inspect local snapshot and Rule Pack availability.
- launchscope_list_background_items: query the latest privacy-limited snapshot.
- launchscope_list_recent_changes: inspect locally recorded changes.
- launchscope_get_installed_rules: read the installed Rule Pack.
- launchscope_validate_rule_pack: validate a candidate without writing.
- launchscope_plan_rule_pack: preview added, updated and unchanged rules without writing.
- launchscope_save_rule_pack_candidate: save a validated candidate into LaunchScope's Candidates directory after the user explicitly asks.

It also exposes the Agent Protocol, Rule Pack JSON Schema and current privacy-limited snapshot as MCP resources, plus an identify-background-item prompt.

The MCP server cannot install rules or start, stop, enable or disable launchd items. Rule installation must be reviewed in LaunchScope, and launchd management remains behind the app's confirmation and state-readback flow.

## Configure from the app

Open the top-level **AI 助手** destination in LaunchScope's sidebar. The app checks a bounded list of known application and configuration locations for Codex, Claude Code, Cursor and Claude Desktop; it never searches the whole home directory.

For Codex and Claude Code, LaunchScope uses the discovered client CLI to register the server. For Cursor and Claude Desktop, it merges only `mcpServers.launchscope` into the existing JSON object. Before any write, LaunchScope shows the exact target and asks for confirmation. Existing files are backed up, unrelated keys and MCP servers are preserved, repeated application is idempotent, and malformed configuration is rejected without overwrite. Copy-only configuration remains available as a fallback.

## Run from a source checkout

    ./scripts/launchscope-mcp

Claude Code can discover the checked-in .mcp.json. Cursor can discover .cursor/mcp.json. Both point to the same server.

## Connect an installed app

The build bundles the server and protocol assets under:

    /Applications/LaunchScope.app/Contents/Resources/LaunchScopeAI/

### Codex

    codex mcp add launchscope -- /usr/bin/python3 \
      /Applications/LaunchScope.app/Contents/Resources/LaunchScopeAI/launchscope_mcp.py

### Claude Code

    claude mcp add --scope user launchscope -- /usr/bin/python3 \
      /Applications/LaunchScope.app/Contents/Resources/LaunchScopeAI/launchscope_mcp.py

### Cursor

Add this to ~/.cursor/mcp.json:

    {
      "mcpServers": {
        "launchscope": {
          "command": "/usr/bin/python3",
          "args": [
            "/Applications/LaunchScope.app/Contents/Resources/LaunchScopeAI/launchscope_mcp.py"
          ]
        }
      }
    }

Other MCP clients can use the same command and argument. The server requires no Python packages and performs no network requests.

## Agent discovery

- AGENTS.md points Codex-compatible agents to the protocol and repository skill.
- CLAUDE.md gives Claude Code the same single source of truth.
- .cursor/rules/launchscope.mdc provides a scoped Cursor rule.
- llms.txt is a lightweight index for other agents and documentation tools.

These files contain pointers rather than copies of the protocol. The authoritative behavior remains in docs/AGENT_PROTOCOL.md.
