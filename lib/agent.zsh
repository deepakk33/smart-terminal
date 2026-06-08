# lib/agent.zsh — agentic loop + extractors + ai() dispatcher.

# Extract first RUN/ACT — join continuation lines until next directive (so a quoted arg
# that wrapped to a second line is captured whole).
# Tolerates model copying trace-style prefixes: "ACT:", "ACT(approved):", "ACT(safe):" etc.
_ai_extract_directive() {
  local kind="$1" resp="$2"
  printf "%s\n" "$resp" | awk -v k="$kind" '
    BEGIN { collecting=0; buf=""; pat = "^" k "(\\([^)]*\\))?: *" }
    {
      if (collecting) {
        if ($0 ~ /^(RUN|ACT|ANSWER)(\([^)]*\))?:/) { exit }
        buf = buf " " $0
        next
      }
      if (match($0, pat)) {
        sub(pat, "")
        buf = $0
        collecting = 1
      }
    }
    END { print buf }
  '
}

_ai_extract_run() { _ai_extract_directive RUN "$1"; }
_ai_extract_act() { _ai_extract_directive ACT "$1"; }

_ai_extract_answer() {
  printf "%s" "$1" | awk '
    /^ANSWER(\([^)]*\))?:/ { flag=1; sub(/^ANSWER(\([^)]*\))?: */,""); print; next }
    /^RUN(\([^)]*\))?:/    { flag=0 }
    /^ACT(\([^)]*\))?:/    { flag=0 }
    flag                    { print }
  '
}

# System prompt for the agentic loop.
_ai_sys_prompt() {
  cat <<'EOF'
You are a macOS zsh assistant operating an agentic loop on the user's machine.
You drive read-only inspections (RUN) and optional mutating actions (ACT, with user confirmation), then synthesize a final ANSWER.

Reply with one of these forms (no prose outside them):
  RUN:    <one read-only shell command>            # auto-executed, no prompt
  ACT:    <one mutating shell command>             # the harness will prompt the USER for y/n before executing
  ANSWER: <final synthesized artifact>             # may span multiple lines; everything until end of message

EXACT PREFIX: use literally `ACT:`, `RUN:`, `ANSWER:`. Never `ACT(approved):`, `ACT(safe):`, `RUN(blocked):`. Those parenthetical forms appear in TRACE as records of past executions — they are NOT directives you should emit.

Workflow:
1. Decompose the user query into sub-questions answerable by shell commands.
2. Emit RUN for inspections, ACT for mutations. Wait for the OUT in TRACE next turn.
3. Repeat. Chain as needed.
4. When you have enough DATA, emit ANSWER summarising what happened.

When to use ACT:
- User asked you to PERFORM an action (commit, stage, push, install, delete, move, chmod, branch, etc.).
- Be specific: produce the exact, final mutating command. The user's confirmation prompt protects them; do not be timid.
- Examples: `ACT: git add -A`, `ACT: git commit -m "<subject>"`, `ACT: brew install ripgrep`, `ACT: mv old.txt new.txt`.
- For commit, use a Conventional Commits subject derived from RUN-gathered diff. Quote properly with double quotes.
- NEVER use ACT for inspection — that's RUN.

ONE COMMAND PER ACT — STRICT:
- Emit exactly ONE shell command per ACT. NEVER chain with &&, ||, or ;.
- Multi-step workflows = multiple ACT turns. Example: create branch then commit:
  Turn N:   ACT: git checkout -b feat/foo
  (wait for EXIT: 0 in TRACE)
  Turn N+1: ACT: git commit -m "feat(foo): description"
- ACT must be a single line. Do not wrap arguments to a new line. Keep the whole command on one line, however long.
- After each ACT, the harness adds `EXIT: <code>` to TRACE. If non-zero, the command failed — diagnose and try a different approach. Do not blindly retry.

CRITICAL — synthesis vs suggestion:
- If the user asks for an ARTIFACT (commit message, summary, explanation, refactored code, changelog), ANSWER must CONTAIN THE ARTIFACT TEXT, not a command that would produce it.
- If the user asks for a VALUE ("how many", "which file", "what branch"), ANSWER must contain the value from TRACE.
- If the user asks "what command would do X", ANSWER may be a one-line shell command.

ACTION-VERB QUERIES — DO IT, DON'T DESCRIBE IT:
- If the user query contains an action verb (commit, push, branch, checkout, revert, stage, install, delete, move, rename, run, restart, kill, prune), you MUST emit ACT to perform the action. Do NOT emit an ANSWER that just describes the commands.
- The harness will prompt the user before executing. You are not bypassing safety — you are doing the work you were asked to do.
- Pattern: a few RUNs to inspect → one ACT → optionally one RUN to verify → ANSWER summarising what happened.

Mutation rules:
- RUN must stay read-only. Mutations go through ACT.
- Allowed in ACT: git add/commit/checkout/stash/branch/tag/etc, brew/npm/pip/yarn install, mv, cp, chmod, kill, redirects. The user is prompted before each ACT runs; you propose, they approve.
- Disallowed anywhere (will be hard-blocked): rm -rf /, sudo rm, fork bombs, dd of=/dev/, chmod -R 777 /.
- Destructive ACTs (rm -rf, git push --force, git reset --hard) trigger a red warning to the user. Use sparingly and only when explicitly requested.

Efficiency:
- NEVER repeat a RUN that already appears in TRACE. Pick a different command or ANSWER.
- For empty OUT, switch strategy — try a related command, not the same one.

Domain breadth — operate across whatever the user's stack involves:
- Git: status/log/diff/blame/reflog/branch (RUN) + add/commit/checkout/push/rebase/stash (ACT).
- Package managers: brew, npm/pnpm/yarn/bun, pip/pipx, cargo, gem, go, composer.
- Cloud CLIs: aws, gcloud, az, doctl, vercel, netlify, heroku, fly, railway, stripe.
- Containers / orchestration: docker, docker compose, kubectl, helm, podman, colima.
- Databases: psql, mysql, mongosh, redis-cli, sqlite3, dynamodb-local, prisma.
- API / network: curl, http (httpie), wscat, dig, nslookup, lsof, netstat, ss.
- JSON / data: jq, yq, csvkit, awk, sed.
- Search / fs: rg, fd, grep, find, ls, tree, stat, du.
- Build / lang tools: make, tsc, eslint, prettier, ruff, mypy, cargo build, go run.
- Process / system: ps, top, htop, kill, launchctl, sw_vers, sysctl.

Prefer focused tools when present (rg over grep, fd over find, jq for JSON). Detect availability with `command -v X >/dev/null` before relying on it.

Git hints:
- Staged diff: `git diff --cached` (NOT `git diff`).
- Untracked dir contents: `ls -la <dir>` or `find <dir> -type f -maxdepth 3`.
- Recent style: `git log --oneline -n 10` to match repo conventions.

Memory:
- If GLOBAL/PROJECT MEMORY blocks appear above CONTEXT, treat them as binding facts/preferences. Honor them unless they contradict the user's current query.
- AUTO-LEARN (only if user shows a preference/correction): after ANSWER, on its own line, you MAY emit `LEARN: <one short fact in third person>`. Only emit when worth saving across sessions.
EOF
}

