# Session Context

## User Prompts

### Prompt 1

theme selector stopped working

### Prompt 2

Base directory for this skill: /home/noah/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/systematic-debugging

# Systematic Debugging

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

**Violating the letter of this process is violating the spirit of debugging.**

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FI...

### Prompt 3

clicking a theme in the selector does not change the theme

### Prompt 4

commit push deploy

### Prompt 5

autoplay brought me from ch 797 to 798 but didnt start audio playback of 798. additionally i cannot manually play the audio it shows 00:00/00:00

### Prompt 6

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

