# ai-terminal.plugin.zsh — loader. Sources lib/*.zsh modules.
#
# Modules:
#   widget.zsh   — ZLE widget + Ctrl+G dispatcher.
#   chat.zsh     — per-terminal chat session.
#   memory.zsh   — global + project memory.
#   context.zsh  — environmental probe for prompts.
#   safety.zsh   — classifier + RUN gate + interactive confirm.
#   intents.zsh  — refinement + commit-msg deterministic pipelines.
#   agent.zsh    — ai() dispatcher + agentic loop + extractors.
#   helpers.zsh  — explain, fix, rotating startup tip.
#
# Hotkey: Ctrl+G (empty buffer seeds "ai "; non-empty single-shot rewrite).
# Subcommands: ai remember / project remember / forget / memory / history / new.
# Env: AI_MAX_ITERS, AI_OUT_LINES, AI_TRACE_CHARS, AI_DEBUG, AI_AUTO_LEARN,
#      AI_PERMISSION (confirm|yolo), AI_TIPS (1|0), AI_MEM_DIR, AI_CHAT_DIR, etc.

# Resolve own dir so libs load regardless of where the plugin was sourced from.
typeset -g _AI_PLUGIN_DIR="${${(%):-%x}:A:h}"
typeset -g _AI_LIB_DIR="${_AI_PLUGIN_DIR}/lib"

if [[ ! -d "$_AI_LIB_DIR" ]]; then
  print -u2 "[ai-terminal] missing lib/ dir at $_AI_LIB_DIR — install incomplete?"
  return 1
fi

# Order matters: safety + chat + memory + context defined before intents/agent that use them.
for _m in widget chat memory context safety intents agent helpers; do
  source "${_AI_LIB_DIR}/${_m}.zsh"
done
unset _m
