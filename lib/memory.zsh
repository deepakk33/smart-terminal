# lib/memory.zsh — global + project memory; auto-inject + auto-learn.

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

# Extract LEARN: lines from a model response and persist (when AI_AUTO_LEARN=1).
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
