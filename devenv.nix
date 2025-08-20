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
        echo "Branch naming convention: <type>/<description>"
        echo "Types: feat, fix, test, docs, chore, hotfix, refactor, perf, style, build, ci, revert"
        echo "Examples:"
        echo "  wt-new feat/auth-system"
        echo "  wt-new fix/login-timeout"
        echo "  wt-new feat/oauth feat/auth-system"
        exit 1
      fi
      
      BRANCH="$1"
      
      # Enforce semantic branch naming (unless it's a perennial branch)
      if ! echo "$BRANCH" | grep -qE '^(main|master|develop|staging|production)$'; then
        if ! echo "$BRANCH" | grep -qE '^(feat|fix|test|docs|chore|hotfix|refactor|perf|style|build|ci|revert)/'; then
          echo "❌ Branch name must follow semantic naming: <type>/<description>"
          echo "Valid types: feat, fix, test, docs, chore, hotfix, refactor, perf, style, build, ci, revert"
          echo "Example: feat/add-authentication"
          exit 1
        fi
      fi
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
      
      # Configure with git-town based on branch type
      cd "$WORKTREE_DIR"
      if echo "$BRANCH" | grep -qE '^(main|master|develop|staging|production)$'; then
        # Mark as perennial branch
        git town perennial-branch add "$BRANCH" 2>/dev/null || true
      else
        # Mark as feature branch
        git town hack 2>/dev/null || true
      fi
      cd - > /dev/null
      
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
    # GIT TOWN INTEGRATION
    # ============================================
    
    wt-sync-all.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🔄 Sync All: Update all worktrees from their parents (with remote push)"
      echo "📍 Run this from: ROOT of project (main worktree)"
      echo "💡 This command PULLS from remote and PUSHES changes"
      echo "============================================"
      
      # First sync main
      echo "📍 Syncing main branch..."
      git town sync
      
      # Get all worktrees
      git worktree list --porcelain | grep "^worktree " | cut -d' ' -f2 | while read -r worktree_path; do
        if [ "$worktree_path" != "$(pwd)" ]; then
          echo ""
          echo "📍 Syncing $worktree_path..."
          cd "$worktree_path"
          
          # Only sync if not parked
          if ! git town parked-branches | grep -q "$(git branch --show-current)"; then
            git town sync || echo "⚠️  Failed to sync $(basename "$worktree_path")"
          else
            echo "⏸️  Skipping parked branch"
          fi
        fi
      done
      
      echo ""
      echo "✅ All worktrees synced!"
    '';
    
    wt-local-merge.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🔀 Local Merge: Merge current branch into parent (no remote push)"
      echo "📍 Run this from: ANY worktree (will find parent automatically)"
      echo "════════════════════════════════════════════════════════════════"
      
      # Get current branch
      BRANCH=$(git branch --show-current)
      
      if [ -z "$BRANCH" ]; then
        echo "❌ Not on a branch"
        exit 1
      fi
      
      if echo "$BRANCH" | grep -qE '^(main|master|develop|staging|production)$'; then
        echo "❌ Cannot merge from perennial branch: $BRANCH"
        echo "💡 This command merges FROM child TO parent"
        exit 1
      fi
      
      # Get parent branch (fallback for older git-town)
      PARENT=$(git config "branch.$BRANCH.parent" 2>/dev/null || git config "git-town.main-branch" 2>/dev/null || echo "master")
      
      echo "🎯 Current branch: $BRANCH"
      echo "🎯 Target parent: $PARENT"
      echo ""
      
      # Save current position
      CURRENT_DIR=$(pwd)
      
      # Find parent worktree
      PARENT_WORKTREE=$(git worktree list | grep "\[$PARENT\]" | awk '{print $1}' | head -1)
      
      if [ -z "$PARENT_WORKTREE" ]; then
        echo "❌ Parent worktree not found for branch: $PARENT"
        echo "💡 Create parent worktree first: wt-new $PARENT"
        exit 1
      fi
      
      # Switch to parent worktree and merge
      echo "📁 Switching to parent worktree: $PARENT_WORKTREE"
      cd "$PARENT_WORKTREE"
      
      # Update parent from origin first
      echo "🔄 Updating parent from origin..."
      git fetch origin 2>/dev/null || true
      git merge origin/$PARENT --ff-only 2>/dev/null || echo "⚠️  Could not fast-forward parent (conflicts may exist)"
      
      # Merge child branch
      echo "🔀 Merging $BRANCH into $PARENT..."
      if git merge "$BRANCH" --no-ff -m "Local merge: '$BRANCH' → $PARENT
      
      This is a LOCAL merge only - no remote push.
      Run 'git push' when ready to publish."; then
        echo "✅ Successfully merged $BRANCH into $PARENT"
        echo "📝 Changes are LOCAL only in worktree: $PARENT_WORKTREE"
        echo "🚀 To publish: cd $PARENT_WORKTREE && git push"
      else
        echo "❌ Merge conflict! Resolve in: $PARENT_WORKTREE"
        echo "💡 After resolving: git add . && git commit"
        exit 1
      fi
      
      # Return to original directory
      cd "$CURRENT_DIR"
      echo "📍 Returned to: $CURRENT_DIR"
    '';
    
    wt-local-sync-all.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🔄 Local Sync All: Merge all child branches into parents (no remote push)"
      echo "📍 Run this from: ROOT of project (main worktree)"
      echo "💡 This command finds ALL worktrees and merges children into parents"
      echo "════════════════════════════════════════════════════════════════════════"
      
      # Check if we're in a git repo
      if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "❌ Not in a git repository"
        exit 1
      fi
      
      echo "🔍 Scanning for worktrees and branch relationships..."
      
      # Simple approach: find all worktrees and their branches
      declare -a all_branches=()
      declare -A branch_to_path=()
      declare -A branch_parents=()
      
      # Get all worktrees
      while IFS= read -r line; do
        if [[ $line =~ ^worktree[[:space:]]+(.+) ]]; then
          path="''${BASH_REMATCH[1]}"
          # Get branch for this worktree
          branch=$(git -C "$path" branch --show-current 2>/dev/null || "")
          if [ -n "$branch" ]; then
            all_branches+=("$branch")
            branch_to_path["$branch"]="$path"
            
            # Try to get parent (fallback for older git-town)
            parent=$(git -C "$path" config "branch.$branch.parent" 2>/dev/null || git -C "$path" config "git-town.main-branch" 2>/dev/null || "")
            if [ -n "$parent" ]; then
              branch_parents["$branch"]="$parent"
            fi
          fi
        fi
      done < <(git worktree list --porcelain)
      
      echo "📊 Found ''${#all_branches[@]} worktrees:"
      for branch in "''${all_branches[@]}"; do
        parent="''${branch_parents[$branch]:-main}"
        path="''${branch_to_path[$branch]}"
        echo "  • $branch → $parent (at $path)"
      done
      echo ""
      
      # Function to merge one branch into its parent
      merge_single() {
        local child_branch=$1
        local child_path="''${branch_to_path[$child_branch]}"
        local parent_branch="''${branch_parents[$child_branch]:-main}"
        local parent_path="''${branch_to_path[$parent_branch]:-}"
        
        # If parent path is empty, it might be main in root
        if [ -z "$parent_path" ]; then
          parent_path=$(git worktree list | grep "\[$parent_branch\]" | awk '{print $1}' | head -1)
        fi
        
        if [ -z "$parent_path" ]; then
          echo "  ⚠️  Parent worktree not found for $parent_branch (skipping $child_branch)"
          return
        fi
        
        echo "  🔀 Merging $child_branch → $parent_branch"
        echo "     From: $child_path"
        echo "     To:   $parent_path"
        
        cd "$parent_path"
        if git merge "$child_branch" --no-ff -m "Local sync: merge '$child_branch' into $parent_branch

This is a LOCAL merge from wt-local-sync-all.
No remote push performed."; then
          echo "     ✅ Merged successfully"
        else
          echo "     ❌ Merge conflict! Resolve manually in $parent_path"
        fi
      }
      
      # Sort branches by dependency (children first)
      echo "🔀 Starting local merges..."
      
      # Simple approach: merge all non-perennial branches
      for branch in "''${all_branches[@]}"; do
        if [[ ! "$branch" =~ ^(main|master|develop|staging|production)$ ]]; then
          merge_single "$branch"
        fi
      done
      
      echo ""
      echo "✅ Local sync complete! All changes are LOCAL only."
      echo "📝 Review integrated changes:"
      for branch in "''${all_branches[@]}"; do
        path="''${branch_to_path[$branch]}"
        echo "     cd $path && git log --oneline -5"
      done
      echo ""
      echo "🚀 To publish changes:"
      echo "     cd <worktree> && git push"
      echo "     OR use 'wt-ship' from specific worktrees"
    '';
    
    wt-ship.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🚢 Ship: Merge to parent + push to remote + cleanup worktree"
      echo "📍 Run this from: ANY child worktree (not main/master)"
      echo "💡 This PUSHES to remote and deletes the branch permanently"
      echo "═══════════════════════════════════════════════════════════"
      
      # Get current branch
      BRANCH=$(git branch --show-current)
      
      if [ -z "$BRANCH" ]; then
        echo "❌ Not on a branch"
        exit 1
      fi
      
      if echo "$BRANCH" | grep -qE '^(main|master|develop|staging|production)$'; then
        echo "❌ Cannot ship perennial branch: $BRANCH"
        echo "💡 Ship merges FROM child TO parent"
        exit 1
      fi
      
      echo "🎯 Shipping branch: $BRANCH"
      echo "⚠️  This will:"
      echo "   1. Sync with parent"
      echo "   2. Merge to parent" 
      echo "   3. Push to remote"
      echo "   4. Delete branch"
      echo "   5. Remove worktree"
      echo ""
      read -p "Continue? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborted"
        exit 1
      fi
      
      # First sync to get latest changes
      echo "🔄 Syncing with parent..."
      git town sync
      
      # Then ship the branch
      echo "🚢 Shipping to remote..."
      git town ship
      
      # Remove the worktree after shipping
      cd ..
      if [[ "$PWD" == */worktrees* ]]; then
        WORKTREE_NAME=$(basename "$OLDPWD")
        echo "🗑️  Removing worktree: $WORKTREE_NAME"
        git worktree remove "$WORKTREE_NAME" --force
      fi
      
      echo "✅ Ship complete! Branch merged and pushed to remote."
    '';
    
    wt-park.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "⏸️  Park: Pause syncing for current branch"
      echo "📍 Run this from: ANY worktree you want to pause"
      echo "💡 Parked branches are skipped by wt-sync-all"
      echo "═══════════════════════════════════════════════"
      
      # Park current branch (stop syncing)
      BRANCH=$(git branch --show-current)
      git town park
      echo "✅ Branch parked: $BRANCH"
      echo "📝 This branch will be skipped during sync operations"
      echo "🔄 To resume: cd here && git town hack"
    '';
    
    wt-observe.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "👀 Observe: Watch branch (pull updates, don't push)"
      echo "📍 Run this from: ANY worktree you want to observe"
      echo "💡 Good for monitoring someone else's branch"
      echo "══════════════════════════════════════════════════"
      
      # Observe current branch (sync but don't push)
      BRANCH=$(git branch --show-current)
      git town observe
      echo "✅ Branch set to observe mode: $BRANCH"
      echo "🔄 Will pull updates but won't push your changes"
      echo "🔄 To resume normal: cd here && git town hack"
    '';
    
    wt-contribute.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🤝 Contribute: Mark as contribution to someone else's branch"
      echo "📍 Run this from: ANY worktree where you're contributing"
      echo "💡 Good when adding to another person's feature branch"
      echo "════════════════════════════════════════════════════════════"
      
      # Mark as contribution branch
      BRANCH=$(git branch --show-current)
      git town contribute
      echo "✅ Branch marked as contribution: $BRANCH"
      echo "📝 Your commits will be rebased, not merged from parent"
      echo "🔄 To resume normal: cd here && git town hack"
    '';
    
    wt-prototype.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🧪 Prototype: Mark as local-only experimental branch"
      echo "📍 Run this from: ANY worktree for experiments"
      echo "💡 Prototype branches are never pushed to remote"
      echo "═══════════════════════════════════════════════════════"
      
      # Mark as prototype branch (local only)
      BRANCH=$(git branch --show-current)
      git town prototype
      echo "✅ Branch marked as prototype: $BRANCH"
      echo "📝 This branch will never be pushed to remote"
      echo "🔄 To make pushable: cd here && git town hack"
    '';
    
    gt-setup.exec = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🔧 Setting up Git Town..."
      
      # Interactive setup
      git town config setup
      
      # Set perennial branches
      git town perennial-branches add main master develop staging production 2>/dev/null || true
      
      echo "✅ Git Town configured!"
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
      
      # Determine branch type based on issue labels
      LABELS=$(gh issue view "$ISSUE" --json labels -q '.labels[].name' 2>/dev/null | tr '\n' ' ' || echo "")
      
      PREFIX="feat"
      if echo "$LABELS $ISSUE_TITLE" | grep -qiE 'bug|fix|error|broken'; then
        PREFIX="fix"
      elif echo "$LABELS $ISSUE_TITLE" | grep -qiE 'docs|documentation|readme'; then
        PREFIX="docs"
      elif echo "$LABELS $ISSUE_TITLE" | grep -qiE 'test|testing|spec'; then
        PREFIX="test"
      elif echo "$LABELS $ISSUE_TITLE" | grep -qiE 'chore|maintenance|dependency|dependencies'; then
        PREFIX="chore"
      elif echo "$LABELS $ISSUE_TITLE" | grep -qiE 'hotfix|urgent|critical'; then
        PREFIX="hotfix"
      fi
      
      # Create semantic branch name
      CLEAN_TITLE=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)
      BRANCH="$PREFIX/$ISSUE-$CLEAN_TITLE"
      
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
      if command -v dagger &> /dev/null && command -v python3 &> /dev/null && python3 -c "import dagger" 2>/dev/null; then
        echo "🐳 Running AI agent in Dagger container..."
        
        # Ensure Dagger engine is running
        if ! dagger version &>/dev/null 2>&1; then
          echo "Starting Dagger engine..."
          dagger engine start || echo "Warning: Failed to start Dagger engine"
        fi
        
        # Use the helper script if it exists, otherwise create inline script
        if [ -f "run_dagger_agent.py" ]; then
          python3 "run_dagger_agent.py" \
            --source . \
            --context .context \
            --issue "$ISSUE"
        else
          # Fallback to inline Python script
          cat > /tmp/run-agent-$$.py << 'PYTHON_SCRIPT'
