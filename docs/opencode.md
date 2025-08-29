# OpenCode AI Assistant - Team Integration Guide

## Overview
OpenCode is an AI coding assistant built for the terminal that provides a native TUI, LSP support, multi-session capabilities, and integration with 75+ LLM providers.

## Installation Methods

### 1. Via Node Package Managers (Recommended for devenv)
```bash
npm install -g opencode-ai
# or
bun install -g opencode-ai
# or
yarn global add opencode-ai
```

### 2. Via Install Script
```bash
curl -fsSL https://opencode.ai/install | bash
```

### 3. Via Homebrew
```bash
brew install sst/tap/opencode
```

### 4. Manual Binary Installation
```bash
# Download latest release
curl -L https://github.com/sst/opencode/releases/latest/download/opencode-darwin-arm64 -o opencode
chmod +x opencode
sudo mv opencode /usr/local/bin/
```

## System Requirements

- **Operating Systems:** Linux, macOS, Windows (WSL2 recommended)
- **Terminal Emulators:** WezTerm, Alacritty, Kitty, Ghostty, or similar modern terminals
- **Dependencies:**
  - Node.js v16+ (for npm installation)
  - Git
  - Curl
  - Bun (optional, for faster package management)

## Configuration

### Configuration File Locations
- Global: `~/.config/opencode/opencode.json`
- Project: `./.opencode.json` (overrides global)
- Custom: via `OPENCODE_CONFIG` environment variable

### Basic Configuration Structure
```json
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "anthropic": {
      "apiKey": "{env:ANTHROPIC_API_KEY}",
      "disabled": false
    },
    "openai": {
      "apiKey": "{env:OPENAI_API_KEY}",
      "disabled": false
    }
  },
  "agents": {
    "coder": {
      "model": "claude-3-5-sonnet-20241022",
      "maxTokens": 8192
    }
  },
  "shell": {
    "path": "/bin/bash",
    "args": ["-l"]
  },
  "autoCompact": true
}
```

## Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `ANTHROPIC_API_KEY` | Anthropic Claude API access | Yes (or another provider) |
| `OPENAI_API_KEY` | OpenAI GPT API access | No |
| `GITHUB_TOKEN` | GitHub Copilot access | No |
| `GROQ_API_KEY` | Groq API access | No |
| `OPENCODE_CONFIG` | Custom config path | No |

## Project Initialization

1. Navigate to your project:
```bash
cd /path/to/project
```

2. Run OpenCode:
```bash
opencode
```

3. Initialize the project (creates `AGENTS.md`):
```
/init
```

## Usage Examples

### Basic Commands
- `/init` - Initialize project context
- `/undo` - Undo last changes
- `/redo` - Redo undone changes
- `/share` - Share conversation link
- `/help` - Show available commands

### Working Modes
- **Build Mode** (default) - AI can make code changes
- **Plan Mode** (Tab key) - AI only suggests changes without executing

### Example Prompts
```
# Ask questions
How is authentication handled in @packages/auth?

# Add features
Add a dark mode toggle to the settings page

# Refactor code
Refactor the database connection logic to use connection pooling

# Debug issues
Debug why the login flow fails on mobile devices
```

## Team Deployment Best Practices

### 1. Shared Configuration
Create a project-level `.opencode.json` that's checked into version control:
```json
{
  "agents": {
    "default": {
      "model": "claude-3-5-sonnet-20241022",
      "maxTokens": 8192,
      "temperature": 0.7
    }
  },
  "permissions": {
    "edit": "ask",
    "shell": "ask"
  }
}
```

### 2. API Key Management
- Use environment variables for API keys
- Never commit API keys to source control
- Consider using a secrets manager for team environments
- Set up shared team API keys where appropriate

### 3. Permission Controls
Configure permissions to require approval for sensitive operations:
```json
{
  "permissions": {
    "edit": "ask",      // Require approval for file edits
    "shell": "ask",     // Require approval for shell commands
    "read": "allow"     // Allow reading files without approval
  }
}
```

### 4. Version Control Integration
- Always review AI-generated changes before committing
- Use meaningful commit messages
- Consider creating feature branches for AI-assisted work

### 5. Documentation
- Keep `AGENTS.md` updated with project-specific context
- Document AI usage patterns that work well for your codebase
- Share successful prompts with the team

## Troubleshooting

### Installation Issues
- **macOS:** May need to allow execution in System Preferences > Security & Privacy
- **Windows:** Use WSL2 or manually download binary
- **Linux:** Ensure proper permissions with `chmod +x`

### Common Problems
1. **"command not found":** Ensure installation directory is in PATH
2. **API key errors:** Check environment variables are set correctly
3. **Terminal compatibility:** Use a modern terminal emulator
4. **Performance issues:** Adjust `maxTokens` in configuration

## Integration with devenv

To integrate OpenCode with devenv, we'll add it as a package and configure the environment properly. See `devenv.md` for specific implementation details.

## Security Considerations

- Review all AI-generated code before execution
- Use permission controls for production environments
- Regularly rotate API keys
- Monitor API usage and costs
- Consider self-hosted models for sensitive codebases

## Resources

- [Official Documentation](https://opencode.ai/docs)
- [GitHub Repository](https://github.com/sst/opencode)
- [Provider Configuration](https://opencode.ai/docs/providers)
- [Custom Commands](https://opencode.ai/docs/commands)
- [Themes and Customization](https://opencode.ai/docs/themes)
