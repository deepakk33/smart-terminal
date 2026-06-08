#!/usr/bin/env bash
# uninstall.sh — remove ai-terminal block from ~/.zshrc + optional OMZ symlink.
# Does NOT delete ollama, the model, or sgpt (those may be used elsewhere).
set -euo pipefail

ZSHRC="${HOME}/.zshrc"
MARK_BEGIN="# >>> ai-terminal start"
MARK_END="# <<< ai-terminal end"

say() { printf "\033[1;34m[ai-terminal]\033[0m %s\n" "$*"; }

if [[ -f "$ZSHRC" ]] && grep -q "^${MARK_BEGIN}$" "$ZSHRC"; then
  TS="$(date +%Y%m%d-%H%M%S)"
  cp "$ZSHRC" "${ZSHRC}.bak.${TS}"
  say "backed up -> ${ZSHRC}.bak.${TS}"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b{flag=1; next}
    $0==e{flag=0; next}
    !flag
  ' "$ZSHRC" > "${ZSHRC}.tmp" && mv "${ZSHRC}.tmp" "$ZSHRC"
  say "removed ai-terminal block from $ZSHRC"
else
  say "no ai-terminal block found in $ZSHRC"
fi

if [[ -n "${ZSH:-}" ]]; then
  LINK="${ZSH_CUSTOM:-${ZSH}/custom}/plugins/ai-terminal/ai-terminal.plugin.zsh"
  [[ -L "$LINK" ]] && rm "$LINK" && say "removed OMZ symlink"
fi

cat <<EOF

\033[1;32m[ai-terminal] uninstalled\033[0m

Kept on system (remove manually if desired):
  - ollama service + model:   ollama rm qwen2.5-coder:7b
  - shell-gpt:                pipx uninstall shell-gpt
  - sgptrc config:            ~/.config/shell_gpt/
EOF
