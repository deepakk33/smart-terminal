# lib/intents.zsh — intent detectors + deterministic pipelines (commit-msg, refinement).

# True when chat has a prior assistant turn AND query reads as feedback.
_ai_is_refinement() {
  local q="${1:l}"
  local p
  p=$(_ai_chat_path)
  [[ -f "$p" ]] || return 1
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

# True when query matches commit-message intent.
_ai_is_commit_msg_intent() {
  local q="${1:l}"
  case "$q" in
    *"commit msg"*|*"commit message"*|*"prepare"*"commit"*|*"write"*"commit"*|*"generate"*"commit"*)
      return 0 ;;
  esac
  return 1
}

# Apply user feedback to prior assistant turn. Compact prompt — only last assistant block + new feedback.
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
  result="${result%%<|im_start|>*}"
  result="${result%%<|im_end|>*}"
  result="${result%%USER FEEDBACK:*}"
  printf "%s\n" "$result"
  _ai_chat_append user "$query"
  _ai_chat_append assistant "$result"
}

# Deterministic commit-message pipeline: gather all relevant git state in one pass.
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
  local checklist="" n=0
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
- Cover ALL changes: staged, unstaged, AND every untracked file.
- One bullet per distinct change area (one bullet per file or per logical grouping).
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
