# Design: in-repo Kokoro TTS server (under the `tts` module)

**Date:** 2026-05-29
**Status:** Approved (design); pending spec review
**Repo:** `~/Projects/personal/claude-setup` (public)

## Goal

Make the `tts` module's optional Kokoro path self-contained. Today the repo's
`tts/scripts/tts-kokoro-install.sh` copies the server program from a **private**
external project (`~/Projects/personal/speed-reader/speeder/kokoro-server`), so the
public installer cannot work for anyone else. Bring the Kokoro server program into
the repo under the `tts` module and rewire the installer to use it.

## What the Kokoro server is

A minimal FastAPI app (`server.py`, ~251 lines) wrapping the Kokoro-82M TTS model:
- `GET /voices` — list available voices.
- `POST /synthesize` — text → base64 WAV (24 kHz) + per-word timestamps.
It is started on `127.0.0.1:8321` via a generated `start.sh` (uvicorn). The model
weights are NOT files in the repo — the `kokoro` pip package downloads Kokoro-82M
on first use (cached by Hugging Face). `tts-speak.sh` already calls this server at
`TTS_KOKORO_URL` (default `http://127.0.0.1:8321`) and falls back to macOS `say`.

`server.py`, `requirements.txt`, and `Dockerfile` were verified clean of personal
data and are copied verbatim.

## Approaches

- **(A) In-repo under `tts/` — CHOSEN.** Add `tts/kokoro-server/`; INSTALL.md
  copies it into `~/.claude/services/kokoro/`, then the rewired installer builds the
  venv there. Self-contained; stays "referred by the tts module."
- (B) Separate top-level module — rejected (it belongs to tts).
- (C) Git submodule the speed-reader project — rejected (re-couples to a private
  repo, defeats self-containment).

## Repo structure

```
tts/
├── kokoro-server/
│   ├── server.py          # verbatim — FastAPI wrapper (/voices, /synthesize)
│   ├── requirements.txt   # verbatim — kokoro>=0.9.2, fastapi, uvicorn, soundfile, numpy
│   └── Dockerfile         # verbatim — optional containerized / HF-Spaces run path (port 7860)
├── scripts/
│   └── tts-kokoro-install.sh   # rewired (see below)
└── INSTALL.md             # updated Kokoro optional step
```

## Installer rewire (the one code change)

In `tts/scripts/tts-kokoro-install.sh`:
- Remove `SOURCE_DIR="$HOME/Projects/personal/speed-reader/speeder/kokoro-server"`.
- Remove the pre-flight that checks `SOURCE_DIR` and the `cp "$SOURCE_DIR/..."`
  step.
- Add a pre-flight that requires `server.py` and `requirements.txt` to already be
  present in `INSTALL_DIR` (`~/.claude/services/kokoro/`), erroring with guidance:
  "copy `tts/kokoro-server/{server.py,requirements.txt}` into `~/.claude/services/kokoro/`
  first" if missing.
- Everything else is unchanged: Python 3.10–3.12 detection, venv creation,
  `pip install -r requirements.txt`, generated `start.sh`, optional
  `--with-launchd` agent + `/voices` readiness poll, `INSTALL_DIR`,
  `SERVER_PORT=8321`, and the already-genericized `PLIST_LABEL="com.claude.tts-kokoro"`.

The installer remains idempotent and keeps its `--with-launchd` argument semantics
(so `$1` is not repurposed).

## INSTALL.md — the Kokoro optional step

Replace the current Kokoro bullet with explicit, agent-followable steps:

```bash
# Requires Python 3.10–3.12  (brew install python@3.12)
mkdir -p ~/.claude/services/kokoro
cp tts/kokoro-server/server.py tts/kokoro-server/requirements.txt ~/.claude/services/kokoro/
bash ~/.claude/scripts/tts-kokoro-install.sh                # build venv + start.sh, then smoke-test start.sh
bash ~/.claude/scripts/tts-kokoro-install.sh --with-launchd  # optional: run as a login service (auto-start)
```

Notes documented in INSTALL.md:
- First run downloads Kokoro-82M (~hundreds of MB, cached); subsequent runs are
  fast.
- Voice/speed are configured in `~/.claude/tts.conf` (`TTS_KOKORO_VOICE`,
  `TTS_KOKORO_SPEED`, `TTS_KOKORO_URL`) — already created by `tts-enable`.
- Uninstall: `tts-kokoro-uninstall.sh` (removes the launchd agent); then
  `rm -rf ~/.claude/services/kokoro` to delete the venv + server.
- Alternative: `tts/kokoro-server/Dockerfile` builds a container that serves on
  port 7860 (e.g. for HF Spaces or Docker) instead of the venv+launchd path.

## README

Add a **Notice**: Kokoro-82M and the `kokoro` package are Apache-2.0; `server.py`
is a thin local wrapper; model weights download at runtime and are not committed.
The `tts` dependency line already mentions the optional Kokoro server; extend it to
note Python 3.10–3.12 is required for it.

## Verification plan

Automated (fast, no model download):
- `bash -n tts/scripts/tts-kokoro-install.sh`.
- **Missing-files guard:** point `INSTALL_DIR` at an empty temp dir (via a temporary
  copy of the script with `INSTALL_DIR` overridden, or by running in a sandbox
  HOME) and confirm it exits non-zero with the "copy the server files first"
  message — NOT a reference to the old speed-reader path.
- **Files-present path:** with `server.py`+`requirements.txt` placed in the temp
  `INSTALL_DIR`, confirm the script passes the file-check and reaches Python
  detection (stop before the slow `pip install` — e.g. by inspection or a guarded
  dry run).
- `grep -rnI "speed-reader\|bernardo" tts/scripts/tts-kokoro-install.sh tts/kokoro-server` → clean.
- `server.py`/`requirements.txt`/`Dockerfile` byte-identical to source.

Optional live smoke (slow, downloads model) — offered after the automated pass, not
run by default: place the files, run the installer, start the server, `curl
/voices` returns a non-empty list.

To keep the automated guard test from clobbering the user's working
`~/.claude/services/kokoro`, the installer will support an overridable
`INSTALL_DIR` via environment variable (`KOKORO_INSTALL_DIR`), defaulting to
`~/.claude/services/kokoro`. This is a small, safe addition that also aids testing.

## Out of scope

- Redesigning `server.py` or its API.
- Committing model weights (downloaded at runtime).
- Other speed-reader files (`.venv`, `__pycache__`, unrelated project code).

## Open questions

None blocking.