import asyncio
import dagger
import os
import sys

async def main():
    issue = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    
    async with dagger.Connection() as client:
        # Build container
        container = (
            client.container()
            .from_("ubuntu:22.04")
            .with_exec(["apt-get", "update"])
            .with_exec(["apt-get", "install", "-y", "git", "curl", "nodejs", "npm"])
            .with_mounted_directory("/workspace", client.host().directory("."))
            .with_workdir("/workspace")
        )
        
        # Add API key if available
        if os.getenv("ANTHROPIC_API_KEY"):
            container = container.with_env_variable("ANTHROPIC_API_KEY", os.getenv("ANTHROPIC_API_KEY"))
        
        # Run command
        result = await container.with_exec([
            "bash", "-c", f"echo 'Working on issue #{issue}'"
        ]).stdout()
        print(result)

if __name__ == "__main__":
    asyncio.run(main())
PYTHON_SCRIPT
          
          python3 /tmp/run-agent-$$.py "$ISSUE"
          rm -f /tmp/run-agent-$$.py
        fi
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
      if command -v dagger &> /dev/null && command -v python3 &> /dev/null && python3 -c "import dagger" 2>/dev/null; then
        echo "🐳 Running AI agent in Dagger container..."
        
        # Ensure Dagger engine is running
        if ! dagger version &>/dev/null 2>&1; then
          echo "Starting Dagger engine..."
          dagger engine start || echo "Warning: Failed to start Dagger engine"
        fi
        
        # Use the helper script if it exists, otherwise create inline script
        if [ -f "run_dagger_agent.py" ]; then
          if [ -n "$CONTEXT_FILES" ]; then
            python3 "run_dagger_agent.py" \
              --source . \
              --context .context
          else
            python3 "run_dagger_agent.py" \
              --source . \
              --task "$TASK"
          fi
        else
          # Fallback to inline Python script
          cat > /tmp/run-agent-here-$$.py << 'PYTHON_SCRIPT'
