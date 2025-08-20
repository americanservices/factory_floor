{ pkgs, lib, config, inputs, ... }:

let
  # Just use plain Python, uv will handle packages
  pythonEnv = pkgs.python3;
in
{
  # Language and runtime support
  languages = {
    python.enable = true;
    python.package = pythonEnv;
    javascript.enable = true;
    typescript.enable = true;
    rust.enable = false;  # Enable as needed
    go.enable = false;    # Enable as needed
  };

  # Core packages
  packages = with pkgs; [
    # Version control
    git
    gh
    git-town
    
    # Container tools
    inputs.dagger.packages.${pkgs.system}.dagger
    
    # Terminal tools
    fzf
    ripgrep
    jq
    tree
    zellij  # Terminal multiplexer
    
    # AI/MCP tools
    nodejs_20
    uv  # Fast Python package manager
    
    # Development utilities
    direnv
    
    # Text processing
    bat
    fd
  ];

  # Git hooks configuration - disabled for now
  # pre-commit.hooks = {
  #   prettier.enable = true;
  #   eslint.enable = true;
  #   black.enable = true;
  # };

  # Custom scripts for workflow management
  scripts = {
    # ============================================
    # WORKTREE MANAGEMENT
    # ============================================
    
    wt-new.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      if [ $# -lt 1 ]; then
        echo "Usage: wt-new <branch-name> [parent-branch]"
        echo "Examples:"
        echo "  wt-new feat-auth"
        echo "  wt-new feat-auth-oauth feat-auth"
        exit 1
      fi
      
      BRANCH="$1"
      PARENT="''${2:-}"
      
      # Ensure we have at least one commit
      if ! git rev-parse HEAD &>/dev/null; then
        echo "📝 Creating initial commit..."
        git add -A || true
        git commit -m "Initial commit" || true
      fi
      
      # Determine base directory
      if [ -n "$PARENT" ] && [ -d "worktrees/$PARENT" ]; then
        # Nested worktree under parent
        WORKTREE_DIR="worktrees/$PARENT/$BRANCH"
        BASE_BRANCH="$PARENT"
      else
        # Top-level worktree
        WORKTREE_DIR="worktrees/$BRANCH"
        # Use current branch as base if no parent specified
        BASE_BRANCH="''${PARENT:-$(git branch --show-current || echo master)}"
      fi
      
      # Create the worktree
      echo "📁 Creating worktree at $WORKTREE_DIR from $BASE_BRANCH..."
      
      # Try different approaches based on what's available
      if git show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
        git worktree add -b "$BRANCH" "$WORKTREE_DIR" "origin/$BASE_BRANCH"
      elif git show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
        git worktree add -b "$BRANCH" "$WORKTREE_DIR" "$BASE_BRANCH"
      else
        # If base branch doesn't exist, use HEAD
        git worktree add -b "$BRANCH" "$WORKTREE_DIR" HEAD
      fi
      
      # Set up context directory
      mkdir -p "$WORKTREE_DIR/.context"
      echo "# Context for $BRANCH" > "$WORKTREE_DIR/.context/README.md"
      echo "Created from: $BASE_BRANCH" >> "$WORKTREE_DIR/.context/README.md"
      echo "Created at: $(date)" >> "$WORKTREE_DIR/.context/README.md"
      
      # Copy essential files
      cp -n CLAUDE.md "$WORKTREE_DIR/" 2>/dev/null || true
      cp -n .envrc "$WORKTREE_DIR/" 2>/dev/null || true
      cp -n devenv.nix "$WORKTREE_DIR/" 2>/dev/null || true
      cp -n devenv.yaml "$WORKTREE_DIR/" 2>/dev/null || true
      cp -n devenv.lock "$WORKTREE_DIR/" 2>/dev/null || true
      
      # Create zellij tab if in a zellij session
      if [ -n "${ZELLIJ:-}" ]; then
        zellij action new-tab --name "$BRANCH" --cwd "$WORKTREE_DIR" 2>/dev/null || true
      fi
      
      echo "✅ Worktree created at $WORKTREE_DIR"
      echo "💡 Run: cd $WORKTREE_DIR && devenv shell"
    '';
    
    wt-list.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "📊 Git Worktrees:"
      echo "=================="
      git worktree list | while read -r path branch commit; do
        # Get relative path
        rel_path=$(realpath --relative-to=. "$path" 2>/dev/null || echo "$path")
        
        # Check if it's current directory
        if [ "$path" = "$(pwd)" ]; then
          echo "→ $rel_path ($branch) [current]"
        else
          echo "  $rel_path ($branch)"
        fi
        
        # Show nested worktrees
        if [ -d "$path/worktrees" ]; then
          find "$path/worktrees" -maxdepth 2 -name ".git" -type f 2>/dev/null | while read -r nested; do
            nested_dir=$(dirname "$nested")
            nested_branch=$(git -C "$nested_dir" branch --show-current 2>/dev/null || echo "unknown")
            echo "    └─ $(basename "$nested_dir") ($nested_branch)"
          done
        fi
      done
    '';
    
    wt-cd.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      # Use fzf to select worktree
      WORKTREE=$(git worktree list | fzf --height=40% --reverse --header="Select worktree:" | awk '{print $1}')
      
      if [ -n "$WORKTREE" ]; then
        echo "📁 Switching to $WORKTREE"
        cd "$WORKTREE"
        
        # If zellij is running, switch to or create tab
        if [ -n "''${ZELLIJ:-}" ]; then
          BRANCH=$(git branch --show-current)
          zellij action go-to-tab-name "$BRANCH" 2>/dev/null || \
            zellij action new-tab --name "$BRANCH" 2>/dev/null || true
        fi
        
        exec $SHELL
      fi
    '';
    
    wt-clean.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🧹 Cleaning merged worktrees..."
      
      # Get list of merged branches
      MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
      
      git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2 | while read -r worktree; do
        if [ "$worktree" = "$(pwd)" ]; then
          continue  # Skip current worktree
        fi
        
        branch=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || continue)
        
        # Check if branch is merged
        if git branch -r --merged "$MAIN_BRANCH" 2>/dev/null | grep -q "origin/$branch"; then
          echo "  Removing merged worktree: $worktree (branch: $branch)"
          git worktree remove "$worktree" --force
        fi
      done
      
      echo "✅ Cleanup complete"
    '';
    
    wt-stack.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      # Visualize the stack structure
      echo "📚 Branch Stack Structure:"
      echo "=========================="
      
      # Function to show tree
      show_tree() {
        local dir="$1"
        local prefix="$2"
        
        if [ -d "$dir/worktrees" ]; then
          for subdir in "$dir/worktrees"/*; do
            if [ -d "$subdir" ]; then
              local branch=$(git -C "$subdir" branch --show-current 2>/dev/null || echo "unknown")
              local status=$(git -C "$subdir" status --porcelain 2>/dev/null | wc -l)
              
              echo "''${prefix}├─ $(basename "$subdir") [$branch] ($status changes)"
              show_tree "$subdir" "''${prefix}│  "
            fi
          done
        fi
      }
      
      # Start from main worktree
      echo "main"
      show_tree "." ""
    '';
    
    # ============================================
    # AI AGENT MANAGEMENT
    # ============================================
    
    agent-start.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      ISSUE="''${1:-}"
      if [ -z "$ISSUE" ]; then
        echo "Usage: agent-start <issue-number>"
        exit 1
      fi
      
      # Get issue details
      echo "📋 Fetching issue #$ISSUE..."
      ISSUE_TITLE=$(gh issue view "$ISSUE" --json title -q .title)
      ISSUE_BODY=$(gh issue view "$ISSUE" --json body -q .body)
      
      # Create branch name
      BRANCH="issue-$ISSUE-$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -c1-30)"
      
      # Create worktree
      wt-new "$BRANCH"
      
      # Save issue context
      CONTEXT_DIR="worktrees/$BRANCH/.context"
      mkdir -p "$CONTEXT_DIR"
      
      cat > "$CONTEXT_DIR/issue-$ISSUE.md" << EOF
      # Issue #$ISSUE: $ISSUE_TITLE
      
      ## Description
      $ISSUE_BODY
      
      ## Created
      $(date)
      
      ## Branch
      $BRANCH
      EOF
      
      # Start container with Claude
      echo "🤖 Starting AI agent for issue #$ISSUE..."
      
      cd "worktrees/$BRANCH"
      
      # Use Dagger for isolation if available, otherwise run locally
      if command -v dagger &> /dev/null && command -v python &> /dev/null; then
        echo "🐳 Running AI agent in Dagger container..."
        
        # Create Python script to run agent in Dagger
        cat > /tmp/run-agent-$$.py << 'PYTHON_SCRIPT'
import asyncio
import dagger
import os
import sys

async def main():
    issue = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    branch = sys.argv[2] if len(sys.argv) > 2 else "unknown"
    
    async with dagger.Connection() as client:
        # Build container with Claude CLI
        container = (
            client.container()
            .from_("node:20-slim")
            .with_exec(["apt-get", "update"])
            .with_exec(["apt-get", "install", "-y", "git", "curl"])
            .with_exec(["npm", "install", "-g", "@anthropic-ai/claude-code"])
            .with_mounted_directory("/workspace", client.host().directory("."))
            .with_workdir("/workspace")
        )
        
        # Add API key if available
        if os.getenv("ANTHROPIC_API_KEY"):
            container = container.with_env_variable("ANTHROPIC_API_KEY", os.getenv("ANTHROPIC_API_KEY"))
        
        # Run claude in interactive mode
        print(f"Starting Claude for issue #{issue} in isolated container...")
        await container.with_exec([
            "claude", "--continue"
        ]).stdout()

if __name__ == "__main__":
    asyncio.run(main())
PYTHON_SCRIPT
        
        python /tmp/run-agent-$$.py "$ISSUE" "$BRANCH"
        rm -f /tmp/run-agent-$$.py
      else
        # Fallback to local execution
        echo "💻 Starting Claude locally (install Dagger for isolation)..."
        
        # Install Claude Code CLI if not present
        if ! command -v claude &> /dev/null; then
          echo "📦 Installing Claude Code CLI..."
          npm install -g @anthropic-ai/claude-code
        fi
        
        # Create or switch to zellij tab for this agent
        if [ -n "${ZELLIJ:-}" ]; then
          echo "🖥️ Opening agent in new zellij tab: agent-$ISSUE"
          zellij action new-tab --name "agent-$ISSUE" --cwd "worktrees/$BRANCH"
          # Give claude initial context in the new tab
          zellij action write-chars "claude --continue\n"
          sleep 0.5
          zellij action write-chars "Read .context/issue-$ISSUE.md and implement the solution. Follow the team workflow in CLAUDE.md. Commit your changes with conventional commits referencing #$ISSUE.\n"
        else
          echo "Context: Issue #$ISSUE in worktree $BRANCH"
          echo "──────────────────────────────────────────────────"
          claude --continue
        fi
      fi
    '';
    
    # Start agent in current worktree
    agent-here.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      # Get current branch and worktree
      CURRENT_BRANCH=$(git branch --show-current)
      CURRENT_DIR=$(pwd)
      
      echo "🤖 Starting AI agent in current worktree: $CURRENT_BRANCH"
      
      # Check if we have context
      if [ -d ".context" ]; then
        echo "📋 Found existing context"
        CONTEXT_FILES=$(ls .context/*.md 2>/dev/null || echo "")
      else
        mkdir -p .context
        echo "📝 Creating context for $CURRENT_BRANCH"
        
        # Prompt for context
        echo "What should the AI work on in this worktree?"
        read -r TASK
        
        cat > .context/task.md << EOF
      # Task for $CURRENT_BRANCH
      
      ## Description
      $TASK
      
      ## Created
      $(date)
      
      ## Branch
      $CURRENT_BRANCH
      EOF
      fi
      
      # Use Dagger for isolation if available, otherwise run locally
      if command -v dagger &> /dev/null && command -v python &> /dev/null; then
        echo "🐳 Running AI agent in Dagger container..."
        
        # Create Python script to run agent in Dagger
        cat > /tmp/run-agent-here-$$.py << 'PYTHON_SCRIPT'
import asyncio
import dagger
import os
import sys

async def main():
    branch = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    
    async with dagger.Connection() as client:
        # Build container with Claude CLI
        container = (
            client.container()
            .from_("node:20-slim")
            .with_exec(["apt-get", "update"])
            .with_exec(["apt-get", "install", "-y", "git", "curl"])
            .with_exec(["npm", "install", "-g", "@anthropic-ai/claude-code"])
            .with_mounted_directory("/workspace", client.host().directory("."))
            .with_workdir("/workspace")
        )
        
        # Add API key if available
        if os.getenv("ANTHROPIC_API_KEY"):
            container = container.with_env_variable("ANTHROPIC_API_KEY", os.getenv("ANTHROPIC_API_KEY"))
        
        # Run claude in interactive mode
        print(f"Starting Claude in branch {branch} in isolated container...")
        await container.with_exec([
            "claude", "--continue"
        ]).stdout()

if __name__ == "__main__":
    asyncio.run(main())
PYTHON_SCRIPT
        
        python /tmp/run-agent-here-$$.py "$CURRENT_BRANCH"
        rm -f /tmp/run-agent-here-$$.py
      else
        # Fallback to local execution
        echo "💻 Starting Claude locally (install Dagger for isolation)..."
        
        # Install Claude Code CLI if not present
        if ! command -v claude &> /dev/null; then
          echo "📦 Installing Claude Code CLI..."
          npm install -g @anthropic-ai/claude-code
        fi
        
        # Create or switch to zellij tab for this agent
        if [ -n "${ZELLIJ:-}" ]; then
          echo "🖥️ Opening agent in new zellij tab: agent-$CURRENT_BRANCH"
          zellij action new-tab --name "agent-$CURRENT_BRANCH"
          # Give claude initial context in the new tab
          zellij action write-chars "claude --continue\n"
          sleep 0.5
          if [ -n "$CONTEXT_FILES" ]; then
            zellij action write-chars "Read the context in .context/ and work on the task. The current branch is $CURRENT_BRANCH.\n"
          else
            zellij action write-chars "Task: $TASK\nBranch: $CURRENT_BRANCH\n"
          fi
        else
          echo "Context: Current branch $CURRENT_BRANCH"
          echo "──────────────────────────────────────────────────"
          claude --continue
        fi
      fi
    '';
    
    agent-status.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🤖 Active AI Agents:"
      echo "==================="
      
      # Check docker containers
      if command -v docker &> /dev/null; then
        docker ps --filter "name=agent-" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null || true
      fi
      
      # Check worktrees with .context directories
      echo ""
      echo "📁 Worktrees with Context:"
      find worktrees -name ".context" -type d 2>/dev/null | while read -r context_dir; do
        worktree_dir=$(dirname "$context_dir")
        branch=$(git -C "$worktree_dir" branch --show-current 2>/dev/null || echo "unknown")
        
        # Check for issue file
        issue_file=$(find "$context_dir" -name "issue-*.md" -type f | head -1)
        if [ -n "$issue_file" ]; then
          issue_num=$(basename "$issue_file" .md | sed 's/issue-//')
          echo "  - $worktree_dir (branch: $branch, issue: #$issue_num)"
        fi
      done || echo "  No worktrees with context found"
    '';
    
    # ============================================
    # ISSUE TO PR WORKFLOW
    # ============================================
    
    issue-to-pr.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      ISSUE="''${1:-}"
      if [ -z "$ISSUE" ]; then
        echo "Usage: issue-to-pr <issue-number>"
        echo "This will:"
        echo "  1. Create a worktree for the issue"
        echo "  2. Run AI to implement the solution"
        echo "  3. Run tests"
        echo "  4. Create a pull request"
        exit 1
      fi
      
      echo "🚀 Starting issue-to-pr workflow for #$ISSUE"
      
      # Start the agent
      agent-start "$ISSUE"
      
      # Get the branch name
      ISSUE_TITLE=$(gh issue view "$ISSUE" --json title -q .title)
      BRANCH="issue-$ISSUE-$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -c1-30)"
      
      cd "worktrees/$BRANCH"
      
      # Run tests
      echo "🧪 Running tests..."
      if [ -f "package.json" ]; then
        npm test || echo "⚠️ Some tests failed"
      elif [ -f "Cargo.toml" ]; then
        cargo test || echo "⚠️ Some tests failed"
      elif [ -f "go.mod" ]; then
        go test ./... || echo "⚠️ Some tests failed"
      fi
      
      # Create PR if changes exist
      if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "feat: implement issue #$ISSUE
        
        $(gh issue view "$ISSUE" --json title -q .title)
        
        Closes #$ISSUE"
      fi
      
      # Push and create PR
      echo "📤 Creating pull request..."
      git push -u origin "$BRANCH"
      
      gh pr create \
        --title "Implement #$ISSUE: $ISSUE_TITLE" \
        --body "## Description
        
        Implements issue #$ISSUE
        
        ## Changes
        - Implementation based on issue requirements
        - Tests added/updated
        - Documentation updated
        
        ## Testing
        - [ ] All tests pass
        - [ ] Manual testing completed
        
        Closes #$ISSUE" \
        --assignee @me
      
      echo "✅ Workflow complete! PR created for issue #$ISSUE"
    '';
    
    # ============================================
    # MCP SERVER MANAGEMENT
    # ============================================
    
    mcp-start.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🔌 Starting MCP servers..."
      
      # Create MCP directory for sockets/logs
      mkdir -p .mcp/{pids,logs,sockets}
      
      # Start Context7 (documentation)
      if command -v npx &> /dev/null; then
        echo "  Starting Context7..."
        npx -y @upstash/context7-mcp > .mcp/logs/context7.log 2>&1 &
        echo $! > .mcp/pids/context7.pid
      fi
      
      # Start Playwright (browser automation)
      if command -v npx &> /dev/null; then
        echo "  Starting Playwright..."
        npx @playwright/mcp@latest --headless > .mcp/logs/playwright.log 2>&1 &
        echo $! > .mcp/pids/playwright.pid
      fi
      
      # Start Python sandbox
      if command -v deno &> /dev/null; then
        echo "  Starting Python sandbox..."
        deno run \
          -N -R=node_modules -W=node_modules --node-modules-dir=auto \
          jsr:@pydantic/mcp-run-python stdio > .mcp/logs/python.log 2>&1 &
        echo $! > .mcp/pids/python.pid
      fi
      
      # Start Sequential thinking
      if command -v npx &> /dev/null; then
        echo "  Starting Sequential thinking..."
        npx -y @modelcontextprotocol/server-sequential-thinking > .mcp/logs/sequential.log 2>&1 &
        echo $! > .mcp/pids/sequential.pid
      fi
      
      echo "✅ MCP servers started"
      echo "📊 View logs: tail -f .mcp/logs/*.log"
    '';
    
    mcp-stop.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🛑 Stopping MCP servers..."
      
      if [ -d ".mcp/pids" ]; then
        for pidfile in .mcp/pids/*.pid; do
          if [ -f "$pidfile" ]; then
            PID=$(cat "$pidfile")
            SERVER=$(basename "$pidfile" .pid)
            
            if kill -0 "$PID" 2>/dev/null; then
              echo "  Stopping $SERVER (PID: $PID)"
              kill "$PID"
            fi
            
            rm "$pidfile"
          fi
        done
      fi
      
      echo "✅ MCP servers stopped"
    '';
    
    mcp-status.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🔌 MCP Server Status:"
      echo "===================="
      
      declare -A servers=(
        ["context7"]="Context7 (Documentation)"
        ["playwright"]="Playwright (Browser)"
        ["python"]="Python Sandbox"
        ["sequential"]="Sequential Thinking"
        ["zen"]="Zen Multi-Model"
      )
      
      for server in "''${!servers[@]}"; do
        if [ -f ".mcp/pids/$server.pid" ]; then
          PID=$(cat ".mcp/pids/$server.pid")
          if kill -0 "$PID" 2>/dev/null; then
            echo "✅ ''${servers[$server]}: Running (PID: $PID)"
          else
            echo "❌ ''${servers[$server]}: Stopped (stale PID)"
          fi
        else
          echo "⭕ ''${servers[$server]}: Not started"
        fi
      done
    '';
    
    # ============================================
    # COLLABORATION TOOLS
    # ============================================
    
    stack-status.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "📚 Stack Status:"
      echo "==============="
      
      # Show current branch and its stack
      CURRENT=$(git branch --show-current)
      echo "Current: $CURRENT"
      echo ""
      
      # Show parent
      PARENT=$(git config "branch.$CURRENT.parent" 2>/dev/null || echo "main")
      echo "Parent: $PARENT"
      
      # Show children
      echo "Children:"
      git for-each-ref --format='%(refname:short)' refs/heads/ | while read -r branch; do
        branch_parent=$(git config "branch.$branch.parent" 2>/dev/null || "")
        if [ "$branch_parent" = "$CURRENT" ]; then
          echo "  - $branch"
        fi
      done
      
      # Show modifications
      echo ""
      echo "📝 Changes in stack:"
      git log --oneline "$PARENT..$CURRENT" 2>/dev/null | head -10 || echo "No changes yet"
    '';
    
    stack-test.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🧪 Testing stack integration..."
      
      CURRENT=$(git branch --show-current)
      PARENT=$(git config "branch.$CURRENT.parent" 2>/dev/null || echo "main")
      
      # Test against parent
      echo "Testing against parent ($PARENT)..."
      git merge-tree $(git merge-base HEAD "$PARENT") HEAD "$PARENT" > /dev/null 2>&1
      
      if [ $? -eq 0 ]; then
        echo "✅ No conflicts with parent"
      else
        echo "⚠️ Potential conflicts with parent"
      fi
      
      # Run tests
      if [ -f "package.json" ]; then
        npm test
      elif [ -f "Cargo.toml" ]; then
        cargo test
      elif [ -f "go.mod" ]; then
        go test ./...
      else
        echo "No test command found for this project"
      fi
    '';
    
    # ============================================
    # UTILITY FUNCTIONS
    # ============================================
    
    dev-setup.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🚀 Setting up development environment..."
      
      # Check prerequisites
      echo "Checking prerequisites..."
      
      command -v git >/dev/null 2>&1 || { echo "❌ git not found"; exit 1; }
      command -v docker >/dev/null 2>&1 || echo "⚠️ docker not found (optional)"
      command -v zellij >/dev/null 2>&1 || echo "⚠️ zellij not found (optional)"
      
      # Initialize git if needed
      if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Initializing git repository..."
        git init
      fi
      
      # Initialize git config
      echo "Configuring git..."
      git config alias.wt "worktree" || true
      git config alias.stack "!stack-status" || true
      
      # Create directory structure
      echo "Creating directory structure..."
      mkdir -p worktrees
      mkdir -p .context
      mkdir -p .mcp/{pids,logs,sockets}
      
      # Copy CLAUDE.md if not exists
      if [ ! -f "CLAUDE.md" ]; then
        echo "Creating CLAUDE.md..."
        touch CLAUDE.md
      fi
      
      echo "✅ Development environment ready!"
      echo ""
      echo "Quick start:"
      echo "  1. wt-new <branch>      - Create new worktree"
      echo "  2. issue-to-pr <#>      - Complete issue workflow"
      echo "  3. mcp-start            - Start MCP servers"
      echo "  4. agent-start <#>      - Start AI agent"
    '';
    
    # DevFlow TUI
    devflow.exec = ''
      #!/usr/bin/env bash
      # Use the venv Python if it exists, otherwise fallback to system
      if [ -f ".venv/bin/python" ]; then
        exec .venv/bin/python ${./devflow.py} "$@"
      else
        exec python ${./devflow.py} "$@"
      fi
    '';
    
    # Show help/quick reference
    "?".exec = ''
      #!/usr/bin/env bash
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "   🏭 AI Factory Floor - Command Reference"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "📚 Worktree Management:"
      echo "  wt-new <branch> [parent]  - Create new worktree"
      echo "  wt-list                   - List all worktrees"
      echo "  wt-cd                     - Interactive worktree switcher"
      echo "  wt-clean                  - Remove merged worktrees"
      echo "  wt-stack                  - Show branch stack structure"
      echo ""
      echo "🤖 AI Agent Commands:"
      echo "  agent-start <issue#>      - Create worktree & start agent for issue"
      echo "  agent-here                - Start agent in current worktree"
      echo "  agent-status              - Show active AI agents"
      echo ""
      echo "🔌 MCP Server Commands:"
      echo "  mcp-start                 - Start all MCP servers"
      echo "  mcp-status                - Check MCP server status"
      echo "  mcp-stop                  - Stop all MCP servers"
      echo ""
      echo "📊 Workflow Commands:"
      echo "  issue-to-pr <issue#>      - Complete workflow from issue to PR"
      echo "  stack-status              - Show current stack status"
      echo "  stack-test                - Test stack integration"
      echo ""
      echo "🎨 Tools:"
      echo "  devflow                   - Launch TUI interface"
      echo "  gt-setup                  - Configure Git Town"
      echo "  dev-setup                 - Initialize development environment"
      echo ""
      echo "💡 Tips:"
      echo "  • Use '?' anytime to see this help"
      echo "  • Nested worktrees: 'wt-new child-branch parent-branch'"
      echo "  • View logs: 'tail -f .mcp/logs/*.log'"
      echo "  • Set ANTHROPIC_API_KEY for AI features"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    '';
    
    # Git Town configuration helper
    gt-setup.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🏘️ Configuring Git Town..."
      
      # Set main branch
      git town config main-branch main || true
      
      # Set perennial branches
      git town config perennial-branches "main master develop staging" || true
      
      # Enable features
      git town config sync-before-ship true || true
      git town config ship-delete-tracking-branch true || true
      
      echo "✅ Git Town configured"
    '';
  };

  # Environment variables
  env = {
    # Workspace configuration
    WORKTREE_BASE = "worktrees";
    FACTORY_FLOOR_ROOT = builtins.toString ./.;
    
    # MCP configuration  
    MCP_CONFIG_PATH = ".mcp/config.json";
    
    # Zellij configuration
    ZELLIJ_CONFIG_DIR = ".config/zellij";
    
    # Git configuration
    GIT_TOWN_CONFIG = ".git-town";
    
    # AI configuration
    CLAUDE_CONTEXT_DIR = ".context";
    
    # Development
    EDITOR = "''${EDITOR:-vim}";
  };

  # Services - commented out for now, using git/filesystem for state
  # services.postgres = {
  #   enable = true;
  # };

  # Process management - MCP servers run automatically
  processes = {
    # MCP servers as background processes
    mcp-auto.exec = ''
      # Create directories if they don't exist
      mkdir -p .mcp/{pids,logs,sockets}
      
      echo "🔌 Starting MCP servers automatically..."
      
      # Only start servers that aren't already running
      start_server() {
        local name=$1
        local cmd=$2
        
        if [ ! -f ".mcp/pids/$name.pid" ] || ! kill -0 $(cat ".mcp/pids/$name.pid" 2>/dev/null) 2>/dev/null; then
          echo "  Starting $name..."
          eval "$cmd > .mcp/logs/$name.log 2>&1 &"
          echo $! > ".mcp/pids/$name.pid"
        else
          echo "  $name already running"
        fi
      }
      
      # Start each server if not running
      if command -v npx &> /dev/null; then
        start_server "context7" "npx -y @upstash/context7-mcp"
        start_server "sequential" "npx -y @modelcontextprotocol/server-sequential-thinking"
      fi
      
      if command -v deno &> /dev/null; then
        start_server "python" "deno run -N -R=node_modules -W=node_modules --node-modules-dir=auto jsr:@pydantic/mcp-run-python stdio"
      fi
      
      echo "✅ MCP servers started (check status with 'mcp-status')"
      
      # Keep process alive
      sleep infinity
    '';
  };

  # Shell hook - runs when entering devenv
  enterShell = ''
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   🏭 AI Factory Floor Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Set up Python virtual environment with uv
    if [ ! -d ".venv" ]; then
      echo "🐍 Creating Python virtual environment..."
      uv venv .venv
      echo "📦 Installing Python packages..."
      source .venv/bin/activate
      uv pip install rich gitpython aiofiles
      echo "✅ Python environment ready"
    else
      # Just activate if it already exists
      source .venv/bin/activate
    fi
    
    echo "📚 Quick Reference:"
    echo "  Worktrees:   wt-new, wt-list, wt-cd, wt-clean, wt-stack"
    echo "  AI Agents:   agent-start, agent-here, agent-status"
    echo "  Workflow:    issue-to-pr <issue#>"
    echo "  MCP:         mcp-start, mcp-status, mcp-stop"
    echo "  Stack:       stack-status, stack-test"
    echo "  TUI:         devflow"
    echo ""
    echo "💡 Tips:"
    echo "  • Use 'wt-new child parent' for nested worktrees"
    echo "  • Run 'issue-to-pr 123' for complete workflow"
    echo "  • Check 'CLAUDE.md' for AI instructions"
    echo "  • Python venv (.venv) is automatically activated"
    echo ""
    
    # Check for required API keys
    if [ -z "''${ANTHROPIC_API_KEY:-}" ]; then
      echo "⚠️  Warning: ANTHROPIC_API_KEY not set"
    fi
    
    # Initialize if first run
    if [ ! -d "worktrees" ]; then
      echo "🔧 First run detected. Initializing..."
      dev-setup
    fi
    
    # Show current worktree status
    if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
      BRANCH=$(git branch --show-current 2>/dev/null || echo "none")
      echo "📍 Current branch: $BRANCH"
      
      # Count worktrees
      WT_COUNT=$(git worktree list 2>/dev/null | wc -l || echo "0")
      echo "🌳 Active worktrees: $WT_COUNT"
    fi
    
    echo ""
    echo "Ready! Run 'wt-new <branch>' to start working."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';

  # Testing
  enterTest = ''
    echo "Running tests"
    git --version | grep --color=auto "${pkgs.git.version}"
  '';
}
