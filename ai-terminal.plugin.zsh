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

# --- Chat session (per-terminal follow-up context) -------------------------
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
  # Cap at last AI_CHAT_MAX_TURNS * 2 entries (user + assistant per turn).
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

# --- Memory ----------------------------------------------------------------
AI_MEM_DIR="${AI_MEM_DIR:-$HOME/.config/ai-terminal}"
AI_MEM_GLOBAL="${AI_MEM_GLOBAL:-$AI_MEM_DIR/memory.md}"
AI_MEM_MAX_LINES="${AI_MEM_MAX_LINES:-200}"

_ai_mem_project_path() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  printf "%s/.ai-terminal.md" "$root"
}

_ai_mem_load() {
  local out="" g p p_content=""
  [[ -f "$AI_MEM_GLOBAL" ]] && g=$(cat "$AI_MEM_GLOBAL" 2>/dev/null)
  p=$(_ai_mem_project_path 2>/dev/null) || true
  [[ -n "$p" && -f "$p" ]] && p_content=$(cat "$p" 2>/dev/null)
  [[ -n "$g" ]] && out+="GLOBAL MEMORY (apply to every query):
${g}
"
  [[ -n "$p_content" ]] && out+="PROJECT MEMORY (apply when working in this repo):
${p_content}
"
  printf "%s" "$out"
}

_ai_mem_remember() {
  local scope=global text=""
  if [[ "$1" == "project" ]]; then
    scope=project; shift
  fi
  text="$*"
  if [[ -z "$text" ]]; then
    echo "Usage: ai [project] remember <fact>"
    return 1
  fi
  local target
  if [[ "$scope" == project ]]; then
    target=$(_ai_mem_project_path 2>/dev/null) \
      || { echo "[ai] not inside a git repo — cannot save project memory"; return 1; }
  else
    target="$AI_MEM_GLOBAL"
  fi
  mkdir -p "$(dirname "$target")"
  printf -- "- %s (%s)\n" "$text" "$(date +%Y-%m-%d)" >> "$target"
  # Cap file at AI_MEM_MAX_LINES (keep newest).
  if (( $(wc -l < "$target") > AI_MEM_MAX_LINES )); then
    tail -n "$AI_MEM_MAX_LINES" "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
  fi
  echo "[ai] remembered ($scope): $text"
  echo "[ai] -> $target"
}

_ai_mem_show() {
  echo "=== GLOBAL: $AI_MEM_GLOBAL ==="
  if [[ -f "$AI_MEM_GLOBAL" ]]; then cat "$AI_MEM_GLOBAL"; else echo "(empty)"; fi
  local p
  p=$(_ai_mem_project_path 2>/dev/null) || true
  if [[ -n "$p" ]]; then
    echo
    echo "=== PROJECT: $p ==="
    if [[ -f "$p" ]]; then cat "$p"; else echo "(empty)"; fi
  fi
}

_ai_mem_forget() {
  local pattern="$*"
  if [[ -z "$pattern" ]]; then
    echo "Usage: ai forget <substring>"
    return 1
  fi
  local removed=0 f before after
  local files=("$AI_MEM_GLOBAL")
  local p
  p=$(_ai_mem_project_path 2>/dev/null) && files+=("$p")
  for f in "${files[@]}"; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    before=$(wc -l < "$f")
    grep -v -F -- "$pattern" "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    after=$(wc -l < "$f")
    if (( before > after )); then
      removed=$(( removed + before - after ))
      echo "[ai] removed $((before-after)) line(s) from $f"
    fi
  done
  (( removed == 0 )) && echo "[ai] no matching lines"
}

# Auto-learn: extract LEARN: <fact> lines from a model response and persist them.
_ai_mem_auto_extract() {
  local resp="$1"
  [[ "${AI_AUTO_LEARN:-0}" == "1" ]] || return 0
  local fact
  printf "%s" "$resp" | awk '/^LEARN:/{sub(/^LEARN: */,""); print}' | while IFS= read -r fact; do
    [[ -z "$fact" ]] && continue
    _ai_mem_remember "$fact" >/dev/null
    echo "[ai] auto-learned: $fact"
  done
}

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
    local status_full
    status_full=$(git status --porcelain 2>/dev/null | head -30)
    out+="GIT_STATUS:\n${status_full}\n"
    # Auto-expand untracked dirs so model doesn't have to discover.
    local utdirs
    utdirs=$(printf "%s\n" "$status_full" | awk '/^\?\? /{sub(/^\?\? /,""); print}' | head -10)
    if [[ -n "$utdirs" ]]; then
      out+="UNTRACKED_CONTENTS:\n"
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        if [[ -d "$p" ]]; then
          out+="--- $p (dir) ---\n$(find "$p" -type f -maxdepth 3 2>/dev/null | head -20)\n"
        elif [[ -f "$p" ]]; then
          out+="--- $p (file) ---\n"
        fi
      done <<< "$utdirs"
    fi
  else
    out+="GIT_REPO: no\n"
  fi
  out+="LS_TOP: $(ls -1 2>/dev/null | head -10 | tr '\n' ' ')\n"
  printf "%b" "$out"
}
aictx() { _ai_context; }

