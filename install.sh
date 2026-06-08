#!/usr/bin/env bash
# install.sh — ai-terminal installer (idempotent, macOS / Linux best-effort).
# Re-runnable. Does not duplicate ~/.zshrc lines. Backs up zshrc before edit.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="${REPO_DIR}/ai-terminal.plugin.zsh"
SGPT_RC_TPL="${REPO_DIR}/config/sgptrc.template"
SGPT_RC="${HOME}/.config/shell_gpt/.sgptrc"
ZSHRC="${HOME}/.zshrc"
MODEL="${AI_TERMINAL_MODEL:-qwen2.5-coder:7b}"
MARK_BEGIN="# >>> ai-terminal start"
MARK_END="# <<< ai-terminal end"

say()  { printf "\033[1;34m[ai-terminal]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[ai-terminal]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[ai-terminal]\033[0m %s\n" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1; }

# -- Step 1: Homebrew (macOS) ----------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
  if ! need brew; then
    die "Homebrew not found. Install from https://brew.sh first, then re-run."
  fi
fi

# -- Step 2: Ollama ---------------------------------------------------------
if ! need ollama; then
  say "Installing ollama via brew..."
  brew install ollama
else
  say "ollama present ($(ollama --version 2>&1 | head -1))"
fi

if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
  say "Starting ollama service in background..."
  nohup ollama serve >/tmp/ollama.log 2>&1 &
  for _ in 1 2 3 4 5; do
    sleep 1
    curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && break
  done
  curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 \
    || die "ollama serve failed to start. See /tmp/ollama.log"
fi
say "ollama service up"

# -- Step 3: Pull model -----------------------------------------------------
if ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$MODEL"; then
  say "model $MODEL already pulled"
else
  say "Pulling $MODEL (may take several minutes)..."
  ollama pull "$MODEL"
fi

# -- Step 4: pipx + shell-gpt ----------------------------------------------
if ! need pipx; then
  say "Installing pipx..."
  brew install pipx
  pipx ensurepath >/dev/null 2>&1 || true
fi
export PATH="${HOME}/.local/bin:${PATH}"

if ! need sgpt; then
  say "Installing shell-gpt[litellm] via pipx..."
  pipx install "shell-gpt[litellm]"
else
  say "sgpt present ($(sgpt --version 2>&1 | head -1))"
fi

# -- Step 5: sgptrc ---------------------------------------------------------
mkdir -p "$(dirname "$SGPT_RC")"
if [[ ! -f "$SGPT_RC" ]]; then
  say "Writing $SGPT_RC from template"
  cp "$SGPT_RC_TPL" "$SGPT_RC"
else
  # Force critical keys without clobbering user additions
  for kv in \
    "DEFAULT_MODEL=ollama/${MODEL}" \
    "USE_LITELLM=true" \
    "OPENAI_USE_FUNCTIONS=false" \
    "OPENAI_API_KEY=local-dummy-key"
  do
    key="${kv%%=*}"
    if grep -q "^${key}=" "$SGPT_RC"; then
      # macOS sed needs -i ''
      if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|^${key}=.*|${kv}|" "$SGPT_RC"
      else
        sed -i "s|^${key}=.*|${kv}|" "$SGPT_RC"
      fi
    else
      printf "%s\n" "$kv" >> "$SGPT_RC"
    fi
  done
  say "patched existing $SGPT_RC"
fi

# -- Step 6: Patch ~/.zshrc -------------------------------------------------
TS="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$ZSHRC" ]]; then
  cp "$ZSHRC" "${ZSHRC}.bak.${TS}"
  say "backed up zshrc -> ${ZSHRC}.bak.${TS}"
else
  : > "$ZSHRC"
fi

# Strip prior guarded block (idempotent)
if grep -q "^${MARK_BEGIN}$" "$ZSHRC"; then
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b{flag=1; next}
    $0==e{flag=0; next}
    !flag
  ' "$ZSHRC" > "${ZSHRC}.tmp" && mv "${ZSHRC}.tmp" "$ZSHRC"
fi

# Strip legacy sgpt v0.2 block + any command_not_found_handler block left from older setups
awk '
  /^# Shell-GPT integration ZSH v0\.2/{skip=!skip; next}
  skip{next}
  /^command_not_found_handler\(\)/{cnf=1; next}
  cnf && /^}/{cnf=0; next}
  cnf{next}
  {print}
' "$ZSHRC" > "${ZSHRC}.tmp" && mv "${ZSHRC}.tmp" "$ZSHRC"

# Append guarded block sourcing plugin
{
  printf "\n%s\n" "$MARK_BEGIN"
  printf "# Managed by %s/install.sh — do not edit between markers.\n" "$REPO_DIR"
  printf "export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
  printf "[ -f \"%s\" ] && source \"%s\"\n" "$PLUGIN" "$PLUGIN"
  printf "%s\n" "$MARK_END"
} >> "$ZSHRC"
say "patched $ZSHRC (guarded block)"

# -- Step 7: Optional OMZ integration --------------------------------------
if [[ -n "${ZSH:-}" && -d "${ZSH}" ]]; then
  OMZ_DIR="${ZSH_CUSTOM:-${ZSH}/custom}/plugins/ai-terminal"
  mkdir -p "$OMZ_DIR"
  ln -sfn "$PLUGIN" "${OMZ_DIR}/ai-terminal.plugin.zsh"
  say "oh-my-zsh plugin link: ${OMZ_DIR}"
fi

# -- Done -------------------------------------------------------------------
cat <<EOF

\033[1;32m[ai-terminal] install complete\033[0m

Next:
  1. Restart your shell (or:  source ~/.zshrc )
  2. Press Ctrl+G on an empty prompt, type your query, hit Enter.
     e.g.  show me last 10 logs here

Model:   ${MODEL}
Plugin:  ${PLUGIN}
zshrc:   ${ZSHRC}  (backup: ${ZSHRC}.bak.${TS})
sgptrc:  ${SGPT_RC}

Override model:    AI_TERMINAL_MODEL=qwen2.5-coder:3b ./install.sh
Override iters:    AI_MAX_ITERS=6  (export in your shell)
Uninstall:         ./uninstall.sh
EOF
