# Kokoro TTS Server (in-repo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `tts` module's Kokoro path self-contained by bringing the server program into `tts/kokoro-server/` and rewiring the installer to drop the private `speed-reader` source path.

**Architecture:** Add `tts/kokoro-server/{server.py,requirements.txt,Dockerfile}` (verbatim). Rewire `tts/scripts/tts-kokoro-install.sh` to require the server files pre-placed in `INSTALL_DIR` (overridable via `KOKORO_INSTALL_DIR`, default `~/.claude/services/kokoro`) instead of copying from the external project. Update `tts/INSTALL.md` + README.

**Tech Stack:** bash, Python 3.10–3.12, FastAPI/uvicorn, the `kokoro` PyPI package (Kokoro-82M), launchd; optional Docker.

**Source of truth for copied files:** `~/Projects/personal/speed-reader/speeder/kokoro-server/{server.py,requirements.txt,Dockerfile}`. Repo: `~/Projects/personal/claude-setup`, branch `feat/kokoro-server`, base `1879354`.

---

## File Structure

```
tts/
├── kokoro-server/          # NEW
│   ├── server.py           # verbatim
│   ├── requirements.txt    # verbatim
│   └── Dockerfile          # verbatim
├── scripts/
│   └── tts-kokoro-install.sh   # rewired (3 edits)
└── INSTALL.md              # Kokoro bullet expanded
README.md                   # deps line + new Notice
```

---

## Task 1: Add the Kokoro server program

**Files:**
- Create: `tts/kokoro-server/server.py`
- Create: `tts/kokoro-server/requirements.txt`
- Create: `tts/kokoro-server/Dockerfile`

- [ ] **Step 1: Copy the three files verbatim**

```bash
cd ~/Projects/personal/claude-setup
mkdir -p tts/kokoro-server
SRC="$HOME/Projects/personal/speed-reader/speeder/kokoro-server"
cp "$SRC/server.py"        tts/kokoro-server/server.py
cp "$SRC/requirements.txt" tts/kokoro-server/requirements.txt
cp "$SRC/Dockerfile"       tts/kokoro-server/Dockerfile
```

- [ ] **Step 2: Verify byte-identical + clean of personal data**

```bash
cd ~/Projects/personal/claude-setup
SRC="$HOME/Projects/personal/speed-reader/speeder/kokoro-server"
for f in server.py requirements.txt Dockerfile; do
  diff "tts/kokoro-server/$f" "$SRC/$f" >/dev/null && echo "$f: IDENTICAL" || echo "$f: DIFF"
done
grep -rnI -e bernardo -e belen -e speed-reader -e /Users/ tts/kokoro-server/ && echo "FAIL: personal string" || echo "CLEAN"
```
Expected: three `IDENTICAL` lines, then `CLEAN`.

> Do NOT commit — the controller commits.

---

## Task 2: Rewire the installer

**Files:**
- Modify: `tts/scripts/tts-kokoro-install.sh`

- [ ] **Step 1: Replace the header comment + SOURCE_DIR/INSTALL_DIR block**

Replace EXACTLY:
```bash
# tts-kokoro-install.sh — Set up the dedicated Kokoro TTS server install
# under ~/.claude/services/kokoro/. Idempotent: safe to re-run to upgrade
# pip deps or re-copy the latest server.py.
set -e

SOURCE_DIR="$HOME/Projects/personal/speed-reader/speeder/kokoro-server"
INSTALL_DIR="$HOME/.claude/services/kokoro"
```
with:
```bash
# tts-kokoro-install.sh — Set up the dedicated Kokoro TTS server install
# under ~/.claude/services/kokoro/. Requires server.py + requirements.txt to be
# present in the install dir first (copy them from tts/kokoro-server/).
# Idempotent: safe to re-run to upgrade pip deps or rebuild the venv.
# Override the target dir with KOKORO_INSTALL_DIR (used for testing).
set -e

INSTALL_DIR="${KOKORO_INSTALL_DIR:-$HOME/.claude/services/kokoro}"
```

- [ ] **Step 2: Replace the SOURCE_DIR pre-flight with a files-present check**

Replace EXACTLY:
```bash
# --- Pre-flight ---
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: Kokoro source dir not found at $SOURCE_DIR" >&2
  echo "       Cannot continue without speed-reader's server.py." >&2
  exit 1
fi
```
with:
```bash
# --- Pre-flight: server files must already be staged in INSTALL_DIR ---
if [ ! -f "$INSTALL_DIR/server.py" ] || [ ! -f "$INSTALL_DIR/requirements.txt" ]; then
  echo "ERROR: Kokoro server files not found in $INSTALL_DIR" >&2
  echo "       Copy them there first:" >&2
  echo "         mkdir -p \"$INSTALL_DIR\"" >&2
  echo "         cp tts/kokoro-server/server.py tts/kokoro-server/requirements.txt \"$INSTALL_DIR\"/" >&2
  exit 1
fi
```

