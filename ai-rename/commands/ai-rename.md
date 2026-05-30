---
description: Generate and apply an AI-summarized name for the current Claude Code session
allowed-tools: Bash(bash:*), Read
---

Generate a project-prefixed kebab-case name for the current session and apply it by directly editing the session metadata file.

**Before anything else, output the following banner verbatim as the very first thing in your response, then continue with the steps below:**

```
⚠️  Keep this Claude Code window focused — `/rename` keystrokes will be auto-typed in a few seconds (unless AI_RENAME_NO_KEYSTROKE is set).
```

Steps:

1. Run the collect script and parse its JSON output:

   ```bash
   bash ~/.claude/scripts/ai-rename-collect.sh
   ```

   The output looks like:

   ```json
   {
     "session_id": "...",
     "project": "funouts" | null,
     "branch": "channel-detail-bookings" | null,
     "transcript_path": "/Users/.../<session_id>.jsonl" | null,
     "user_message_count": 7,
     "user_messages": ["fix the timezone bug ...", "also handle DST ...", "..."],
     "truncated": false
   }
   ```

   **`transcript_path` is always available to you — use it freely whenever the digest doesn't clearly tell you what this session is about.** `user_messages` is a curated, capped digest of user turns (slash-command/system-reminder/task-notification wrappers stripped, each message capped at 1000 chars, total capped at 8000). Whenever you are even slightly unsure of the session's intent, `Read` `transcript_path` to see the full session JSONL — there is no penalty for reading too much; there is a real penalty for picking a bad name from thin context. **Always read the transcript when:**
   - `user_messages` is empty or contains only short/generic phrases ("yes", "ok", "go ahead", "do it"),
   - `truncated` is `true` and the visible portion doesn't make the topic obvious,
   - the messages span multiple topics and you can't tell which one was the actual work,
   - you'd otherwise have to guess.

2. Synthesize a name following these rules — do not deviate:

   - Format: `<project>/<topic>`.
   - **Do NOT add an operator prefix.** `ai-rename-persist.sh` prepends one automatically (`$AI_RENAME_PREFIX`, or your OS username by default), so emit only `<project>/<topic>`.
   - `<project>`:
     - Use the JSON `project` value when non-null.
     - When `project` is `null`, use `home`.
   - `<topic>`:
     - 2–4 kebab-case words capturing the session's intent.
     - Read `user_messages` as the session **arc**. Weigh the dominant theme across messages, not just the first — sessions often pivot mid-flight, and the last few messages frequently signal the topic that was actually worked on. The opening message is a strong hint, not a verdict.
     - If anything is ambiguous, `Read` `transcript_path` before deciding (see triggers above). Treat reading as the default, not the exception.
     - If even after reading the transcript no clear topic emerges and `branch` is set (and is not `main`, `master`, `HEAD`, or empty): kebab-case the branch (replace `/` and `_` with `-`) and use that.
     - If nothing yields a useful topic, use `exploration`.
   - Keep `<project>/<topic>` to about 40 characters or fewer. Lowercase, only `[a-z0-9-/]`, no quotes, no trailing punctuation, no leading slash. The persist script prepends the operator prefix and enforces a 50-char total.

   Examples:
   - `user_messages`: ["fix timezone bug in booking confirmation email", "also handle DST edge cases"], `project`: "funouts" → `funouts/timezone-booking-fix`
   - `user_messages`: ["look at this repo", "what's wrong?", "fix it"], `truncated`: true → read `transcript_path` to find the actual topic before naming.
   - `user_messages`: [], `project`: "omninode", `branch`: "main" → `omninode/exploration`
   - `user_messages`: [], `project`: "funouts", `branch`: "feat/qr-onboarding" → `funouts/feat-qr-onboarding`
   - `project`: null, `user_messages`: ["set up phone notifications via ntfy"] → `home/phone-notifications-ntfy`

3. Run the persist script with the generated name and relay its output verbatim:

   ```bash
   bash ~/.claude/scripts/ai-rename-persist.sh "<generated-name>"
   ```

Do not print the generated name as a separate message before calling persist — the persist script's own output is the canonical confirmation.
