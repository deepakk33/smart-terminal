# lib/safety.zsh — command classifier, RUN-gate filter, interactive confirm.

# Per-shell session cache of "always allow" approvals.
typeset -ga AI_APPROVED_CMDS 2>/dev/null

# Classify a command: safe | confirm | destructive | blocked.
_ai_classify() {
  local cmd="$1"
  local blocked='(^|[ ;|&])(rm +-rf +/[^./a-z]?|sudo +rm|dd +[^|]*of=/dev/[sdh]|mkfs|chmod +-R +777 +/)'
  local blocked2=':\(\)\{ *:\|:&'  # fork-bomb signature
  [[ "$cmd" =~ $blocked  ]] && { print -- blocked; return; }
  [[ "$cmd" =~ $blocked2 ]] && { print -- blocked; return; }
  local destr='(^|[ ;|&])(rm +-rf|git +push +(--force|-f)|git +reset +--hard|drop +(table|database)|truncate +table)'
  [[ "$cmd" =~ $destr ]] && { print -- destructive; return; }
  local conf='(^|[ ;|&])(git +(add|commit|push|checkout|branch|stash|tag|rebase|merge|pull|fetch|clone|reset|cherry-pick|revert|restore|rm)|brew +(install|uninstall|upgrade|update|reinstall|tap|untap)|npm +(install|uninstall|update|publish|run|ci)|(pip|pip3|pipx) +(install|uninstall|upgrade)|yarn +(add|remove|install)|pnpm +(add|remove|install)|bun +(install|add|remove)|cargo +(install|publish|uninstall)|gem +(install|uninstall)|go +(install|get)|make +install|mv +|cp +-[rR]|chmod +|chown +|kill +|killall +|launchctl +(load|unload|bootstrap|bootout)|defaults +(write|delete)|rm +)'
  [[ "$cmd" =~ $conf ]] && { print -- confirm; return; }
  [[ "$cmd" =~ '>[^|&>]|>>' ]] && { print -- confirm; return; }
  print -- safe
}

_ai_approved_in_session() {
  local cmd="$1" a
  for a in "${AI_APPROVED_CMDS[@]}"; do
    [[ "$cmd" == "$a" ]] && return 0
  done
  return 1
}

# Prompt user. Returns 0 if approved, 1 otherwise. Caches "always" choices per shell.
_ai_confirm() {
  local cmd="$1" class="$2"
  _ai_approved_in_session "$cmd" && { echo "[ai] (session-approved) » $cmd"; return 0; }
  if [[ "${AI_PERMISSION:-confirm}" == "yolo" ]]; then
    echo "[ai] (yolo) » $cmd"
    return 0
  fi
  local color=33 tag="confirm"
  if [[ "$class" == destructive ]]; then
    color=31; tag="DESTRUCTIVE"
  fi
  printf "\n\033[1;%sm[ai:%s]\033[0m proposed: \033[1m%s\033[0m\n" "$color" "$tag" "$cmd"
  printf "Run? [\033[1my\033[0m]es / [\033[1ma\033[0m]lways-this-session / [\033[1mn\033[0m]o: "
  local choice
  if ! read -k 1 choice; then
    echo
    return 1
  fi
  echo
  case "$choice" in
    y|Y) return 0 ;;
    a|A) AI_APPROVED_CMDS+=("$cmd"); echo "[ai] approved for this shell session: $cmd"; return 0 ;;
    *)   echo "[ai] declined"; return 1 ;;
  esac
}

# RUN-gate: stricter than _ai_classify. RUN must be strictly read-only.
_ai_safe() {
  local cmd="$1"
  local danger='(^|[ ;|&])(rm|sudo|dd|mkfs|mv|chmod|chown|kill|killall|shutdown|reboot|halt|truncate|tee)( |$)'
  local danger2='>[^|&>]|>>'
  local danger3='git +(push|reset|commit|rebase|checkout|merge|add|stash|tag|clone|fetch|pull)'
  local danger4='(curl|wget)[^|;]*\|[^|]*(sh|bash|zsh)'
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