- [ ] **Step 3: Remove the Layout copy block**

Replace EXACTLY:
```bash
# --- Layout ---
mkdir -p "$INSTALL_DIR"
echo "Copying server.py and requirements.txt from $SOURCE_DIR ..."
cp "$SOURCE_DIR/server.py"        "$INSTALL_DIR/server.py"
cp "$SOURCE_DIR/requirements.txt" "$INSTALL_DIR/requirements.txt"

# --- Virtualenv ---
```
with:
```bash
# --- Virtualenv ---
```

- [ ] **Step 4: Syntax check + confirm no personal coupling remains**

```bash
cd ~/Projects/personal/claude-setup
bash -n tts/scripts/tts-kokoro-install.sh && echo "SYNTAX OK"
grep -nE "speed-reader|SOURCE_DIR|bernardo" tts/scripts/tts-kokoro-install.sh && echo "FAIL: coupling remains" || echo "DECOUPLED"
```
Expected: `SYNTAX OK`, then `DECOUPLED`.

> Do NOT commit — the controller commits.

---

## Task 3: Docs — INSTALL.md Kokoro step + README

**Files:**
- Modify: `tts/INSTALL.md`
- Modify: `README.md`

- [ ] **Step 1: Expand the Kokoro bullet in `tts/INSTALL.md`**

Replace EXACTLY:
```markdown
- **Kokoro voices:** `bash ~/.claude/scripts/tts-kokoro-install.sh` (sets up a
  launchd-managed Kokoro server at `http://127.0.0.1:8321`). Uninstall:
  `tts-kokoro-uninstall.sh`.
```
with:
````markdown
- **Kokoro voices (higher quality):** requires Python 3.10–3.12
  (`brew install python@3.12`). Stage the server, then build it:
  ```bash
  mkdir -p ~/.claude/services/kokoro
  cp tts/kokoro-server/server.py tts/kokoro-server/requirements.txt ~/.claude/services/kokoro/
  bash ~/.claude/scripts/tts-kokoro-install.sh                 # build venv + start.sh, smoke-test
  bash ~/.claude/scripts/tts-kokoro-install.sh --with-launchd  # optional: run as a login service
  ```
  First run downloads the Kokoro-82M model (~hundreds of MB, cached). The server
  listens on `http://127.0.0.1:8321`; `tts-speak.sh` uses it automatically and
  falls back to Apple `say`. Tune `TTS_KOKORO_VOICE` / `TTS_KOKORO_SPEED` in
  `~/.claude/tts.conf`. Uninstall: `bash ~/.claude/scripts/tts-kokoro-uninstall.sh`
  then `rm -rf ~/.claude/services/kokoro`. Alternative: `tts/kokoro-server/Dockerfile`
  builds a container serving on port 7860.
````

- [ ] **Step 2: Update the README tts dependency line**

Replace EXACTLY:
```markdown
- tts: macOS (`say`, `afplay`), `python3`; optional Kokoro server, OpenRouter key,
  Karabiner-Elements (stop hotkeys).
```
with:
```markdown
- tts: macOS (`say`, `afplay`), `python3`; optional Kokoro server (needs Python
  3.10–3.12), OpenRouter key, Karabiner-Elements (stop hotkeys).
```

- [ ] **Step 3: Add a Kokoro Notice to the README**

Find EXACTLY:
```markdown
- `cc.icns` is the Claude logo (an Anthropic mark), included only for personal use
  to brand local notifications. Not affiliated with or endorsed by Anthropic.
```
and add immediately after it:
```markdown
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) and the `kokoro` PyPI
  package are Apache-2.0. `tts/kokoro-server/server.py` is a thin local FastAPI
  wrapper; the model weights download at runtime and are not committed.
```

- [ ] **Step 4: Verify the edits landed**

```bash
cd ~/Projects/personal/claude-setup
grep -q "cp tts/kokoro-server/server.py" tts/INSTALL.md && echo "INSTALL: PASS" || echo "INSTALL: FAIL"
grep -q "needs Python" README.md && echo "DEPS: PASS" || echo "DEPS: FAIL"
grep -q "Kokoro-82M" README.md && echo "NOTICE: PASS" || echo "NOTICE: FAIL"
```
Expected: `INSTALL: PASS`, `DEPS: PASS`, `NOTICE: PASS`.

> Do NOT commit — the controller commits.

---

## Task 4: Verification

VERIFICATION ONLY — no production files; never touch the live `~/.claude/services/kokoro` (all tests use a temp `KOKORO_INSTALL_DIR`).

**Files:** none

- [ ] **Step 1: Missing-files guard exits cleanly with the NEW message**