# --- Refinement: follow-up on prior assistant turn -------------------------
_ai_is_refinement() {
  local q="${1:l}"
  local p
  p=$(_ai_chat_path)
  [[ -f "$p" ]] || return 1
  # Require a prior [assistant] turn.
  grep -q "^\[assistant\]" "$p" 2>/dev/null || return 1
  case "$q" in
    *"too long"*|*"too short"*|*"shorter"*|*"longer"*|*"instead"*|\
    *"drop "*|*"remove "*|*"add "*|*"change "*|*"rewrite"*|*"redo"*|\
    *"try again"*|*"make it"*|*"use "*|*"don't "*|*"do not "*|\
    *"that's wrong"*|*"thats wrong"*|*"thats not right"*|*"that's not right"*|\
    *"you are doing wrong"*|*"you're wrong"*|*"refine"*|*"revise"*|\
    *"shorten"*|*"lengthen"*|*"simpler"*|*"more detail"*|*"less detail"*|\
    *"no scope"*|*"with scope"*|*"without "*|*"only "*|*"keep only"*)
      return 0 ;;
  esac
  return 1
}

# Extract content of the LAST [assistant] block from chat file (text after [assistant] up to next [user] or EOF).
_ai_chat_last_assistant() {
  local p
  p=$(_ai_chat_path)
  [[ -f "$p" ]] || return 1
  awk '
    /^\[assistant\]/ { start=NR; capture=1; buf=""; next }
    /^\[user\]/      { capture=0 }
    capture          { buf = buf $0 ORS }
    END              { printf "%s", buf }
  ' "$p"
}

_ai_refine() {
  local query="$*"
  local mem prior
  mem=$(_ai_mem_load)
  prior=$(_ai_chat_last_assistant)
  if [[ -z "$prior" ]]; then
    echo "[ai] no prior assistant turn to refine"
    return 1
  fi
  local prompt="You are revising your PREVIOUS output based on user feedback.

${mem}PREVIOUS OUTPUT (verbatim — this is what you produced last turn):
---
${prior}
---

USER FEEDBACK on that output: ${query}

Task: produce a new version of PREVIOUS OUTPUT with the feedback applied.

Rules:
- Reproduce the FULL structure of PREVIOUS OUTPUT (subject + body + bullets + code blocks). Do not collapse a multi-line artifact to a single line unless the user explicitly asks.
- Apply the feedback exactly. \"drop the scope\" -> delete (scope) parenthetical. \"max 50 chars\" -> count chars. \"imperative verbs\" -> rewrite as add/create/update/etc.
- Output ONLY the revised artifact. No preamble. No \"here is\". No rules text. No code fences. Stop immediately after the artifact."
  local result
  result=$(printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null)
  # Strip anything past a chat-template token leak.
  result="${result%%<|im_start|>*}"
  result="${result%%<|im_end|>*}"
  result="${result%%USER FEEDBACK:*}"
  printf "%s\n" "$result"
  _ai_chat_append user "$query"
  _ai_chat_append assistant "$result"
}

