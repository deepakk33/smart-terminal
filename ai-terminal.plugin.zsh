# ai-terminal.plugin.zsh
# Local AI terminal: sgpt + Ollama + agentic loop. Hotkey: Ctrl+G.
#   - Empty buffer + Ctrl+G : seed "ai " prefix, type query, Enter -> agentic loop.
#   - Non-empty buffer + Ctrl+G : single-shot sgpt buffer replace.
# Helpers: explain <cmd>, fix, ai <query>, aictx.

# --- Single-shot widget (non-empty buffer) ---------------------------------
_sgpt_zsh() {
  if [[ -n "$BUFFER" ]]; then
    _sgpt_prev_cmd=$BUFFER
    BUFFER+="⌛"
    zle -I && zle redisplay
    BUFFER=$(sgpt --shell <<< "$_sgpt_prev_cmd" --no-interaction)
    zle end-of-line
  fi
}
zle -N _sgpt_zsh

# --- Ctrl+G dispatcher -----------------------------------------------------
_ai_widget() {
  if [[ -z "$BUFFER" ]]; then
    BUFFER="ai "
    CURSOR=${#BUFFER}
    zle redisplay
  else
    _sgpt_zsh
  fi
}
zle -N _ai_widget
bindkey '^G' _ai_widget

# --- Context probe ---------------------------------------------------------
_ai_context() {
  local out=""
  out+="OS: macOS $(sw_vers -productVersion 2>/dev/null)\n"
  out+="PWD: $(pwd)\n"
  out+="USER: $USER\n"
  out+="SHELL: zsh\n"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    out+="GIT_REPO: yes\n"
    out+="GIT_BRANCH: $(git branch --show-current 2>/dev/null)\n"
    out+="GIT_REMOTE: $(git remote -v 2>/dev/null | head -1 | awk '{print $2}')\n"
    out+="GIT_STATUS_SHORT: $(git status --porcelain 2>/dev/null | head -5 | tr '\n' ';')\n"
  else
    out+="GIT_REPO: no\n"
  fi
  out+="LS_TOP: $(ls -1 2>/dev/null | head -10 | tr '\n' ' ')\n"
  printf "%b" "$out"
}
aictx() { _ai_context; }

# --- Safety filter ---------------------------------------------------------
_ai_safe() {
  local cmd="$1"
  local danger='(^|[ ;|&])(rm|sudo|dd|mkfs|mv|chmod|chown|kill|killall|shutdown|reboot|halt|truncate|tee)( |$)'
  local danger2='>[^|&>]|>>'
  local danger3='git +(push|reset|commit|rebase|checkout|merge)'
  local danger4='(curl|wget)[^|;]*\|[^|]*(sh|bash|zsh)'
  [[ "$cmd" =~ $danger  ]] && return 1
  [[ "$cmd" =~ $danger2 ]] && return 1
  [[ "$cmd" =~ $danger3 ]] && return 1
  [[ "$cmd" =~ $danger4 ]] && return 1
  return 0
}

# --- Agentic loop ----------------------------------------------------------
ai() {
  local query="$*"
  if [[ -z "$query" ]]; then
    echo "Usage: ai <natural language query>"
    return 1
  fi
  local ctx
  ctx=$(_ai_context)
  local trace=""
  local max="${AI_MAX_ITERS:-4}"
  local i=0
  local resp="" line="" cmd="" out="" prompt=""
  local sys='You are a macOS zsh assistant operating an agentic loop on the user'\''s machine.
You CAN and SHOULD execute read-only shell commands via RUN to gather real data, then ANSWER with the actual result (not just a command).
Use repo/OS context. If GIT_REPO=yes and the query mentions logs/history/changes, prefer git commands.

Reply with EXACTLY ONE line, prefixed by one of:
  RUN: <single read-only shell command — used to FETCH data>
  ANSWER: <final answer derived from TRACE outputs, or, if trivially obvious without execution, a one-line shell command>

Rules:
- For factual questions about THIS machine ("how many files", "which is biggest", "what branch am I on", "what does X contain"), ALWAYS RUN first to get real data, then ANSWER with the actual value from TRACE.
- Only ANSWER directly (no RUN) when the user is asking "what command would do X" or the answer is generic.
- Disallowed in RUN: rm, sudo, mv, chmod, chown, kill, dd, mkfs, file redirects (> >>), git push/reset/commit/rebase/checkout/merge, curl|sh.
- No prose outside the prefixed line. One line only.'
  while (( i < max )); do
    prompt="${sys}

CONTEXT:
${ctx}
TRACE:
${trace:-(none)}
USER QUERY: ${query}"
    resp=$(printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null)
    line=$(printf "%s" "$resp" | grep -E '^ANSWER:' | head -1)
    [[ -z "$line" ]] && line=$(printf "%s" "$resp" | grep -E '^RUN:' | head -1)
    line="${line%% ANSWER:*}"
    line="${line%% RUN:*}"
    if [[ -z "$line" ]]; then
      echo "[ai] no structured reply, raw:"
      printf "%s\n" "$resp"
      return 1
    fi
    if [[ "$line" == ANSWER:* ]]; then
      printf "%s\n" "${line#ANSWER: }"
      return 0
    fi
    cmd="${line#RUN: }"
    if ! _ai_safe "$cmd"; then
      echo "[ai] blocked unsafe: $cmd"
      trace+="RUN_BLOCKED: $cmd
"
      ((i++)); continue
    fi
    echo "[ai] » $cmd"
    out=$(eval "$cmd" 2>&1 | head -40)
    printf "%s\n" "$out"
    trace+="RUN: $cmd
OUT: $out
---
"
    ((i++))
  done
  echo "[ai] max iters ($max) reached. Last trace:"
  printf "%b" "$trace"
}

# --- Misc helpers ----------------------------------------------------------
explain() { sgpt "explain this command: $*"; }
fix()     { eval "$(fc -ln -1)" 2>&1 | sgpt "this command failed, return only the corrected command"; }