```bash
cd ~/Projects/personal/claude-setup
T=$(mktemp -d)
OUT=$(KOKORO_INSTALL_DIR="$T" bash tts/scripts/tts-kokoro-install.sh 2>&1); rc=$?
printf '%s\n' "$OUT"; echo "exit=$rc"
[ "$rc" -ne 0 ] && echo "EXIT NONZERO: PASS" || echo "EXIT NONZERO: FAIL"
printf '%s' "$OUT" | grep -q "server files not found" && echo "NEW MSG: PASS" || echo "NEW MSG: FAIL"
printf '%s' "$OUT" | grep -qi "speed-reader" && echo "OLD PATH LEAK: FAIL" || echo "NO OLD PATH: PASS"
rm -rf "$T"
```
Expected: nonzero exit, `NEW MSG: PASS`, `NO OLD PATH: PASS`.

- [ ] **Step 2: Files-present path passes the guard and reaches Python detection**

Stage the files in a temp dir and run with a fake `python3` that reports an incompatible version (3.13), so detection deterministically fails AFTER the file-check — proving the guard passed without triggering the slow `pip install`.

```bash
cd ~/Projects/personal/claude-setup
T=$(mktemp -d); FAKEBIN=$(mktemp -d)
cp tts/kokoro-server/server.py tts/kokoro-server/requirements.txt "$T/"
printf '#!/bin/bash\n[ "$1" = "-c" ] && echo "3.13"\n' > "$FAKEBIN/python3"; chmod +x "$FAKEBIN/python3"
OUT=$(KOKORO_INSTALL_DIR="$T" PATH="$FAKEBIN:/usr/bin:/bin" bash tts/scripts/tts-kokoro-install.sh 2>&1); rc=$?
printf '%s\n' "$OUT"; echo "exit=$rc"
printf '%s' "$OUT" | grep -q "server files not found" && echo "GUARD WRONGLY TRIPPED: FAIL" || echo "GUARD PASSED: PASS"
printf '%s' "$OUT" | grep -q "no compatible python" && echo "REACHED PYTHON DETECT: PASS" || echo "REACHED PYTHON DETECT: FAIL"
rm -rf "$T" "$FAKEBIN"
```
Expected: `GUARD PASSED: PASS` and `REACHED PYTHON DETECT: PASS`. (This proves control flow reaches the unchanged venv/pip logic once files are present.)

- [ ] **Step 3: Final sanity**

```bash
cd ~/Projects/personal/claude-setup
grep -rnI -e bernardo -e speed-reader -e SOURCE_DIR tts/kokoro-server tts/scripts/tts-kokoro-install.sh && echo "FAIL" || echo "CLEAN"
git status --short
```
Expected: `CLEAN`; `git status` shows new `tts/kokoro-server/` + modified `tts/scripts/tts-kokoro-install.sh`, `tts/INSTALL.md`, `README.md` (controller commits these).

- [ ] **Step 4 (OPTIONAL, slow — controller offers, not run by default): live smoke**

Only if the user opts in (downloads the Kokoro-82M model, builds a venv):
```bash
T=$(mktemp -d)
cp ~/Projects/personal/claude-setup/tts/kokoro-server/server.py \
   ~/Projects/personal/claude-setup/tts/kokoro-server/requirements.txt "$T/"
KOKORO_INSTALL_DIR="$T" bash ~/Projects/personal/claude-setup/tts/scripts/tts-kokoro-install.sh   # builds venv (slow)
"$T/start.sh" &   # start server on 127.0.0.1:8321
# wait for readiness, then:
curl -fsS http://127.0.0.1:8321/voices | jq '.voices | length'   # expect a positive count
# cleanup: kill the start.sh server, rm -rf "$T"
```

---

## Self-Review

**Spec coverage:**
- Bring server.py/requirements.txt/Dockerfile into `tts/kokoro-server/` → Task 1. ✓
- Rewire installer: drop SOURCE_DIR, require files in INSTALL_DIR, `KOKORO_INSTALL_DIR` override, keep everything else → Task 2 (3 edits) + Step 1 override. ✓
- INSTALL.md Kokoro step (copy → install → optional launchd, Python prereq, Docker note, uninstall) → Task 3 Step 1. ✓
- README deps + Apache-2.0 Notice → Task 3 Steps 2–3. ✓
- Verification: missing-files guard, files-present path, no speed-reader/bernardo, byte-identical, bash -n → Tasks 1–2 + Task 4. Optional live smoke → Task 4 Step 4. ✓
- Out of scope (model weights, .venv/__pycache__, server redesign) → respected (only 3 files copied). ✓

**Placeholder scan:** No TBD/TODO; all edits show exact old→new; copied files use exact `cp`; verification commands are concrete with expected output.

**Consistency:** `INSTALL_DIR`/`KOKORO_INSTALL_DIR`, `SERVER_PORT=8321`, and the install path `~/.claude/services/kokoro` are consistent across the installer, INSTALL.md, and the verification steps. The INSTALL.md copy command (`cp tts/kokoro-server/server.py tts/kokoro-server/requirements.txt ~/.claude/services/kokoro/`) matches the installer's required files.
