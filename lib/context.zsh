# lib/context.zsh — environmental probe fed to every prompt.

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
