# MCP Servers with OpenCode

This guide explains how our project configures and runs MCP servers inside OpenCode, plus how to use Exa MCP (remote and local).

## Where it's configured

- Project config: `.opencode.json` (checked into repo)
- Global config (optional): `~/.config/opencode/opencode.json`

OpenCode reads `.opencode.json` and starts any `enabled` local servers automatically when the app launches.

## Servers we enable by default

- `exa` (local): Exa MCP server via NPX
- `context7` (local): Documentation fetcher (Context7)
- `sequential-thinking` (local): Structured problem-solving
- `python-sandbox` (local, Deno): Run Python safely
- `playwright` (local): Browser automation MCP

Optional examples included but disabled by default:
- `exa-remote` (remote): Connect to Exa’s hosted MCP URL
- `filesystem` (local): FS access
- `github` (local): GitHub tools

## Required tools

- Node.js + npx (already provided by `devenv.nix`)
- Deno (for Python sandbox). If needed, add `pkgs.deno` to `packages` in `devenv.nix`.

## Environment variables

- `EXA_API_KEY` (required for Exa)
- `UPSTASH_VECTOR_REST_URL` and `UPSTASH_VECTOR_REST_TOKEN` (Context7)
- `GITHUB_TOKEN` (optional for GitHub MCP)

Export them in your shell (do not commit secrets):
```sh
export EXA_API_KEY="<your key>"
export UPSTASH_VECTOR_REST_URL="<url>"
export UPSTASH_VECTOR_REST_TOKEN="<token>"
```

## Exa MCP options

- Local (preferred for our setup):
```json
{
  "mcp": {
    "exa": {
      "type": "local",
      "command": ["npx", "-y", "exa-mcp-server"],
      "enabled": true,
      "environment": { "EXA_API_KEY": "{env:EXA_API_KEY}" }
    }
  }
}
```

- Remote (hosted by Exa):
```json
{
  "mcp": {
    "exa-remote": {
      "type": "remote",
      "url": "https://mcp.exa.ai/mcp",
      "enabled": false,
      "headers": { "Authorization": "Bearer {env:EXA_API_KEY}" }
    }
  }
}
```

You can toggle `enabled` between the local and remote versions depending on preference.

## Using inside OpenCode

1. Ensure your API keys are exported (see above)
2. From the project root, start OpenCode:
```sh
opencode
```
3. When OpenCode launches, it will start all enabled local MCP servers listed in `.opencode.json`. You should see a plug icon or server status indicators inside the TUI.

## Troubleshooting

- "command not found": confirm you’re running inside `devenv shell` so `npx` is available
- Exa auth errors: verify `EXA_API_KEY` is exported without quotes/spaces
- Deno missing: add `deno` to `packages` in `devenv.nix` and re-enter `devenv shell`
- Ports/permissions: local servers use stdio; no ports should be required

## References
- OpenCode MCP docs: https://opencode.ai/docs/mcp-servers/
- Exa MCP docs: https://exa.ai/docs/exa-mcp
- MCP servers directory: https://github.com/modelcontextprotocol/servers
