# lib/helpers.zsh — explain, fix, startup tip.

explain() { sgpt "explain this command: $*"; }
fix()     { eval "$(fc -ln -1)" 2>&1 | sgpt "this command failed, return only the corrected command"; }

# Rotating tip printed once per interactive shell.
_ai_print_tip() {
  [[ "${AI_TIPS:-1}" == "0" ]] && return
  [[ -o interactive ]] || return
  local tips=(
    'Press \033[1mCtrl+G\033[0m on an empty prompt, type a query, hit Enter.  e.g.  ai how many files changed today'
    'Git: \033[1mai prepare commit msg\033[0m  /  \033[1mai commit staged files\033[0m  /  \033[1mai which branches are merged into main\033[0m'
    'Node: \033[1mai which package depends on react\033[0m  /  \033[1mai run lint and show errors\033[0m'
    'AWS:  \033[1mai list s3 buckets in this profile\033[0m  /  \033[1mai which lambdas error in last hour\033[0m'
    'Docker: \033[1mai why is the api container restarting\033[0m  /  \033[1mai prune dangling images\033[0m'
    'DB: \033[1mai show schema for users table\033[0m  /  \033[1mai find slow queries from last 24h\033[0m'
    'System: \033[1mai whats hogging port 3000\033[0m  /  \033[1mai which process is using the most cpu\033[0m'
    'Memory: \033[1mai remember <fact>\033[0m  /  \033[1mai project remember <fact>\033[0m  /  \033[1mai memory\033[0m'
    'Follow up: after any \033[1mai\033[0m turn, say "shorter", "drop scope", "you are wrong, try X" to refine'
    'Chat: \033[1mai history\033[0m to see turns  /  \033[1mai new\033[0m to reset session'
    'Helpers: \033[1mexplain <cmd>\033[0m  /  \033[1mfix\033[0m (corrects the last failed command)'
    'Debug:  \033[1mAI_DEBUG=1 ai <query>\033[0m streams raw model responses per iter'
    'Auto-approve (careful): \033[1mAI_PERMISSION=yolo ai <action>\033[0m skips ACT prompts'
    'Silence tips: \033[1mexport AI_TIPS=0\033[0m in ~/.zshrc'
  )
  local idx=$(( RANDOM % ${#tips[@]} ))
  printf "\033[2m\033[36mai ›\033[0m " >&2
  printf "${tips[$((idx+1))]}\n" >&2
}
_ai_print_tip
