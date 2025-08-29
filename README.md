# 🏭 Factory Floor

A powerful development environment and workflow automation system that provides intelligent worktree management, AI agent integration, and comprehensive tooling for modern software development.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/americanservices/factory_floor.git
cd factory_floor

# Enter the development environment
devenv shell
# OR if you have direnv
direnv allow

# Create your first worktree
wt-new feat/my-feature

# Start working with AI assistance
agent-here
```

## 📋 Requirements

### System Requirements
- **macOS** or **Linux** (WSL2 on Windows)
- **Git** 2.20+ (for worktree support)
- **10GB** free disk space

### Required Software

#### 1. Install Nix
Nix is the foundation of our reproducible development environment.

```bash
# Official Nix installer
sh <(curl -L https://nixos.org/nix/install) --daemon
```

#### 2. Install Devenv
Devenv provides a declarative development environment on top of Nix.

```bash
# Install devenv
nix-env -iA nixpkgs.devenv

# Or using cachix (recommended for faster builds)
nix-env -iA cachix -f https://cachix.org/api/v1/install
cachix use devenv
nix-env -if https://github.com/cachix/devenv/tarball/latest
```

#### 3. Install Direnv (Optional but Recommended)
Direnv automatically loads the development environment when you enter the project directory.

```bash
# Install via Nix
nix-env -iA nixpkgs.direnv

# Add to your shell (.bashrc, .zshrc, etc.)
eval "$(direnv hook bash)"  # for bash
eval "$(direnv hook zsh)"   # for zsh
```

### API Keys (Required for AI Features)
API keys are managed securely within the devenv shell:
- **ANTHROPIC_API_KEY** - For Claude AI integration
- **OPENAI_API_KEY** - For GPT models (optional)
- **EXA_API_KEY** - For web search capabilities (optional)

**Important:** Set up secrets using `secrets-setup` command after entering the shell.

## 🛠️ Installation

### For New Projects

To add Factory Floor to a new project:

```bash
# 1. Navigate to your project
cd /path/to/your/project

# 2. Initialize Factory Floor using the flake template
nix flake init -t github:americanservices/factory_floor

# 3. Enter the development environment
devenv shell
# OR with direnv
direnv allow

# 4. Initialize the project structure
dev-setup  # Creates directories and initial configuration

# 5. Set up secrets for AI features
secrets-setup  # Configure API keys securely
```

### For Existing Factory Floor Users

```bash
# 1. Clone the repository
git clone https://github.com/americanservices/factory_floor.git
cd factory_floor

# 2. Enter the development environment
devenv shell
# OR with direnv
direnv allow

# 3. Configure Git Town (for branch management)
gt-setup

# 4. Set up API keys (if using AI features)
export ANTHROPIC_API_KEY="your-key-here"
# OR use 1Password integration
op-login
secrets-dev
```

## ✨ Features

### 📁 Worktree Management
Efficiently manage multiple feature branches without switching contexts.

- **Semantic branch naming** - Enforced conventions (feat/, fix/, docs/, etc.)
- **Nested worktrees** - Create hierarchical branch structures
- **Automatic context preservation** - Each worktree maintains its own context
- **Quick navigation** - Jump between worktrees with `wt-cd`

```bash
# Create a new feature worktree
wt-new feat/authentication

# List all worktrees
wt-list

# Navigate between worktrees (interactive)
wt-cd

# Clean up merged worktrees
wt-clean
```

### 🤖 AI Agent Integration
Leverage AI to accelerate development with context-aware assistance.

- **Claude AI integration** - Built-in support for Anthropic's Claude
- **Issue-driven development** - Automatically implement GitHub issues
- **Context preservation** - AI agents understand your project structure
- **Container isolation** - AI agents run in Dagger containers for safety

```bash
# Start AI agent for a GitHub issue
agent-start 123

# Start AI agent in current worktree
agent-here

# Check agent status
agent-status

# Full issue-to-PR workflow
issue-to-pr 123
```

### 🔌 MCP Server Support
Model Context Protocol servers provide additional capabilities to AI agents.

- **Web search** - Exa API integration
- **Documentation access** - Context7 integration
- **Code execution** - Python sandbox
- **Browser automation** - Playwright support

```bash
# Start MCP servers
mcp-start

# Check server status
mcp-status

# Stop all servers
mcp-stop
```

### 🐳 Containerization with Dagger
Run tools and tests in isolated, reproducible environments.

- **Automatic container builds** - Define once, run anywhere
- **Dependency caching** - Fast rebuilds
- **Cross-platform support** - Works on macOS, Linux, and WSL
- **CI/CD integration** - Same containers locally and in CI

### 🔐 1Password Integration
Secure secret management with 1Password CLI.

```bash
# Login to 1Password
op-login

# Interactive secret browser
op-secrets

# Export secrets as environment variables
op-env "Development" "API Keys"

# Get specific secret
op-get "Development" "GitHub" password
```

### 🌳 Git Town Integration
Advanced Git workflow management with automatic branch relationships.

```bash
# Sync all worktrees with their parents
wt-sync-all

# Ship current branch (merge + cleanup)
wt-ship

# Park branch (pause syncing)
wt-park

# Mark as prototype (local-only)
wt-prototype
```

## 📚 Usage Examples

### Creating a New Worktree

```bash
# Simple feature branch
wt-new feat/user-authentication

# Nested branch (stacked on another feature)
wt-new feat/oauth feat/user-authentication

# Hotfix branch
wt-new hotfix/security-patch
```

### Starting an AI Agent

```bash
# For a specific GitHub issue
agent-start 42

# In current worktree with custom task
agent-here
# Then provide task description when prompted

# Continue previous conversation
cd worktrees/feat/my-feature
npx @anthropic-ai/claude-code --continue
```

### Complete Issue-to-PR Workflow

```bash
# Automated workflow for issue #123
issue-to-pr 123
# This will:
# 1. Create appropriate worktree
# 2. Start AI agent with issue context
# 3. Run tests
# 4. Create pull request
```

### Using the TUI

```bash
# Launch the interactive DevFlow interface
devflow

# Navigate with arrow keys
# Select actions with Enter
# Quick actions with hotkeys (shown in UI)
```

### Managing Secrets

```bash
# Setup development secrets from 1Password
secrets-dev

# Manual API key setup
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."

# Source from environment file
source .env.dev
```

## 🏗️ Development (For Factory Floor Contributors)

If you want to contribute to Factory Floor itself:

### Project Structure

```
factory_floor/
├── devenv.nix          # Main Nix configuration
├── devenv.yaml         # Devenv settings
├── devenv.lock         # Locked dependencies
├── .envrc              # Direnv configuration
├── CLAUDE.md           # AI agent instructions
├── devflow.py          # TUI application
└── worktrees/          # Git worktrees directory
```

### Building and Testing

```bash
# Enter development environment
devenv shell

# Run the test suite
stack-test

# Test a specific workflow
wt-new test/workflow-test
cd worktrees/test/workflow-test
# ... test your changes ...
wt-ship
```

### Adding New Features

1. Create a feature branch:
   ```bash
   wt-new feat/new-capability
   ```

2. Implement your feature in `devenv.nix`

3. Test thoroughly:
   ```bash
   # Test the new command
   your-new-command
   
   # Test in different scenarios
   wt-new test/edge-case
   ```

4. Create a PR:
   ```bash
   git push -u origin feat/new-capability
   gh pr create
   ```

### Debugging

```bash
# Enable debug output
set -x

# Check Nix build
nix-build

# Inspect environment
env | grep DEVENV

# Check script definitions
type wt-new
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Quick Contribution Guide

1. **Fork** the repository
2. **Create** a feature branch (`wt-new feat/amazing-feature`)
3. **Commit** your changes with conventional commits
4. **Push** to your fork
5. **Open** a Pull Request

## ❓ Frequently Asked Questions

### Secret Management Issues

**Q: I'm getting "secret not found" errors even though my API keys are in 1Password**

A: SecretSpec looks for items with specific titles in your vault. If you have existing 1Password items with different names (like "Exa MCP" instead of "EXA_API_KEY"), manually set the secret to create the properly named item:

```bash
# This will create/update the item with the correct title
secretspec set EXA_API_KEY
# Enter your API key when prompted

# Or copy from existing item
op item get "Exa MCP" --field credential | secretspec set EXA_API_KEY --stdin
```

**Q: SecretSpec says I'm not authenticated to 1Password**

A: Make sure you're signed in to 1Password CLI:

```bash
# Sign in (will prompt for password/biometrics)
eval $(op signin)

# Verify you're signed in
op whoami
```

**Q: How do I check which secrets are configured?**

A: Use the check command to see the status:

```bash
secretspec check  # Shows which required secrets are missing
```

**Q: Where are my secrets stored?**

A: Secrets are stored in your 1Password "development" vault (configured in `~/.config/secretspec/config.toml`). The items are named using the format `secretspec/{project}/{profile}/{key}` (e.g., `secretspec/factory-floor/development/OPENAI_API_KEY`).

## 📖 Documentation

- [Workflow Patterns](docs/workflows.md) - Common development workflows
- [AI Agent Guide](docs/ai-agents.md) - Using AI effectively
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [Command Reference](docs/commands.md) - Complete command documentation

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/americanservices/factory_floor/issues)
- **Discussions**: [GitHub Discussions](https://github.com/americanservices/factory_floor/discussions)
- **Quick Help**: Run `?` in the devenv shell for command reference

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

Factory Floor is built on top of excellent open-source projects:
- [Nix](https://nixos.org/) - Reproducible builds and deployments
- [Devenv](https://devenv.sh/) - Developer environments powered by Nix
- [Git Town](https://git-town.com/) - High-level Git workflow
- [Dagger](https://dagger.io/) - Portable development pipelines
- [Anthropic Claude](https://anthropic.com/) - AI assistance
- [1Password CLI](https://1password.com/downloads/command-line/) - Secure secret management

---

<div align="center">
Built with ❤️ by the Factory Floor team
</div>