# --- Deterministic commit-message pipeline ---------------------------------
# Skips agentic loop. Gathers ALL relevant git data in one pass, sends to model once.
_ai_commit_msg() {
  local query="$*"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[ai] not in a git repo"
    return 1
  fi
  echo "[ai] gathering git state..."
  local status_out diff_cached diff_unstaged untracked_files log_recent
  status_out=$(git status --porcelain 2>&1 | head -100)
  diff_cached=$(git diff --cached 2>&1 | head -400)
  diff_unstaged=$(git diff 2>&1 | head -400)
  log_recent=$(git log --oneline -n 10 2>&1)
  # Untracked: file paths + a head of each text file
  untracked_files=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    untracked_files+="--- ${f} ---\n"
    if [[ -f "$f" ]]; then
      file --brief --mime "$f" 2>/dev/null | grep -q "text/" \
        && untracked_files+="$(head -30 "$f" 2>/dev/null)\n"
    fi
  done < <(git ls-files --others --exclude-standard 2>/dev/null | head -20)
  local data="STATUS (--porcelain):
${status_out:-(clean)}

STAGED DIFF (git diff --cached):
${diff_cached:-(none)}

UNSTAGED DIFF (git diff):
${diff_unstaged:-(none)}

UNTRACKED FILES + HEADS:
${untracked_files:-(none)}

RECENT COMMIT STYLE (git log --oneline -n 10):
${log_recent:-(none)}"
  # Build explicit file checklist so model can't ignore items.
  local checklist=""
  local n=0
  for f in ${(f)"$(git diff --cached --name-only 2>/dev/null)"}; do
    [[ -z "$f" ]] && continue
    ((n++)); checklist+="  ${n}. [staged] ${f}\n"
  done
  for f in ${(f)"$(git diff --name-only 2>/dev/null)"}; do
    [[ -z "$f" ]] && continue
    ((n++)); checklist+="  ${n}. [unstaged] ${f}\n"
  done
  for f in ${(f)"$(git ls-files --others --exclude-standard 2>/dev/null)"}; do
    [[ -z "$f" ]] && continue
    ((n++)); checklist+="  ${n}. [untracked] ${f}\n"
  done
  local mem chat
  mem=$(_ai_mem_load)
  chat=$(_ai_chat_load)
  local prompt="You are a git commit-message generator.
${mem}${chat}Below is the ACTUAL local repo state. Generate a Conventional Commits style message covering every change.
If CONVERSATION SO FAR contains a previous commit-message attempt plus user feedback, REVISE per the feedback — do not start from scratch.

CHANGES YOU MUST COVER (one bullet per item, do not skip any):
${checklist:-  (none — repo is clean)}
Total: ${n} change(s).

Format:
  <type>(<scope>): <subject ≤72 chars>
  <blank line>
  - bullet for item 1 (use real filename + what changed)
  - bullet for item 2
  ... (one bullet per CHANGES item above)

Rules:
- NO placeholders. NO '...'. Use the actual filenames and content shown in DATA.
- Subject line: lowercase after the colon, no trailing period.
- Match the repo's existing commit style if visible in RECENT COMMIT STYLE.
- The body MUST have exactly ${n} bullet(s) — one per item in the CHANGES list above.
- Output ONLY the commit message text — no preamble, no fenced code block.

DATA:
${data}

USER REQUEST: ${query}"
  local result
  result=$(printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null)
  printf "%s\n" "$result"
  _ai_chat_append user "$query"
  _ai_chat_append assistant "$result"
}

# --- Safety filter ---------------------------------------------------------
_ai_safe() {
  local cmd="$1"
  local danger='(^|[ ;|&])(rm|sudo|dd|mkfs|mv|chmod|chown|kill|killall|shutdown|reboot|halt|truncate|tee)( |$)'
  local danger2='>[^|&>]|>>'
  local danger3='git +(push|reset|commit|rebase|checkout|merge|add|stash|tag|clone|fetch|pull)'
  local danger4='(curl|wget)[^|;]*\|[^|]*(sh|bash|zsh)'
  # Package managers + anything that mutates the system. Block install/uninstall/update verbs broadly.
  local danger5='(^|[ ;|&])(brew|apt|apt-get|yum|dnf|pacman|port|snap|pip|pip3|pipx|npm|yarn|pnpm|bun|gem|cargo|go) +(install|add|uninstall|remove|upgrade|update|reinstall|create|init|publish|link|unlink|global)'
  local danger6='(^|[ ;|&])(make|cmake) +(install|clean|deploy)'
  [[ "$cmd" =~ $danger  ]] && return 1
  [[ "$cmd" =~ $danger2 ]] && return 1
  [[ "$cmd" =~ $danger3 ]] && return 1
  [[ "$cmd" =~ $danger4 ]] && return 1
  [[ "$cmd" =~ $danger5 ]] && return 1
  [[ "$cmd" =~ $danger6 ]] && return 1
  return 0
}

# --- Agentic loop ----------------------------------------------------------
# Extract first RUN cmd from raw model response (single line).
_ai_extract_run() {
  printf "%s" "$1" | awk '/^RUN:/{sub(/^RUN: */,""); print; exit}'
}

