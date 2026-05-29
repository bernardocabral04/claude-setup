---
description: Force one consolidator eval right now, bypassing cooldown and min-bytes gates
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Bypass the cooldown and min-new-bytes gates and run one eval immediately on whatever new transcript content has accumulated since the last eval. The cursor is still respected (only the new slice is evaluated). Useful for "save this nugget now" moments and for debugging.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/consolidator-now-impl.sh $ARGUMENTS
```
