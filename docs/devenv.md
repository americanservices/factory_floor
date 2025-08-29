# devenv.sh - Team Setup Guide

This document explains how we use devenv.sh to ensure a repeatable, reproducible development environment for OpenCode and our project tooling.

## Quickstart

1. Make sure you have Nix and direnv installed.
2. In the project root, run:
   ```bash
   direnv allow
   devenv shell
   ```
3. The environment will provision languages, tools, scripts, and shell hooks.

## Files

- devenv.nix — declarative environment config (languages, packages, scripts, processes, env vars)
- .envrc — integrates direnv with devenv for auto-activation
- devenv.lock — pins inputs for reproducibility

## Languages

We enable:
- Python (managed with uv in the shell hook)
- Node.js and Bun (for JS tooling and OpenCode npm install fallback)
- Go (for any Go dependencies)

Example toggle in devenv.nix:
```nix
languages = {
  python.enable = true;
  javascript.enable = true;
  typescript.enable = true;
  go.enable = true;
};
```

## Packages

Core utilities we include:
- git, gh, git-town
- nodejs_20, bun
- uv
- ripgrep, jq, fzf, tree, bat, fd

Add packages under:
```nix
packages = with pkgs; [ git gh git-town nodejs_20 bun uv ripgrep jq tree fzf bat fd ];
```

## Scripts

We define shell scripts for:
- Worktree management (wt-*)
- MCP server control (mcp-*)
- Agent helpers (agent-*)

Scripts are available automatically in the devenv shell. See devenv.nix `scripts = { ... }`.

## Processes & Services

We optionally run background processes (e.g., MCP servers) using `processes`.
Start them with:
```bash
devenv up
```

Example in devenv.nix:
```nix
processes.mcp-auto.exec = ''
  mkdir -p .mcp/{pids,logs,sockets}
  # start servers if not running
  # ...
  sleep infinity
'';
```

Services (databases, etc.) can be enabled via `services.<name>`. We currently keep these off.

## OpenCode Integration

To make `opencode` available reliably:
- We prefer installing via Homebrew in the shell hook when not found, and ensure `$HOME/.opencode/bin` is added to PATH.
- Alternatively, install via npm: `npm install -g opencode-ai` or bun: `bun install -g opencode-ai`.

Environment variables:
```nix
env = {
  PATH = "$HOME/.opencode/bin:$PATH"; # opencode installer path
};
```

Shell hook (enterShell) handles:
- Creating a Python venv with uv
- Installing OpenCode if missing (script, brew, or npm fallback)
- Printing quick references

## direnv

`.envrc` contains:
```sh
eval "$(devenv hook zsh)"
use devenv
```
Run `direnv allow` once in the project root.

## Reproducibility

- Keep `devenv.lock` committed.
- Avoid ad-hoc global installations; prefer defining packages or scripted installs in `enterShell`.
- Team members should use `devenv shell` (or direnv auto-activation) for a consistent toolchain.

## Troubleshooting

- If a command is missing, confirm you are in the devenv shell: `$DEVENV_STATE` is set and prompt shows `(devenv)`.
- Rebuild environment: `devenv update` then `devenv shell`.
- PATH issues on macOS shells: our hook exports the opencode path for current session.

## Links
- https://devenv.sh
- Reference options: https://devenv.sh/reference/options
- Scripts: https://devenv.sh/scripts
- Languages: https://devenv.sh/languages
- Processes: https://devenv.sh/processes
- Services: https://devenv.sh/services
