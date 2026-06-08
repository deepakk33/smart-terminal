# lib/widget.zsh — ZLE widget + Ctrl+G dispatcher.

# Single-shot: non-empty buffer becomes a shell command via sgpt.
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

# Empty buffer: seed "ai " prefix. Non-empty: single-shot.
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
