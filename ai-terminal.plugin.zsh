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
  local prompt="You are a git commit-message generator.
Below is the ACTUAL local repo state. Generate a Conventional Commits style message covering every change.

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
  printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null
}

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
  local query="$*"
  if [[ -z "$query" ]]; then
    echo "Usage: ai <natural language query>"
    return 1
  fi
  # Intent shortcut: commit message generation has deterministic pipeline.
  local q_lc="${query:l}"
  if [[ "$q_lc" == *"commit msg"* || "$q_lc" == *"commit message"* \
      || "$q_lc" == *"prepare"*"commit"* || "$q_lc" == *"write"*"commit"* \
      || "$q_lc" == *"generate"*"commit"* ]]; then
    _ai_commit_msg "$query"
    return $?
  fi
  local ctx
  ctx=$(_ai_context)
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
- Recent style: `git log --oneline -n 10` to match repo commit conventions.'
  while (( i < max )); do
    # On final iteration, push model to ANSWER even if it wanted more RUNs.
    if (( i == max - 1 )); then
      final_hint="
NOTE: This is the FINAL turn. You MUST emit ANSWER now using the TRACE you have. No more RUNs."
    fi
    prompt="${sys}${final_hint}

CONTEXT:
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
    return 0
  fi
  # Last resort: print raw response (with ANSWER prefix stripped if present).
  printf "%s\n" "${resp#ANSWER:}"
  return 2
}

# --- Misc helpers ----------------------------------------------------------
explain() { sgpt "explain this command: $*"; }
fix()     { eval "$(fc -ln -1)" 2>&1 | sgpt "this command failed, return only the corrected command"; }