import asyncio
import dagger
import os
import sys

async def main():
    branch = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    
    async with dagger.Connection() as client:
        # Build container
        container = (
            client.container()
            .from_("ubuntu:22.04")
            .with_exec(["apt-get", "update"])
            .with_exec(["apt-get", "install", "-y", "git", "curl", "nodejs", "npm"])
            .with_mounted_directory("/workspace", client.host().directory("."))
            .with_workdir("/workspace")
        )
        
        # Add API key if available
        if os.getenv("ANTHROPIC_API_KEY"):
            container = container.with_env_variable("ANTHROPIC_API_KEY", os.getenv("ANTHROPIC_API_KEY"))
        
        # Run command
        result = await container.with_exec([
            "bash", "-c", f"echo 'Working in branch {branch}'"
        ]).stdout()
        print(result)

if __name__ == "__main__":
    asyncio.run(main())
PYTHON_SCRIPT
          
          python3 /tmp/run-agent-here-$$.py "$CURRENT_BRANCH"
          rm -f /tmp/run-agent-here-$$.py
        fi
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
      
      # Check if user wants specific topic
      TOPIC="''${1:-}"
      
      case "$TOPIC" in
        ship|shipping)
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "   🚢 Shipping Workflow Guide"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo ""
          echo "What 'shipping' means:"
          echo "  Merging your feature branch into its parent branch"
          echo "  and cleaning up (deleting branch + worktree)"
          echo ""
          echo "When to use wt-ship:"
          echo "  ✓ Solo work on small features"
          echo "  ✓ Parent branch owner approved"
          echo "  ✓ Hotfixes needing immediate merge"
          echo ""
          echo "When to use PR instead:"
          echo "  ✓ Need code review from team"
          echo "  ✓ Complex/critical features"
          echo "  ✓ Company requires PR approval"
          echo ""
          echo "Ship workflow:"
          echo "  1. cd worktrees/feat/my-feature"
          echo "  2. git add -A && git commit -m 'feat: ...'"
          echo "  3. wt-ship  # Syncs, merges, cleans up"
          echo ""
          echo "PR workflow:"
          echo "  1. git push -u origin feat/my-feature"
          echo "  2. gh pr create"
          echo "  3. After approval: wt-ship"
          ;;
        
        workflow|flow)
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "   📈 Daily Workflow Pattern"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo ""
          echo "Morning:"
          echo "  wt-sync-all              # Get latest from all parents"
          echo "  wt-stack                 # View branch structure"
          echo ""
          echo "Starting new work:"
          echo "  issue-to-pr 123          # Auto workflow from issue"
          echo "  # OR manually:"
          echo "  wt-new feat/feature-name # Create worktree"
          echo "  cd worktrees/feat/feature-name"
          echo ""
          echo "During development:"
          echo "  git add -A && git commit # Regular commits"
          echo "  git town sync            # Sync with parent"
          echo ""
          echo "Branch states:"
          echo "  wt-park                  # Pause work (skip syncing)"
          echo "  wt-prototype             # Local-only experiments"
          echo "  wt-observe               # Watch branch (no push)"
          echo "  wt-contribute            # Contributing to others"
          echo ""
          echo "Completing work:"
          echo "  wt-ship                  # Merge & cleanup"
          echo "  # OR"
          echo "  gh pr create             # Create PR for review"
          ;;
        
        naming|branches)
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "   🏷️  Branch Naming Convention"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo ""
          echo "Required format: <type>/<description>"
          echo ""
          echo "Types:"
          echo "  feat/     - New features"
          echo "  fix/      - Bug fixes"
          echo "  test/     - Test additions/changes"
          echo "  docs/     - Documentation only"
          echo "  chore/    - Maintenance tasks"
          echo "  hotfix/   - Urgent production fixes"
          echo "  refactor/ - Code restructuring"
          echo "  perf/     - Performance improvements"
          echo "  style/    - Code style changes"
          echo "  build/    - Build system changes"
          echo "  ci/       - CI/CD changes"
          echo "  revert/   - Revert previous changes"
          echo ""
          echo "Examples:"
          echo "  feat/user-authentication"
          echo "  fix/login-timeout-issue"
          echo "  docs/api-endpoints"
          echo "  chore/update-dependencies"
          ;;
        
        local|integration)
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "   🔀 Local Integration Workflow"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo ""
          echo "Problem: Multiple AI agents working in parallel"
          echo "Solution: Merge locally first, test, then push"
          echo ""
          echo "Commands:"
          echo "  wt-local-merge     - Merge 1 branch to parent (local only)"
          echo "  wt-local-sync-all  - Merge ALL branches (local only)"
          echo ""
          echo "Workflow example:"
          echo "  # Start multiple agents"
          echo "  agent-start 101  # Creates feat/search"
          echo "  agent-start 102  # Creates feat/filters"
          echo "  agent-start 103  # Creates fix/pagination"
          echo ""
          echo "  # Test integration locally"
          echo "  wt-local-sync-all"
          echo "  # This merges all into main locally"
          echo ""
          echo "  # Test everything"
          echo "  npm test"
          echo ""
          echo "  # If good, publish"
          echo "  git push"
          echo ""
          echo "Key difference:"
          echo "  wt-ship        = merge + push + delete (permanent)"
          echo "  wt-local-merge = merge only (test first)"
          echo ""
          echo "Run locations:"
          echo "  wt-local-merge     → from ANY child worktree"
          echo "  wt-local-sync-all  → from ROOT project directory"
          ;;
        
        *)
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "   🏭 AI Factory Floor - Command Reference"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo ""
          echo "📚 Worktree Management:"
          echo "  wt-new <type>/<name> [parent] - Create semantic branch"
          echo "  wt-list                        - List all worktrees"
          echo "  wt-cd                          - Interactive switcher"
          echo "  wt-clean                       - Remove merged worktrees"
          echo "  wt-stack                       - Show branch hierarchy"
          echo ""
          echo "🔄 Git Town - Remote Sync & Ship:"
          echo "  wt-sync-all      (from ROOT)   - Sync all with remote"
          echo "  wt-ship          (from child)  - Ship to remote + cleanup"
          echo "  wt-park          (from any)    - Pause syncing"
          echo "  wt-observe       (from any)    - Watch only (no push)"
          echo "  wt-contribute    (from any)    - Mark as contribution"
          echo "  wt-prototype     (from any)    - Mark as local-only"
          echo ""
          echo "🔀 Local Integration (No Remote Push):"
          echo "  wt-local-merge     (from child) - Merge to parent locally"
          echo "  wt-local-sync-all  (from ROOT)  - Merge all children locally"
          echo ""
          echo "🤖 AI Agent Commands:"
          echo "  agent-start <issue#>           - Auto-create semantic branch"
          echo "  agent-here                     - Start agent in current"
          echo "  issue-to-pr <issue#>           - Complete AI workflow"
          echo ""
          echo "🔌 MCP Servers:"
          echo "  mcp-status                     - Check server status"
          echo "  mcp-start/stop                 - Manual control"
          echo ""
          echo "🎨 Tools:"
          echo "  devflow                        - Launch visual TUI"
          echo "  gt-setup                       - Configure Git Town"
          echo ""
          echo "📖 Help Topics:"
          echo "  ? workflow                     - Daily workflow guide"
          echo "  ? shipping                     - When/how to ship branches"
          echo "  ? naming                       - Branch naming rules"
          echo "  ? local                        - Local integration workflow"
          echo ""
          echo "💡 Multi-Agent Workflow:"
          echo "  1. agent-start 101, 102, 103   - Start multiple agents"
          echo "  2. wt-local-sync-all           - Test integration locally"
          echo "  3. Fix conflicts if any        - Resolve issues"
          echo "  4. git push (from ROOT)        - Publish when ready"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          ;;
      esac
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
    
    # Check and start Dagger engine if needed
    if command -v dagger &>/dev/null; then
      if ! dagger version &>/dev/null; then
        echo "🐳 Starting Dagger engine..."
        dagger engine start &>/dev/null || echo "⚠️  Failed to start Dagger engine"
      else
        echo "✅ Dagger engine is running"
      fi
    fi
    
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
    echo "  Git Town:    wt-sync-all, wt-ship, wt-park, wt-observe, wt-contribute, wt-prototype"
    echo "  AI Agents:   agent-start, agent-here, agent-status"
    echo "  Workflow:    issue-to-pr <issue#>"
    echo "  MCP:         mcp-start, mcp-status, mcp-stop"
    echo "  Stack:       stack-status, stack-test"
    echo "  TUI:         devflow"
    echo "  Setup:       gt-setup (configure Git Town)"
    echo ""
    echo "💡 Tips:"
    echo "  • Branch naming: feat/, fix/, test/, docs/, chore/, hotfix/, etc."
    echo "  • Use 'wt-sync-all' to sync all worktrees with their parents"
    echo "  • Use 'wt-ship' to merge and cleanup current worktree"
    echo "  • Run 'issue-to-pr 123' for complete workflow"
    echo "  • Check 'CLAUDE.md' for AI instructions"
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