# Extract ANSWER block (may be multi-line). Captures from "ANSWER:" line until end
# of response OR until next "RUN:" line. Strips the "ANSWER: " prefix.
_ai_extract_answer() {
  printf "%s" "$1" | awk '
    /^ANSWER:/ { flag=1; sub(/^ANSWER: */,""); print; next }
    /^RUN:/    { flag=0 }
    flag       { print }
  '
}

ai() {
  # Memory + chat subcommands (dispatched before LLM).
  case "$1" in
    remember)          shift; _ai_mem_remember "$@"; return $? ;;
    forget)            shift; _ai_mem_forget "$@"; return $? ;;
    memory|recall|mem) _ai_mem_show; return 0 ;;
    new|reset|end)     _ai_chat_reset; return 0 ;;
    history|chat)      _ai_chat_show; return 0 ;;
    project)
      if [[ "$2" == remember ]]; then
        shift 2; _ai_mem_remember project "$@"; return $?
      fi
      ;;
  esac
  local query="$*"
  if [[ -z "$query" ]]; then
    echo "Usage:"
    echo "  ai <query>                   — agentic loop (Ctrl+G to seed)"
    echo "  ai remember <fact>           — save to global memory"
    echo "  ai project remember <fact>   — save to project memory"
    echo "  ai memory                    — show memory"
    echo "  ai forget <substring>        — remove matching lines"
    echo "  ai history                   — show current chat session"
    echo "  ai new                       — reset chat session (archived)"
    return 1
  fi
  # Intent dispatch.
  local q_lc="${query:l}"
  # 1) Refinement of prior assistant turn (only when chat has one).
  if _ai_is_refinement "$query"; then
    _ai_refine "$query"
    return $?
  fi
  # 2) Commit-message generation has deterministic pipeline.
  if [[ "$q_lc" == *"commit msg"* || "$q_lc" == *"commit message"* \
      || "$q_lc" == *"prepare"*"commit"* || "$q_lc" == *"write"*"commit"* \
      || "$q_lc" == *"generate"*"commit"* ]]; then
    _ai_commit_msg "$query"
    return $?
  fi
  local ctx mem chat
  ctx=$(_ai_context)
  mem=$(_ai_mem_load)
  chat=$(_ai_chat_load)
  local trace=""
  local max="${AI_MAX_ITERS:-6}"
  local out_lines="${AI_OUT_LINES:-200}"
  local trace_chars="${AI_TRACE_CHARS:-6000}"
  local debug="${AI_DEBUG:-0}"
  local i=0
  local resp="" cmd="" out="" prompt="" answer="" final_hint=""
  local sys='You are a macOS zsh assistant operating an agentic loop on the user'\''s machine.
You drive a chain of read-only shell commands to gather REAL data, then synthesize a final ANSWER.

Reply with one of these forms (no prose outside them):
  RUN: <one read-only shell command>           # one per iteration; chain freely
  ANSWER: <final synthesized artifact>          # may span multiple lines; everything until end of message

Workflow:
1. Decompose the user query into sub-questions answerable by shell commands.
2. Emit RUN for the next sub-question. Wait for its OUT in TRACE on the next turn.
3. Repeat. Chain as many RUNs as needed (typically 1-5).
4. When you have enough DATA, emit ANSWER with the synthesized artifact.

CRITICAL — synthesis vs suggestion:
- If the user asks for an ARTIFACT (commit message, summary, explanation, refactored code, changelog), ANSWER must CONTAIN THE ARTIFACT TEXT, not a command that would produce it.
- If the user asks for a VALUE ("how many", "which file", "what branch"), ANSWER must contain the value from TRACE.
- If the user asks "what command would do X", ANSWER may be a one-line shell command.

Example — "prepare a commit message based on staged/unstaged work":
  Turn 1: RUN: git status --short
  Turn 2: RUN: git diff --stat
  Turn 3: RUN: git diff
  Turn 4: RUN: git log --oneline -n 5
  Turn 5: ANSWER:
          feat(skills): add diagram skill and feat-assets scaffold

          - new .claude/skills/diagram/ directory ...
          - feat-assets/ for shared asset pipeline ...

Mutation rules:
- RUN must be read-only. You CANNOT modify files or repo state. No: rm, sudo, mv, chmod, chown, kill, dd, mkfs, file redirects (> >>), git push/reset/commit/rebase/checkout/merge/add, curl|sh.
- If the user asks you to PERFORM a mutating action (commit, stage, delete, push), still RUN read-only steps to inspect state, then ANSWER with the exact command(s) the USER should run. Do NOT attempt the mutation yourself.