# Reject ACTs that chain commands. Force one operation per turn so user confirms each step
# and the model can recover from failures.
_ai_act_is_chained() {
  local c="$1"
  [[ "$c" =~ '(\&\&|\|\||;)' ]] && return 0
  return 1
}

# Detect unbalanced quotes — indicates the model wrapped a quoted arg to a new line and
# we only captured the first line. Caller should reject and ask the model to put it on one line.
_ai_act_has_unbalanced_quotes() {
  local c="$1" dq sq
  dq=$(printf "%s" "$c" | tr -cd '"' | wc -c)
  sq=$(printf "%s" "$c" | tr -cd "'" | wc -c)
  (( dq % 2 != 0 )) && return 0
  (( sq % 2 != 0 )) && return 0
  return 1
}

# Execute one ACT iteration. Captures exit code so the model can recover next turn.
_ai_handle_act() {
  local act_cmd="$1" out_lines="$2"
  if _ai_act_is_chained "$act_cmd"; then
    echo "[ai] rejected chained ACT (use one cmd per turn): $act_cmd"
    _AI_TRACE+="ACT_REJECTED_CHAINED: $act_cmd
HINT: do not combine commands with && || ; — emit them as SEPARATE ACT turns. Wait for each result.
"
    return 1
  fi
  if _ai_act_has_unbalanced_quotes "$act_cmd"; then
    echo "[ai] rejected ACT with unbalanced quotes (cmd wrapped to next line?): $act_cmd"
    _AI_TRACE+="ACT_REJECTED_UNBALANCED_QUOTES: $act_cmd
HINT: keep the ENTIRE ACT command on ONE LINE. Do not wrap quoted arguments. Quote with double quotes only.
"
    return 1
  fi
  local class out rc
  class=$(_ai_classify "$act_cmd")
  case "$class" in
    blocked)
      echo "[ai] HARD-BLOCKED (catastrophic pattern): $act_cmd"
      _AI_TRACE+="ACT_BLOCKED: $act_cmd
