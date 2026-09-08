#!/usr/bin/env bash
# Verifies everything Kestrel shells out to, and that the CLI flags it uses still exist.
# Exits non-zero if a required dependency is missing.
set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH"
FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

echo "Kestrel dependency check"
echo

echo "CLIs"
if command -v claude >/dev/null 2>&1; then
  ok "claude — $(command -v claude) ($(claude --version 2>/dev/null | head -1))"
  HELP="$(claude --help 2>&1)"
  for flag in --print --output-format --allowedTools --model; do
    grep -q -- "$flag" <<<"$HELP" || warn "claude --help no longer mentions $flag (see Sources/Kestrel/Backends/ClaudeBackend.swift)"
  done
else
  bad "claude not found — install Claude Code, then run: claude auth"
fi

if command -v codex >/dev/null 2>&1; then
  ok "codex — $(command -v codex) ($(codex --version 2>/dev/null | head -1))"
  HELP="$(codex exec --help 2>&1)"
  for flag in --sandbox --skip-git-repo-check --output-last-message --image; do
    grep -q -- "$flag" <<<"$HELP" || warn "codex exec --help no longer mentions $flag (see Sources/Kestrel/Backends/CodexBackend.swift)"
  done
else
  warn "codex not found — optional. Install with: npm i -g @openai/codex && codex login"
fi

echo
echo "Speech to text"
# macOS 26 has Apple's on-device engine built in, so whisper is only the fallback there.
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
ENGINE="$(python3 -c 'import json,os;p=os.path.expanduser("~/.kestrel/config.json");print(json.load(open(p)).get("transcriptionEngine","apple") if os.path.exists(p) else "apple")' 2>/dev/null || echo apple)"
if [ "$MAJOR" -ge 26 ] && [ "$ENGINE" = "apple" ]; then
  ok "Apple speech engine — built into macOS $(sw_vers -productVersion), nothing to install"
  WHISPER_REQUIRED=0
else
  [ "$MAJOR" -ge 26 ] && warn "config sets transcriptionEngine=whisper; Apple's engine is available on this Mac" \
                      || warn "macOS $(sw_vers -productVersion) — Apple's speech engine needs macOS 26; using whisper"
  WHISPER_REQUIRED=1
fi

WHISPER="$(command -v whisper-cli || true)"
MODEL="$HOME/.kestrel/models/ggml-base.en.bin"
if [ "$WHISPER_REQUIRED" -eq 1 ]; then
  [ -n "$WHISPER" ] && ok "whisper-cli — $WHISPER" || bad "whisper-cli not found — brew install whisper-cpp"
  [ -f "$MODEL" ] && ok "model — $MODEL ($(du -h "$MODEL" | cut -f1))" \
                  || bad "model missing — ./scripts/download-whisper-model.sh"
elif [ -n "$WHISPER" ]; then
  ok "whisper-cli also present — $WHISPER (fallback)"
fi

echo
echo "User data"
[ -d "$HOME/.kestrel" ] && ok "~/.kestrel exists" || warn "~/.kestrel will be created on first launch"
[ -f "$HOME/.kestrel/KESTREL.md" ] && ok "memory file present" || warn "memory file seeded on first launch"

echo
[ "$FAIL" -eq 0 ] && echo "All required dependencies present." || echo "Missing required dependencies (see ✗ above)."
exit $FAIL
