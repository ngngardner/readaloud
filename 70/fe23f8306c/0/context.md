# Session Context

## User Prompts

### Prompt 1

Base directory for this skill: /home/noah/.claude/skills/skillserver

# Skillserver Bridge

Interact with the MCP skillserver (served over LiteLLM gateway on `pylon:4100`)
to list, search, and invoke skills hosted there. Works from any project —
requires only the `litellm-gateway` MCP server to be connected.

## Setup: load the MCP tools

The skillserver MCP tools are deferred. Before doing anything else, load them:

```
ToolSearch query: "+skillserver"
```

This exposes:

- `mcp__litellm-gat...

