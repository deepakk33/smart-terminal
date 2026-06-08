# ai-terminal

Local, free, context-aware AI terminal for zsh. Press **Ctrl+G**, type a query in plain English, get the actual result. All inference runs locally via [Ollama](https://ollama.com) — no cloud APIs, no API keys.

```
$ <empty prompt>          # press Ctrl+G
$ ai show me last 10 logs here
[ai] » git log -n 10 --oneline
713f29d second
097676e first
```

## What it does

- **Ctrl+G on empty prompt** → seeds `ai ` prefix. Type natural language, hit Enter → agentic loop.
- **Ctrl+G on non-empty prompt** → one-shot: replaces buffer with a shell command suggestion.
- **Context-aware**: probes `pwd`, OS, git repo state (branch, status, **untracked dir contents**), `ls` before asking the model.
- **Agentic loop** with three directives:
  - `RUN:` — read-only inspection, auto-executed.
  - `ACT:` — mutating action, classified into `confirm` / `destructive` / `blocked` → prompts y/n/always-this-session before running.
  - `ANSWER:` — final synthesized text.
- **Memory** (global + per-project) auto-injected into every prompt. `LEARN:` lines from model can be auto-saved (`AI_AUTO_LEARN=1`).
- **Chat session** per terminal tab — follow-ups (`shorter`, `drop scope`, `you are wrong, try X`) compound on the prior assistant turn.
- **Broad domain**: git, npm/pnpm/yarn/bun, brew, pip/pipx, aws/gcloud/az, docker/kubectl, psql/mongosh/redis-cli, curl/jq, lsof/ps — anything in `$PATH`. Model is instructed to detect tools via `command -v` and fall back gracefully.

## Permission tiers

| Class | Examples | Default behavior |
|---|---|---|
| safe | `ls`, `git status`, `cat`, `find`, `ps` | run silently as RUN |
| confirm | `git add`, `git commit`, `git push`, `brew install`, `npm install`, `mv`, `chmod`, redirects | yellow prompt — y / always-this-session / n |
| destructive | `rm -rf`, `git push --force`, `git reset --hard`, `drop table` | red prompt — same options, stronger warning |
| blocked | `rm -rf /`, `sudo rm`, fork bombs, `dd of=/dev/sd*`, `chmod -R 777 /` | never executed, even with `yolo` |

Override: `AI_PERMISSION=yolo` auto-approves `confirm` and `destructive` (does NOT bypass `blocked`).

## Components

| Component | Purpose |
|---|---|
| `ollama` | Local LLM runtime (Homebrew) |
| `qwen2.5-coder:7b` | Default model (~4.7 GB) |
| `shell-gpt` (sgpt) | CLI bridge, configured for Ollama via LiteLLM |
| `ai-terminal.plugin.zsh` | Widget + agentic loop + helpers |

## Install

```bash
git clone <this-repo> ~/sm-project/ai-terminal
cd ~/sm-project/ai-terminal
./install.sh
```

The installer is **idempotent** — re-run it any time. It will:

1. Install ollama + pipx via Homebrew (if missing).
2. Start the ollama service.
3. Pull `qwen2.5-coder:7b` (override via `AI_TERMINAL_MODEL=...`).
4. Install `shell-gpt[litellm]` via pipx.
5. Write `~/.config/shell_gpt/.sgptrc`.
6. Patch `~/.zshrc` with a guarded block that sources the plugin.
7. Back up `~/.zshrc` to `~/.zshrc.bak.<timestamp>` first.

Then restart your shell (or `source ~/.zshrc`).

### Smaller / faster model

```bash
AI_TERMINAL_MODEL=qwen2.5-coder:3b ./install.sh
```

## Usage

| Action | Result |
|---|---|
| Empty prompt + **Ctrl+G** | Inserts `ai ` prefix |
| Type query, **Enter** | Runs agentic loop |
| Non-empty prompt + **Ctrl+G** | Single-shot buffer rewrite (original sgpt behavior) |
| `ai <query>` | Same as above without the hotkey |
| `ai <follow-up feedback>` | Refines the previous assistant turn (auto-detected) |
| `ai new` / `ai reset` | Reset chat session (archives prior turns) |
| `ai history` / `ai chat` | Show chat turns for current session |
| `ai remember <fact>` | Save fact to **global** memory (`~/.config/ai-terminal/memory.md`) |
| `ai project remember <fact>` | Save fact to **project** memory (`<git-root>/.ai-terminal.md`) |
| `ai memory` | Show global + project memory |
| `ai forget <substring>` | Remove memory lines containing substring |
| `explain <cmd>` | Describe what a command does |
| `fix` | Re-run last command, ask AI for a corrected one |
| `aictx` | Print the context the loop sees (debug) |

### Chat / follow-ups

Each terminal tab has its own chat session (keyed by parent shell PID), stored at `~/.config/ai-terminal/sessions/chat-<id>.md`. Every turn (user query + assistant response) is appended automatically.

```bash
ai prepare commit msg
# feat(dashboard): add greeting.txt and update project documentation
#  • added greeting.txt ...
#  • created .ai-terminal.md ...
#  • added .claude/skills/diagram/README.md ...
#  • included feat-assets/logo.svg ...

ai subject too long, max 50 chars and drop the scope
# feat: add greeting.txt and update project documentation
#  • ... (bullets preserved)

ai keep only 2 bullets
ai use imperative verbs, not past tense
# feat: add greeting.txt and update project documentation
#  • Add greeting.txt with initial content "hello world"
#  • Create .ai-terminal.md with project overview
```

Follow-up detection auto-fires when chat has a prior assistant turn AND the new query looks like feedback ("shorter", "drop", "use", "instead", "make it", "you are doing wrong", etc.). Refinements compound — each turn builds on the last.

Knobs: `AI_CHAT_MAX_TURNS` (default 10), `AI_CHAT_DIR` (default `~/.config/ai-terminal/sessions`).

### Memory

Every `ai` call auto-injects both memory files into the model prompt. Use it to teach durable preferences:

```bash
ai remember user prefers Conventional Commits with scope, bullet body
ai project remember dashboard uses Next.js 14 app router with TanStack Query
ai prepare commit msg          # subject becomes feat(dashboard): ...
```

Memory locations:
- Global: `~/.config/ai-terminal/memory.md` (always loaded)
- Project: `<git-root>/.ai-terminal.md` (loaded when CWD is inside that repo)

Each entry is a dated bullet. File is capped at `AI_MEM_MAX_LINES` (default 200, newest kept).

**Auto-learn** (`AI_AUTO_LEARN=1`): model may emit `LEARN: <fact>` after ANSWER → appended to global memory automatically. Off by default.

### Environment knobs

| Var | Default | Effect |
|---|---|---|
| `AI_TERMINAL_MODEL` | `qwen2.5-coder:7b` | Model to pull/use (install time) |
| `AI_MAX_ITERS` | `6` | Max RUN-iterations per `ai` call |
| `AI_OUT_LINES` | `200` | Lines kept from each RUN output |
| `AI_TRACE_CHARS` | `6000` | Trace size cap, oldest trimmed when over |
| `AI_DEBUG` | `0` | `1` prints raw model response per iter |
| `AI_AUTO_LEARN` | `0` | `1` extracts `LEARN:` lines into global memory |
| `AI_PERMISSION` | `confirm` | `yolo` auto-approves ACT cmds (never bypasses `blocked`) |
| `AI_TIPS` | `1` | `0` silences the startup tip line |
| `AI_MEM_DIR` | `~/.config/ai-terminal` | Memory dir |
| `AI_MEM_GLOBAL` | `$AI_MEM_DIR/memory.md` | Global memory file path |
| `AI_MEM_MAX_LINES` | `200` | Memory file size cap |
| `AI_CHAT_DIR` | `~/.config/ai-terminal/sessions` | Chat session dir |
| `AI_CHAT_MAX_TURNS` | `10` | Max turn-pairs kept per session |
| `AI_CHAT_ID` | `$PPID` | Session identifier (per terminal tab) |

## Files / layout

```
ai-terminal/
├── README.md
├── install.sh
├── uninstall.sh
├── ai-terminal.plugin.zsh         # loader — sources lib/*.zsh
├── lib/
│   ├── widget.zsh                 # Ctrl+G ZLE widget
│   ├── chat.zsh                   # per-session conversation
│   ├── memory.zsh                 # global + project memory
│   ├── context.zsh                # env probe (OS, git, ls, untracked dirs)
│   ├── safety.zsh                 # classifier + confirm + RUN gate
│   ├── intents.zsh                # commit-msg + refinement pipelines
│   ├── agent.zsh                  # ai() + agentic loop + extractors
│   └── helpers.zsh                # explain, fix, startup tip
└── config/
    └── sgptrc.template
```

## Uninstall

```bash
./uninstall.sh
```

Removes the guarded block from `~/.zshrc` and the OMZ symlink. Does **not** remove ollama, the model, or sgpt — those may be used by other tools.

## Cmd-key note (macOS)

Terminals receive Ctrl-keys, not Cmd. To bind Cmd+K (or similar) to Ctrl+G:

- **Terminal.app** → Settings → Profiles → Keyboard → Add: Key `⌘K`, Action "Send Text", value `\x07`.
- **VS Code** `keybindings.json`:
  ```json
  { "key": "cmd+k", "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "" }, "when": "terminalFocus" }
  ```

## Safety

- Read-only commands only inside RUN. Destructive patterns blocked by `_ai_safe`.
- ANSWER text is printed, never executed. If the model proposes `rm -rf /` as an ANSWER, you see the text but nothing runs until you type it yourself and press Enter.
- All inference local. No outbound API calls.

## Tested on

macOS 26 (Apple Silicon), zsh 5.9, ollama 0.24, shell-gpt 1.5.1.