Efficiency:
- NEVER repeat a RUN that already appears in TRACE. Pick a different command or ANSWER.
- For empty OUT, switch strategy — try a related command, not the same one.

Git hints (when relevant):
- Staged diff: `git diff --cached` (NOT `git diff`).
- Untracked dir contents: `ls -la <dir>` or `find <dir> -type f -maxdepth 3`.
- Recent style: `git log --oneline -n 10` to match repo commit conventions.

Memory:
- If GLOBAL/PROJECT MEMORY blocks appear above CONTEXT, treat them as binding facts/preferences. Honor them unless they contradict the user'\''s current query.
- AUTO-LEARN (only if user shows a preference/correction): after ANSWER, on its own line, you MAY emit `LEARN: <one short fact in third person, e.g. "user prefers Conventional Commits with scope">`. Only emit when the fact is clearly worth saving across sessions. Never emit LEARN for transient details.'
  while (( i < max )); do
    # On final iteration, push model to ANSWER even if it wanted more RUNs.
    if (( i == max - 1 )); then
      final_hint="
NOTE: This is the FINAL turn. You MUST emit ANSWER now using the TRACE you have. No more RUNs."
    fi
    prompt="${sys}${final_hint}

${mem}${chat}CONTEXT:
${ctx}
TRACE:
${trace:-(none)}
USER QUERY: ${query}"
    resp=$(printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null)
    (( debug )) && { echo "---[ai:debug iter $i raw]---"; printf "%s\n" "$resp"; echo "---"; }

    # Prefer ANSWER (multi-line); fall back to RUN.
    answer=$(_ai_extract_answer "$resp")
    if [[ -n "$answer" ]]; then
      printf "%s\n" "$answer"
      _ai_chat_append user "$query"
      _ai_chat_append assistant "$answer"
      _ai_mem_auto_extract "$resp"
      return 0
    fi
    cmd=$(_ai_extract_run "$resp")
    # Strip trailing inline-prefix junk if model mashed both on one line.
    cmd="${cmd%% ANSWER:*}"
    cmd="${cmd%% RUN:*}"
    if [[ -z "$cmd" ]]; then
      echo "[ai] no structured reply, raw:"
      printf "%s\n" "$resp"
      return 1
    fi
    if ! _ai_safe "$cmd"; then
      echo "[ai] blocked unsafe: $cmd"
      trace+="RUN_BLOCKED: $cmd
"
      ((i++)); continue
    fi
    # Dedupe: model sometimes re-emits an identical RUN. Reject and hint.
    if [[ "$trace" == *"RUN: ${cmd}"$'\n'* ]]; then
      echo "[ai] skip repeat: $cmd"
      trace+="HINT: '${cmd}' already executed above. Choose a DIFFERENT command or emit ANSWER.
"
      ((i++)); continue
    fi
    echo "[ai] » $cmd"
    out=$(eval "$cmd" 2>&1 | head -"$out_lines")
    printf "%s\n" "$out"
    trace+="RUN: $cmd
OUT: $out
---
"
    # Bound trace size — keep tail when oversized.
    if (( ${#trace} > trace_chars )); then
      trace="...[older trace trimmed]...
${trace: -$trace_chars}"
    fi
    ((i++))
  done
  # Forced final synthesis: model didn't ANSWER within max iters.
  # Ask one more time with strict ANSWER-only instruction using accumulated trace.
  echo "[ai] forcing final synthesis from trace..."
  prompt="${sys}

CONTEXT:
${ctx}
TRACE:
${trace:-(none)}
USER QUERY: ${query}

FINAL: emit ANSWER ONLY using the TRACE above as ground truth. Do not emit RUN. If the trace is incomplete, do your best with the data you have."
  resp=$(printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null)
  answer=$(_ai_extract_answer "$resp")
  if [[ -n "$answer" ]]; then
    printf "%s\n" "$answer"
    _ai_chat_append user "$query"
    _ai_chat_append assistant "$answer"
    _ai_mem_auto_extract "$resp"
    return 0
  fi
  # Last resort: print raw response (with ANSWER prefix stripped if present).
  local fallback="${resp#ANSWER:}"
  printf "%s\n" "$fallback"
  _ai_chat_append user "$query"
  _ai_chat_append assistant "$fallback"
  return 2
}

# --- Misc helpers ----------------------------------------------------------
explain() { sgpt "explain this command: $*"; }
fix()     { eval "$(fc -ln -1)" 2>&1 | sgpt "this command failed, return only the corrected command"; }
