# Session Context

## User Prompts

### Prompt 1

some general complaints looking to do a /skillserver jason refactor to address. 

floating pill doesnt provide a way to navigate back to the book screen
book screen should provide a filter to hide read chapters by default (user can show if they want)

### Prompt 2

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

### Prompt 3

proceed

### Prompt 4

proceed

### Prompt 5

go, q1 progress is determined by current chapter only (chapters before current chapter are considered read). q2 not sure do whats best. q3 ok

