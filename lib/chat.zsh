# lib/chat.zsh — per-terminal chat session (follow-up context).

AI_CHAT_DIR="${AI_CHAT_DIR:-$HOME/.config/ai-terminal/sessions}"
AI_CHAT_ID="${AI_CHAT_ID:-$PPID}"
AI_CHAT_MAX_TURNS="${AI_CHAT_MAX_TURNS:-10}"

_ai_chat_path() { printf "%s/chat-%s.md" "$AI_CHAT_DIR" "$AI_CHAT_ID"; }

_ai_chat_load() {
  local p
  p=$(_ai_chat_path)
  [[ -f "$p" ]] || return 0
  local content
  content=$(cat "$p" 2>/dev/null)
  [[ -z "$content" ]] && return 0
  printf "CONVERSATION SO FAR (prior turns this session — use as context for follow-ups):\n%s\n\n" "$content"
}

_ai_chat_append() {
  local role="$1"; shift
  local text="$*"
  local p
  p=$(_ai_chat_path)
  mkdir -p "$(dirname "$p")"
  printf -- "[%s]\n%s\n\n" "$role" "$text" >> "$p"
  local total
  total=$(grep -c "^\[" "$p" 2>/dev/null || echo 0)
  if (( total > AI_CHAT_MAX_TURNS * 2 )); then
    local keep=$((AI_CHAT_MAX_TURNS * 2))
    awk -v keep="$keep" '
      /^\[/ { entries[++c] = NR }
      { lines[NR] = $0; last = NR }
      END {
        start = entries[c - keep + 1]
        if (!start) start = 1
        for (i = start; i <= last; i++) print lines[i]
      }
    ' "$p" > "${p}.tmp" && mv "${p}.tmp" "$p"
  fi
}

_ai_chat_show() {
  local p
  p=$(_ai_chat_path)
  echo "=== CHAT: $p ==="
  if [[ -f "$p" ]]; then cat "$p"; else echo "(empty — no turns yet this session)"; fi
}

_ai_chat_reset() {
  local p
  p=$(_ai_chat_path)
  if [[ -f "$p" ]]; then
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    mv "$p" "${p}.archived-${ts}"
    echo "[ai] chat reset (archived: ${p}.archived-${ts})"
  else
    echo "[ai] no chat to reset"
  fi
}

# Extract last [assistant] block from chat file.
_ai_chat_last_assistant() {
  local p
  p=$(_ai_chat_path)
  [[ -f "$p" ]] || return 1
  awk '
    /^\[assistant\]/ { capture=1; buf=""; next }
    /^\[user\]/      { capture=0 }
    capture          { buf = buf $0 ORS }
    END              { printf "%s", buf }
  ' "$p"
}