"
      return 1
      ;;
    safe)
      echo "[ai] » $act_cmd"
      out=$(eval "$act_cmd" 2>&1 | head -"$out_lines"); rc=$?
      printf "%s\n" "$out"
      _AI_TRACE+="ACT(safe): $act_cmd
EXIT: $rc
OUT: $out
---
"
      ;;
    confirm|destructive)
      if _ai_confirm "$act_cmd" "$class"; then
        out=$(eval "$act_cmd" 2>&1 | head -"$out_lines"); rc=$?
        printf "%s\n" "$out"
        _AI_TRACE+="ACT(approved): $act_cmd
EXIT: $rc
OUT: $out
---
"
      else
        _AI_TRACE+="ACT_DECLINED_BY_USER: $act_cmd
"
      fi
      ;;
  esac
  return 0
}

# Print usage when ai called with no args.
_ai_usage() {
  cat <<EOF
Usage:
  ai <query>                   — agentic loop (Ctrl+G to seed)
  ai remember <fact>           — save to global memory
  ai project remember <fact>   — save to project memory
  ai memory                    — show memory
  ai forget <substring>        — remove memory lines
  ai history                   — show chat session
  ai new                       — reset chat session (archived)

Env knobs:
  AI_MAX_ITERS (default 6), AI_OUT_LINES (200), AI_TRACE_CHARS (6000),
  AI_DEBUG=1, AI_AUTO_LEARN=1, AI_PERMISSION=yolo, AI_TIPS=0.
EOF
}

# Distinct action verbs in a query. Used to gate ANSWER until that many ACTs have succeeded.
_ai_action_verb_count() {
  local q="${1:l}" n=0 v
  local seen=""
  for v in commit push branch checkout revert reset rebase merge stash install uninstall delete remove move rename restart deploy prune; do
    if [[ "$q" == *"$v"* && "$seen" != *",${v},"* ]]; then
      seen+=",${v},"
      ((n++))
    fi
  done
  echo $n
}

# True if query reads as a request to PERFORM an action.
_ai_is_action_query() {
  local q="${1:l}"
  if (( $(_ai_action_verb_count "$q") > 0 )); then return 0; fi
  case "$q" in
    *"do it"*|*"do that"*|*"do this"*|*"go ahead"*|*"please run"*|\
    *"can you"*"commit"*|*"can you"*"push"*) return 0 ;;
  esac
  return 1
}

