---
description: Show consolidator status for the current Claude Code session, or a target session by id
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Show ON/OFF, the resolved memory directory, file/trash counts, the cursor state, the last LLM response, recent metrics, and engine reachability.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/consolidator-status-impl.sh $ARGUMENTS
```