ai() {
  # Subcommand dispatch first — these never reach the LLM.
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
    _ai_usage
    return 1
  fi

  # Intent routing.
  if _ai_is_refinement "$query"; then
    _ai_refine "$query"
    return $?
  fi
  if _ai_is_commit_msg_intent "$query"; then
    _ai_commit_msg "$query"
    return $?
  fi

  # Generic agentic loop.
  local ctx mem chat
  ctx=$(_ai_context)
  mem=$(_ai_mem_load)
  chat=$(_ai_chat_load)
  local _AI_TRACE=""
  local max="${AI_MAX_ITERS:-6}"
  local out_lines="${AI_OUT_LINES:-200}"
  local trace_chars="${AI_TRACE_CHARS:-6000}"
  local debug="${AI_DEBUG:-0}"
  local i=0
  local acted=0
  local action_query=0
  local actions_needed=0
  _ai_is_action_query "$query" && action_query=1
  (( action_query )) && actions_needed=$(_ai_action_verb_count "$query")
  (( actions_needed == 0 && action_query )) && actions_needed=1
  local resp="" cmd="" out="" prompt="" answer="" final_hint="" act_cmd=""
  local sys
  sys=$(_ai_sys_prompt)

  while (( i < max )); do
    if (( i == max - 1 )); then
      final_hint="
NOTE: This is the FINAL turn. You MUST emit ANSWER now using the TRACE you have. No more RUN/ACT."
    fi
    prompt="${sys}${final_hint}

${mem}${chat}CONTEXT:
${ctx}
TRACE:
${_AI_TRACE:-(none)}
USER QUERY: ${query}"
    resp=$(printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null)
    (( debug )) && { echo "---[ai:debug iter $i raw]---"; printf "%s\n" "$resp"; echo "---"; }

    # 1) ANSWER takes priority — unless this is an action query and not enough ACTs have completed.
    answer=$(_ai_extract_answer "$resp")
    if [[ -n "$answer" ]]; then
      if (( action_query == 1 && acted < actions_needed )); then
        echo "[ai] ANSWER blocked — ${acted}/${actions_needed} required action(s) completed. Pushing back..."
        _AI_TRACE+="ERROR: user asked for ${actions_needed} action(s) but only ${acted} succeeded so far (need EXIT: 0). Do not ANSWER yet. Emit the next ACT to complete the remaining work.
"
        ((i++)); continue
      fi
      printf "%s\n" "$answer"
      _ai_chat_append user "$query"
      _ai_chat_append assistant "$answer"
      _ai_mem_auto_extract "$resp"
      return 0
    fi

    # 2) ACT (mutation) — handled by _ai_handle_act, which updates _AI_TRACE.
    act_cmd=$(_ai_extract_act "$resp")
    if [[ -n "$act_cmd" ]]; then
      # _ai_handle_act records EXIT in trace; if approved and ran, mark acted.
      local before_trace_len=${#_AI_TRACE}
      _ai_handle_act "$act_cmd" "$out_lines"
      # Detect a successful run by checking trace gained an EXIT: 0 entry.
      if [[ "${_AI_TRACE:$before_trace_len}" == *"EXIT: 0"* ]]; then
        acted=1
      fi
      ((i++)); continue
    fi

    # 3) RUN (read-only).
    cmd=$(_ai_extract_run "$resp")
    if [[ -z "$cmd" ]]; then
      # No prefix at all — feed an error hint back to the model and retry.
      echo "[ai] response had no RUN:/ACT:/ANSWER: prefix — retrying with hint..."
      _AI_TRACE+="ERROR: previous response had no prefix. ALL replies must start with RUN:, ACT:, or ANSWER:.
Raw was: ${resp:0:200}
HINT: if the user asked for an ACTION (commit/revert/branch/push/install/etc.), emit ACT:. If asked to inspect, emit RUN:. If asked for an artifact, emit ANSWER:.
"
      ((i++)); continue
    fi
    if ! _ai_safe "$cmd"; then
      echo "[ai] blocked unsafe RUN (use ACT for mutations): $cmd"
      _AI_TRACE+="RUN_BLOCKED: $cmd
HINT: use ACT for mutating commands so the user can confirm.
"
      ((i++)); continue
    fi
    if [[ "$_AI_TRACE" == *"RUN: ${cmd}"$'\n'* ]]; then
      echo "[ai] skip repeat: $cmd"
      _AI_TRACE+="HINT: '${cmd}' already executed above. Choose a DIFFERENT command or emit ANSWER.
"
      ((i++)); continue
    fi
    echo "[ai] » $cmd"
    out=$(eval "$cmd" 2>&1 | head -"$out_lines")
    printf "%s\n" "$out"
    _AI_TRACE+="RUN: $cmd
OUT: $out
---
"
    if (( ${#_AI_TRACE} > trace_chars )); then
      _AI_TRACE="...[older trace trimmed]...
${_AI_TRACE: -$trace_chars}"
    fi
    ((i++))
  done

  # Forced final synthesis if loop exhausted without ANSWER.
  echo "[ai] forcing final synthesis from trace..."
  local final_warn=""
  if (( action_query == 1 && acted < actions_needed )); then
    final_warn="
WARNING: user asked for ${actions_needed} action(s); only ${acted} succeeded. Your ANSWER must HONESTLY report what completed vs what did NOT. Do NOT claim missing work was done. Suggest the exact remaining commands the user can run themselves."
  fi
  prompt="${sys}

${mem}CONTEXT:
${ctx}
TRACE:
${_AI_TRACE:-(none)}
USER QUERY: ${query}${final_warn}

FINAL: emit ANSWER ONLY using the TRACE above as ground truth. Do not emit RUN or ACT. If trace incomplete, do your best."
  resp=$(printf "%s" "$prompt" | sgpt --no-interaction 2>/dev/null)
  answer=$(_ai_extract_answer "$resp")
  if [[ -n "$answer" ]]; then
    printf "%s\n" "$answer"
    _ai_chat_append user "$query"
    _ai_chat_append assistant "$answer"
    _ai_mem_auto_extract "$resp"
    return 0
  fi
  local fallback="${resp#ANSWER:}"
  printf "%s\n" "$fallback"
  _ai_chat_append user "$query"
  _ai_chat_append assistant "$fallback"
  return 2
}
