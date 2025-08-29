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
          rust.enable = false;    # Enable as needed
          go.enable = false;    # Enable as needed
      };

      # Allow unfree packages (required for 1Password CLI)
      # Configure allowUnfree via devenv.yaml (see below)

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
      
      # Security & secret management
      _1password  # 1Password CLI (op)
    ];

    # Git hooks configuration - disabled for now
    # pre-commit.hooks = {
    #    prettier.enable = true;
    #    eslint.enable = true;
    #    black.enable = true;
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
        
        # Check if worktree directory already exists
        if [ -d "$WORKTREE_DIR" ]; then
          echo "⚠️    Directory already exists: $WORKTREE_DIR"
          echo "🧹 Cleaning up..."
          
          # Remove from git worktree list if it exists
          if git worktree list | grep -q "$WORKTREE_DIR"; then
            git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
          fi
          
          # Remove directory if it still exists
          rm -rf "$WORKTREE_DIR" 2>/dev/null || true
          
          # Remove branch if it exists
          git branch -D "$BRANCH" 2>/dev/null || true
          
          # Remove git-town configuration for this branch
          git config --unset "branch.$BRANCH.parent" 2>/dev/null || true
          git config --unset "branch.$BRANCH.pushremote" 2>/dev/null || true
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
        fi
        # Note: New branches created with 'git worktree add -b' are automatically
        # configured as feature branches by git-town, so no need to run 'git town hack'
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
        if [ -n "${ZELLIJ:-}" ] && zellij list-sessions &>/dev/null; then
          zellij action new-tab --layout default --name "$BRANCH" --cwd "$WORKTREE_DIR" 2>/dev/null || true
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
            echo "    $rel_path ($branch)"
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
          if [ -n "''${ZELLIJ:-}" ] && zellij list-sessions &>/dev/null; then
            BRANCH=$(git branch --show-current)
            zellij action go-to-tab-name "$BRANCH" 2>/dev/null || \
              zellij action new-tab --layout default --name "$BRANCH" 2>/dev/null || true
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
            echo "    Removing merged worktree: $worktree (branch: $branch)"
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
                show_tree "$subdir" "''${prefix}│     "
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
              git town sync || echo "⚠️     Failed to sync $(basename "$worktree_path")"
            else
              echo "⏸️    Skipping parked branch"
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
        git merge origin/$PARENT --ff-only 2>/dev/null || echo "⚠️    Could not fast-forward parent (conflicts may exist)"
        
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
            echo "    ⚠️    Parent worktree not found for $parent_branch (skipping $child_branch)"
            return
          fi
          
          echo "  🔀 Merging $child_branch → $parent_branch"
          echo "     From: $child_path"
          echo "     To:   $parent_path"
          
          cd "$parent_path"
          if git merge "$child_branch" --no-ff -m "Local sync: merge '$child_branch' into $parent_branch

This is a LOCAL merge from wt-local-sync-all.
No remote push performed."; then
            echo "       ✅ Merged successfully"
          else
            echo "       ❌ Merge conflict! Resolve manually in $parent_path"
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
        echo "       cd <worktree> && git push"
        echo "       OR use 'wt-ship' from specific worktrees"
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
        echo "     1. Sync with parent"
        echo "     2. Merge to parent" 
        echo "     3. Push to remote"
        echo "     4. Delete branch"
        echo "     5. Remove worktree"
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
          echo "🗑️     Removing worktree: $WORKTREE_NAME"
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
      
      # ============================================
      # AUTOMATED MERGE AND CLEANUP COMMANDS
      # ============================================
      
      wt-merge-branch.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔀 Merge Branch: One-command merge with cleanup"
        echo "📍 Run this from: Parent worktree or ROOT project directory" 
        echo "💡 Merges specified branch into its parent with conflict resolution"
        echo "══════════════════════════════════════════════════════════════════"
        
        BRANCH_TO_MERGE="''${1:-}"
        if [ -z "$BRANCH_TO_MERGE" ]; then
          echo "Usage: wt-merge-branch <branch-name>"
          echo ""
          echo "Available branches:"
          git branch -a | grep -v HEAD | sed 's/^../  /'
          exit 1
        fi
        
        # Check if branch exists
        if ! git show-ref --verify --quiet "refs/heads/$BRANCH_TO_MERGE"; then
          if ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_TO_MERGE"; then
            echo "❌ Branch '$BRANCH_TO_MERGE' not found"
            exit 1
          fi
        fi
        
        # Get parent branch for the branch to merge
        PARENT_BRANCH=$(git config "branch.$BRANCH_TO_MERGE.parent" 2>/dev/null || git config "git-town.main-branch" 2>/dev/null || echo "master")
        
        echo "🎯 Branch to merge: $BRANCH_TO_MERGE"
        echo "🎯 Target parent: $PARENT_BRANCH"
        echo ""
        
        # Find worktrees
        CHILD_WORKTREE=$(git worktree list | grep "\[$BRANCH_TO_MERGE\]" | awk '{print $1}' | head -1)
        PARENT_WORKTREE=$(git worktree list | grep "\[$PARENT_BRANCH\]" | awk '{print $1}' | head -1)
        
        if [ -z "$PARENT_WORKTREE" ]; then
          echo "❌ Parent worktree not found for branch: $PARENT_BRANCH"
          echo "💡 Create parent worktree first: wt-new $PARENT_BRANCH"
          exit 1
        fi
        
        # Show preview
        echo "📋 Preview of changes to be merged:"
        if [ -n "$CHILD_WORKTREE" ]; then
          echo "    From: $CHILD_WORKTREE"
        fi
        echo "    To:   $PARENT_WORKTREE"
        
        # Show commit diff
        if git log --oneline "$PARENT_BRANCH..$BRANCH_TO_MERGE" --max-count=5 2>/dev/null | head -5; then
          echo ""
          echo "📝 Recent commits to merge:"
          git log --oneline "$PARENT_BRANCH..$BRANCH_TO_MERGE" --max-count=5 | sed 's/^/    /'
        fi
        echo ""
        
        # Confirmation
        read -p "Continue with merge? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "❌ Merge cancelled"
          exit 1
        fi
        
        # Save current directory
        ORIGINAL_DIR=$(pwd)
        
        # Switch to parent worktree
        cd "$PARENT_WORKTREE"
        
        # Update parent from origin
        echo "🔄 Updating parent from origin..."
        git fetch origin 2>/dev/null || true
        
        # Try fast-forward first
        if git merge "origin/$PARENT_BRANCH" --ff-only 2>/dev/null; then
          echo "✅ Parent fast-forwarded"
        else
          echo "⚠️  Could not fast-forward parent (may have local changes)"
        fi
        
        # Attempt merge
        echo "🔀 Merging $BRANCH_TO_MERGE into $PARENT_BRANCH..."
        if git merge "$BRANCH_TO_MERGE" --no-ff -m "feat: merge $BRANCH_TO_MERGE into $PARENT_BRANCH

Automated merge via wt-merge-branch command."; then
          echo "✅ Merge successful!"
          
          # Push to remote
          echo "📤 Pushing changes to remote..."
          if git push origin "$PARENT_BRANCH"; then
            echo "✅ Changes pushed to remote"
            
            # Cleanup: remove worktree and branch
            if [ -n "$CHILD_WORKTREE" ] && [ "$CHILD_WORKTREE" != "$PARENT_WORKTREE" ]; then
              echo "🧹 Cleaning up worktree and branch..."
              
              # Remove worktree
              echo "    Removing worktree: $CHILD_WORKTREE"
              git worktree remove "$CHILD_WORKTREE" --force 2>/dev/null || echo "⚠️  Could not remove worktree"
              
              # Delete branch
              echo "    Deleting branch: $BRANCH_TO_MERGE"  
              git branch -d "$BRANCH_TO_MERGE" 2>/dev/null || git branch -D "$BRANCH_TO_MERGE" 2>/dev/null || echo "⚠️  Could not delete branch"
              
              # Remove git-town config
              git config --unset "branch.$BRANCH_TO_MERGE.parent" 2>/dev/null || true
              git config --unset "branch.$BRANCH_TO_MERGE.pushremote" 2>/dev/null || true
            fi
            
            echo "✅ Merge and cleanup complete!"
          else
            echo "❌ Failed to push to remote"
            echo "💡 Merge completed locally, push manually when ready"
          fi
        else
          echo "❌ Merge conflict detected!"
          echo ""
          echo "🔧 Conflict resolution options:"
          echo "   1. Fix conflicts manually:"
          echo "      - Edit conflicted files"
          echo "      - git add <resolved-files>"
          echo "      - git commit"
          echo "   2. Use merge tool: git mergetool"
          echo "   3. Abort merge: git merge --abort"
          echo ""
          echo "📍 You are now in: $PARENT_WORKTREE"
          echo "🔄 After resolving, run this command again to complete cleanup"
          
          # Stay in the conflicted directory for user to resolve
          cd "$ORIGINAL_DIR"
          exit 1
        fi
        
        # Return to original directory
        cd "$ORIGINAL_DIR"
        echo "📍 Returned to: $ORIGINAL_DIR"
      '';
      
      wt-auto-clean.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🧹 Auto Clean: Intelligent cleanup of merged branches"
        echo "📍 Run this from: ROOT project directory"
        echo "💡 Finds merged branches and safely removes worktrees + branches"
        echo "═══════════════════════════════════════════════════════════════════"
        
        # Check if we're in git repo
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
          echo "❌ Not in a git repository"
          exit 1
        fi
        
        # Get main branch
        MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
        if ! git show-ref --verify --quiet "refs/remotes/origin/$MAIN_BRANCH"; then
          MAIN_BRANCH="master"
        fi
        
        echo "🎯 Main branch: $MAIN_BRANCH"
        echo "🔍 Scanning for merged branches..."
        echo ""
        
        # Get all worktrees and check which branches are merged
        declare -a branches_to_clean=()
        declare -a worktrees_to_remove=()
        
        git worktree list --porcelain | while IFS= read -r line; do
          if [[ $line =~ ^worktree[[:space:]]+(.+) ]]; then
            worktree_path="''${BASH_REMATCH[1]}"
            
            # Skip if it's the main worktree
            if [ "$worktree_path" = "$(git worktree list | head -1 | awk '{print $1}')" ]; then
              continue
            fi
            
            # Get branch for this worktree
            branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || "")
            if [ -z "$branch" ]; then
              continue
            fi
            
            # Skip if it's a perennial branch
            if echo "$branch" | grep -qE '^(main|master|develop|staging|production)$'; then
              continue
            fi
            
            # Check if branch is merged into main
            if git branch --merged "origin/$MAIN_BRANCH" 2>/dev/null | grep -q "^[[:space:]]*$branch$"; then
              echo "🔍 Found merged branch: $branch (worktree: $worktree_path)"
              branches_to_clean+=("$branch")
              worktrees_to_remove+=("$worktree_path")
            fi
          fi
        done
        
        # Read the arrays (bash limitation workaround)
        mapfile -t branches_to_clean < <(git worktree list --porcelain | while IFS= read -r line; do
          if [[ $line =~ ^worktree[[:space:]]+(.+) ]]; then
            worktree_path="''${BASH_REMATCH[1]}"
            if [ "$worktree_path" = "$(git worktree list | head -1 | awk '{print $1}')" ]; then
              continue
            fi
            branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || "")
            if [ -z "$branch" ] || echo "$branch" | grep -qE '^(main|master|develop|staging|production)$'; then
              continue
            fi
            if git branch --merged "origin/$MAIN_BRANCH" 2>/dev/null | grep -q "^[[:space:]]*$branch$"; then
              echo "$branch"
            fi
          fi
        done)
        
        mapfile -t worktrees_to_remove < <(git worktree list --porcelain | while IFS= read -r line; do
          if [[ $line =~ ^worktree[[:space:]]+(.+) ]]; then
            worktree_path="''${BASH_REMATCH[1]}"
            if [ "$worktree_path" = "$(git worktree list | head -1 | awk '{print $1}')" ]; then
              continue
            fi
            branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || "")
            if [ -z "$branch" ] || echo "$branch" | grep -qE '^(main|master|develop|staging|production)$'; then
              continue  
            fi
            if git branch --merged "origin/$MAIN_BRANCH" 2>/dev/null | grep -q "^[[:space:]]*$branch$"; then
              echo "$worktree_path"
            fi
          fi
        done)
        
        if [ ''${#branches_to_clean[@]} -eq 0 ]; then
          echo "✅ No merged branches found to clean up"
          exit 0
        fi
        
        echo ""
        echo "📋 Branches to clean up:"
        for i in "''${!branches_to_clean[@]}"; do
          branch="''${branches_to_clean[$i]}"
          worktree="''${worktrees_to_remove[$i]}"
          echo "   $((i+1)). $branch (worktree: $worktree)"
        done
        echo ""
        
        # Confirmation
        read -p "Clean up ''${#branches_to_clean[@]} merged branches? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "❌ Cleanup cancelled"
          exit 0
        fi
        
        echo "🧹 Starting cleanup..."
        
        # Clean up each branch
        for i in "''${!branches_to_clean[@]}"; do
          branch="''${branches_to_clean[$i]}"
          worktree_path="''${worktrees_to_remove[$i]}"
          
          echo "    Cleaning $branch..."
          
          # Remove worktree
          if git worktree remove "$worktree_path" --force 2>/dev/null; then
            echo "      ✅ Removed worktree: $worktree_path"
          else
            echo "      ⚠️  Could not remove worktree: $worktree_path"
          fi
          
          # Delete branch
          if git branch -d "$branch" 2>/dev/null; then
            echo "      ✅ Deleted branch: $branch"
          elif git branch -D "$branch" 2>/dev/null; then
            echo "      ✅ Force deleted branch: $branch"
          else
            echo "      ⚠️  Could not delete branch: $branch"
          fi
          
          # Remove git-town configuration
          git config --unset "branch.$branch.parent" 2>/dev/null || true
          git config --unset "branch.$branch.pushremote" 2>/dev/null || true
        done
        
        echo ""
        echo "✅ Auto cleanup complete!"
        echo "📊 Cleaned up ''${#branches_to_clean[@]} merged branches"
        echo "💡 Run 'wt-list' to see remaining worktrees"
      '';
      
      wt-ship-all.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🚢 Ship All: Batch ship multiple ready branches"
        echo "📍 Run this from: ROOT project directory"
        echo "💡 Scans for completed branches and ships them in dependency order"
        echo "══════════════════════════════════════════════════════════════════"
        
        # Check if we're in git repo
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
          echo "❌ Not in a git repository"
          exit 1
        fi
        
        echo "🔍 Scanning for ready-to-ship branches..."
        
        # Get all worktrees
        declare -a candidate_branches=()
        declare -a candidate_worktrees=()
        
        while IFS= read -r line; do
          if [[ $line =~ ^worktree[[:space:]]+(.+) ]]; then
            worktree_path="''${BASH_REMATCH[1]}"
            
            # Skip main worktree
            if [ "$worktree_path" = "$(git worktree list | head -1 | awk '{print $1}')" ]; then
              continue
            fi
            
            branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || "")
            if [ -z "$branch" ]; then
              continue
            fi
            
            # Skip perennial branches
            if echo "$branch" | grep -qE '^(main|master|develop|staging|production)$'; then
              continue
            fi
            
            # Check if branch has any commits (is ready to ship)
            parent_branch=$(git -C "$worktree_path" config "branch.$branch.parent" 2>/dev/null || git config "git-town.main-branch" 2>/dev/null || echo "master")
            
            if git log --oneline "$parent_branch..$branch" --max-count=1 2>/dev/null | grep -q .; then
              candidate_branches+=("$branch")
              candidate_worktrees+=("$worktree_path")
            fi
          fi
        done < <(git worktree list --porcelain)
        
        if [ ''${#candidate_branches[@]} -eq 0 ]; then
          echo "✅ No branches ready to ship found"
          echo "💡 Branches need commits to be eligible for shipping"
          exit 0
        fi
        
        echo ""
        echo "📋 Ready-to-ship branches found:"
        for i in "''${!candidate_branches[@]}"; do
          branch="''${candidate_branches[$i]}"
          worktree="''${candidate_worktrees[$i]}"
          parent_branch=$(git -C "$worktree" config "branch.$branch.parent" 2>/dev/null || echo "main")
          commit_count=$(git log --oneline "$parent_branch..$branch" 2>/dev/null | wc -l || echo "0")
          
          echo "   $((i+1)). $branch → $parent_branch ($commit_count commits)"
          echo "      Path: $worktree"
          
          # Show latest commit
          latest_commit=$(git -C "$worktree" log --oneline -1 2>/dev/null | head -1 || echo "")
          if [ -n "$latest_commit" ]; then
            echo "      Latest: $latest_commit"
          fi
          echo ""
        done
        
        # Interactive selection
        echo "📝 Select branches to ship:"
        echo "   (a)ll branches"
        echo "   (s)elect specific branches"
        echo "   (n)one - cancel"
        echo ""
        read -p "Choice (a/s/n): " -n 1 -r
        echo
        
        declare -a branches_to_ship=()
        declare -a worktrees_to_ship=()
        
        case $REPLY in
          [Aa])
            branches_to_ship=("''${candidate_branches[@]}")
            worktrees_to_ship=("''${candidate_worktrees[@]}")
            ;;
          [Ss])
            echo ""
            for i in "''${!candidate_branches[@]}"; do
              branch="''${candidate_branches[$i]}"
              read -p "Ship $branch? (y/n): " -n 1 -r
              echo
              if [[ $REPLY =~ ^[Yy]$ ]]; then
                branches_to_ship+=("$branch")
                worktrees_to_ship+=("''${candidate_worktrees[$i]}")
              fi
            done
            ;;
          *)
            echo "❌ Shipping cancelled"
            exit 0
            ;;
        esac
        
        if [ ''${#branches_to_ship[@]} -eq 0 ]; then
          echo "❌ No branches selected for shipping"
          exit 0
        fi
        
        echo ""
        echo "🚢 Shipping ''${#branches_to_ship[@]} branches in order..."
        echo ""
        
        # Ship each branch
        for i in "''${!branches_to_ship[@]}"; do
          branch="''${branches_to_ship[$i]}"
          worktree_path="''${worktrees_to_ship[$i]}"
          
          echo "📦 Shipping branch $((i+1))/''${#branches_to_ship[@]}: $branch"
          echo "    From: $worktree_path"
          
          # Change to worktree directory
          cd "$worktree_path"
          
          # Check for uncommitted changes
          if [ -n "$(git status --porcelain)" ]; then
            echo "    ⚠️  Found uncommitted changes, committing..."
            git add -A
            git commit -m "chore: final changes before shipping

Automated commit from wt-ship-all command." || echo "    ⚠️  Could not commit changes"
          fi
          
          # Sync first
          echo "    🔄 Syncing with parent..."
          if git town sync; then
            echo "    ✅ Sync successful"
            
            # Ship the branch
            echo "    🚢 Shipping to remote..."
            if git town ship; then
              echo "    ✅ Ship successful: $branch"
              
              # Clean up worktree after shipping (git-town should handle this, but let's be safe)
              if [ -d "$worktree_path" ]; then
                echo "    🧹 Cleaning up worktree..."
                cd ..
                if [[ "$PWD" == */worktrees* ]]; then
                  WORKTREE_NAME=$(basename "$worktree_path")
                  git worktree remove "$WORKTREE_NAME" --force 2>/dev/null || echo "    ⚠️  Could not remove worktree"
                fi
              fi
            else
              echo "    ❌ Ship failed for: $branch"
              echo "    💡 Resolve issues manually in: $worktree_path"
            fi
          else
            echo "    ❌ Sync failed for: $branch"
            echo "    💡 Resolve conflicts manually in: $worktree_path"
          fi
          
          echo ""
        done
        
        # Return to project root
        cd "$(git rev-parse --show-toplevel)"
        
        echo "✅ Batch shipping complete!"
        echo "📊 Attempted to ship ''${#branches_to_ship[@]} branches"
        echo "💡 Run 'wt-list' to see remaining worktrees"
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
        
        # Check if worktree already exists and clean up if needed
        WORKTREE_DIR="worktrees/$BRANCH"
        if [ -d "$WORKTREE_DIR" ]; then
          echo "⚠️    Worktree already exists: $WORKTREE_DIR"
          echo "🧹 Cleaning up existing worktree..."
          
          # Remove from git worktree list if it exists
          if git worktree list | grep -q "$WORKTREE_DIR"; then
            git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
          fi
          
          # Remove directory if it still exists
          rm -rf "$WORKTREE_DIR" 2>/dev/null || true
          
          # Remove branch if it exists
          git branch -D "$BRANCH" 2>/dev/null || true
          
          # Remove git-town configuration for this branch
          git config --unset "branch.$BRANCH.parent" 2>/dev/null || true
          git config --unset "branch.$BRANCH.pushremote" 2>/dev/null || true
        fi
        
        # Create worktree
        wt-new "$BRANCH"

        
        # Save issue context
        CONTEXT_DIR="worktrees/$BRANCH/.context"
        mkdir -p "$CONTEXT_DIR"
        echo "$CONTEXT_DIR/issue-$ISSUE.md"
        echo $CONTEXT_DIR/issue-$ISSUE.md
        cat > "$CONTEXT_DIR/issue-$ISSUE.md" <<EOF
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
          echo "📦 Using Claude Code CLI via npx..."
          
          # Create or switch to zellij tab for this agent
          if [ -n "${ZELLIJ:-}" ] && zellij list-sessions &>/dev/null; then
            echo "🖥️ Opening agent in new zellij tab: agent-$ISSUE"
            zellij action new-tab --layout default --name "agent-$ISSUE" --cwd "worktrees/$BRANCH"
            # Give claude initial context in the new tab
            sleep 0.5
            # Check if continuing existing conversation or starting new one
            if [ -f "worktrees/$BRANCH/.claude/conversation.json" ] || [ -f "worktrees/$BRANCH/.claude_history" ]; then
              zellij action write-chars "npx @anthropic-ai/claude-code --continue\n"
            else
              zellij action write-chars "npx @anthropic-ai/claude-code \"Read .context/issue-$ISSUE.md and implement the solution. Follow the team workflow in CLAUDE.md. Commit your changes with conventional commits referencing #$ISSUE.\"\n"
            fi
          else
            echo "Context: Issue #$ISSUE in worktree $BRANCH"
            echo "──────────────────────────────────────────────────"
            # Check if there's an existing conversation to continue
            if [ -f ".claude/conversation.json" ] || [ -f ".claude_history" ]; then
              npx @anthropic-ai/claude-code --continue
            else
              echo "Starting new Claude session..."
              npx @anthropic-ai/claude-code "Read .context/issue-$ISSUE.md and implement the solution. Follow the team workflow in CLAUDE.md. Commit your changes with conventional commits referencing #$ISSUE."
            fi
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

        echo "CAMBIO"
        
        # Initialize variables
        CONTEXT_FILES=""
        TASK=""
        
        # Check if we have context
        if [ -d ".context" ]; then
          echo "📋 Found existing context"
          CONTEXT_FILES=$(ls .context/*.md 2>/dev/null || echo "")
          # Extract task from existing context if available
          if [ -n "$CONTEXT_FILES" ]; then
            TASK="Continue work based on context in .context/"
          fi
        else
          mkdir -p .context
          echo "📝 Creating context for $CURRENT_BRANCH"
          
          # Prompt for context
          echo "What should the AI work on in this worktree?"
          read -r TASK
          
          {
            echo "# Task for $CURRENT_BRANCH"
            echo ""
            echo "## Description"
            echo "$TASK"
            echo ""
            echo "## Created"
            date
            echo ""
            echo "## Branch"
            echo "$CURRENT_BRANCH"
          } > .context/task.md
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
          echo "📦 Using Claude Code CLI via npx..."
          
          # Create or switch to zellij tab for this agent
          if [ -n "${ZELLIJ:-}" ] && zellij list-sessions &>/dev/null; then
            echo "🖥️ Opening agent in new zellij tab: agent-$CURRENT_BRANCH"
            zellij action new-tab --layout default --name "agent-$CURRENT_BRANCH"
            # Give claude initial context in the new tab
            sleep 0.5
            # Check if continuing existing conversation or starting new one
            if [ -f ".claude/conversation.json" ] || [ -f ".claude_history" ]; then
              zellij action write-chars "npx @anthropic-ai/claude-code --continue\n"
            else
              if [ -n "$CONTEXT_FILES" ]; then
                zellij action write-chars "npx @anthropic-ai/claude-code \"Read the context in .context/ and work on the task. The current branch is $CURRENT_BRANCH.\"\n"
              else
                zellij action write-chars "npx @anthropic-ai/claude-code \"Task: $TASK. Branch: $CURRENT_BRANCH\"\n"
              fi
            fi
          else
            echo "Context: Current branch $CURRENT_BRANCH"
            echo "──────────────────────────────────────────────────"
            # Check if there's an existing conversation to continue
            if [ -f ".claude/conversation.json" ] || [ -f ".claude_history" ]; then
              npx @anthropic-ai/claude-code --continue
            else
              echo "Starting new Claude session..."
              if [ -n "$CONTEXT_FILES" ]; then
                npx @anthropic-ai/claude-code "Read the context in .context/ and work on the task. The current branch is $CURRENT_BRANCH."
              else
                npx @anthropic-ai/claude-code "Task: $TASK. Branch: $CURRENT_BRANCH"
              fi
            fi
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
            echo "    - $worktree_dir (branch: $branch, issue: #$issue_num)"
          fi
        done || echo "    No worktrees with context found"
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
                echo "    Stopping $SERVER (PID: $PID)"
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
            echo "    - $branch"
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
      # SECRETS MANAGEMENT & 1PASSWORD INTEGRATION
      # ============================================
      
      # Setup secrets from 1Password for MCP servers and other services
      secrets-setup.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        ENV="''${1:-dev}"
        
        echo "🔐 Secrets Setup for environment: $ENV"
        echo "══════════════════════════════════════════════"
        
        # Check if op is available
        if ! command -v op &> /dev/null; then
          echo "❌ 1Password CLI (op) not found"
          echo "💡 Run: nix develop or devenv shell"
          exit 1
        fi
        
        # Check authentication
        if ! op vault list &>/dev/null; then
          echo "🔑 Not authenticated with 1Password"
          echo "💡 Signing in..."
          op signin
          if [ $? -ne 0 ]; then
            echo "❌ Failed to sign in to 1Password"
            exit 1
          fi
        fi
        
        echo "✅ Authenticated with 1Password"
        echo ""
        
        # Define vault and item names based on environment
        case "$ENV" in
          dev|development)
            VAULT="Development"
            ;;
          prod|production)
            VAULT="Production"
            ;;
          staging)
            VAULT="Staging"
            ;;
          *)
            echo "❌ Unknown environment: $ENV"
            echo "💡 Valid environments: dev, staging, prod"
            exit 1
            ;;
        esac
        
        echo "📦 Using vault: $VAULT"
        echo ""
        
        # Initialize variables with empty defaults to avoid unbound variable errors
        CONTEXT7_API_KEY=""
        EXA_API_KEY=""
        ANTHROPIC_API_KEY=""
        OPENAI_API_KEY=""
        GEMINI_API_KEY=""
        
        # Export MCP server credentials
        echo "🔌 Setting up MCP server credentials..."
        
        # Context7 MCP
        if op item get "Context7 MCP" --vault="$VAULT" &>/dev/null; then
          echo "  • Context7 MCP credentials"
          CONTEXT7_API_KEY=$(op item get "Context7 MCP" --vault="$VAULT" --fields="API_KEY" 2>/dev/null || echo "")
        else
          echo "  ⚠️ Context7 MCP item not found in vault"
        fi
        
        # Exa MCP (Web Search)
        if op item get "Exa MCP" --vault="$VAULT" &>/dev/null; then
          echo "  • Exa MCP credentials"
          EXA_API_KEY=$(op item get "Exa MCP" --vault="$VAULT" --fields="API_KEY" 2>/dev/null || echo "")
        else
          echo "  ⚠️ Exa MCP item not found in vault"
        fi
        
        # AI API Key (Single item for all AI services)
        if op item get "AI API Key" --vault="$VAULT" &>/dev/null; then
          echo "  • AI API Key"
          AI_API_KEY=$(op item get "AI API Key" --vault="$VAULT" --fields="API_KEY" 2>/dev/null || echo "")
          # Set all AI service variables to the same key
          ANTHROPIC_API_KEY="$AI_API_KEY"
          OPENAI_API_KEY="$AI_API_KEY"
          GEMINI_API_KEY="$AI_API_KEY"
        else
          echo "  ⚠️ AI API Key item not found in vault"
        fi
        
        # Additional MCP servers can be added here
        # Example:
        # if op item get "Custom MCP" --vault="$VAULT" &>/dev/null; then
        #   echo "  • Custom MCP credentials"
        #   export CUSTOM_MCP_URL=$(op item get "Custom MCP" --vault="$VAULT" --fields="URL" 2>/dev/null || echo "")
        #   export CUSTOM_MCP_TOKEN=$(op item get "Custom MCP" --vault="$VAULT" --fields="TOKEN" 2>/dev/null || echo "")
        # fi
        
        echo ""
        
        # Write environment file for persistence
        ENV_FILE=".env.$ENV"
        echo "💾 Writing environment file: $ENV_FILE"
        cat > "$ENV_FILE" <<EOF
# MCP Server Credentials - $ENV environment
# Generated: $(date)
# DO NOT COMMIT THIS FILE

# Context7 MCP
CONTEXT7_API_KEY="$CONTEXT7_API_KEY"

# Exa MCP (Web Search)
EXA_API_KEY="$EXA_API_KEY"

# AI API Key (used for all AI services)
ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
OPENAI_API_KEY="$OPENAI_API_KEY"
GEMINI_API_KEY="$GEMINI_API_KEY"

# Additional MCP servers can be configured here
EOF
        
        # Update .gitignore if needed
        if ! grep -q "^\.env\." .gitignore 2>/dev/null; then
          echo ".env.*" >> .gitignore
          echo "📝 Added .env.* to .gitignore"
        fi
        
        echo ""
        echo "✅ Secrets setup complete for $ENV environment!"
        echo ""
        echo "🎯 Next steps:"
        echo "  1. Source the environment: source $ENV_FILE"
        echo "  2. Start MCP servers: mcp-start"
        echo "  3. Verify with: mcp-status"
        echo ""
        echo "💡 To use in a new shell:"
        echo "     source $ENV_FILE"
        echo ""
        echo "🔒 Security notes:"
        echo "  • Never commit $ENV_FILE"
        echo "  • Secrets expire with 1Password session"
        echo "  • Re-run this command to refresh"
      '';
      
      # Quick alias for common dev setup
      secrets-dev.exec = ''
        exec secrets-setup dev
      '';
      
      # ============================================
      # 1PASSWORD INTEGRATION
      # ============================================
      
      # Login to 1Password and setup session
      op-login.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔐 1Password Login"
        echo "=================="
        
        # Check if op is available
        if ! command -v op &> /dev/null; then
          echo "❌ 1Password CLI (op) not found"
          echo "💡 Make sure devenv is loaded properly"
          exit 1
        fi
        
        # Check if already signed in
        if op account list &>/dev/null; then
          echo "✅ Already signed in to 1Password"
          
          # List accounts
          echo ""
          echo "📋 Available accounts:"
          op account list --format=table
          echo ""
          
          # Check session status
          if op vault list &>/dev/null; then
            echo "✅ Session is active"
            echo "💡 Use 'op-secrets' to retrieve secrets"
          else
            echo "⚠️ Session expired. Please authenticate:"
            op signin
          fi
        else
          echo "🔑 Signing in to 1Password..."
          echo "💡 This will open your browser for authentication"
          op signin
          
          if [ $? -eq 0 ]; then
            echo "✅ Successfully signed in!"
            echo "📋 Available accounts:"
            op account list --format=table
          else
            echo "❌ Sign-in failed"
            exit 1
          fi
        fi
        
        echo ""
        echo "🎯 Next steps:"
        echo "  • op-secrets              - Interactive secret retrieval"
        echo "  • op-env <vault> <item>    - Export secrets as env vars"
        echo "  • op-status               - Check connection status"
      '';
      
      # Alias for consistency  
      "1pass-login".exec = ''
        exec op-login "$@"
      '';
      
      # Interactive secret browser and retrieval
      op-secrets.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔍 1Password Secret Browser"
        echo "==========================="
        
        # Check authentication
        if ! op vault list &>/dev/null; then
          echo "❌ Not authenticated with 1Password"
          echo "💡 Run 'op-login' first"
          exit 1
        fi
        
        # Interactive vault selection
        echo "📁 Available vaults:"
        VAULT=$(op vault list --format=json | jq -r '.[].name' | fzf --height=40% --reverse --header="Select vault:")
        
        if [ -z "$VAULT" ]; then
          echo "❌ No vault selected"
          exit 1
        fi
        
        echo "📦 Selected vault: $VAULT"
        echo ""
        
        # Interactive item selection
        echo "🔍 Items in $VAULT:"
        ITEM=$(op item list --vault="$VAULT" --format=json | jq -r '.[] | "\(.title) (\(.category))"' | fzf --height=40% --reverse --header="Select item:")
        
        if [ -z "$ITEM" ]; then
          echo "❌ No item selected"
          exit 1
        fi
        
        # Extract title from selection
        ITEM_TITLE=$(echo "$ITEM" | sed 's/ ([^)]*)$//')
        echo "🎯 Selected item: $ITEM_TITLE"
        echo ""
        
        # Show item details
        echo "📋 Item details:"
        op item get "$ITEM_TITLE" --vault="$VAULT" --format=json | jq -r '
          "Title: " + .title,
          "Category: " + .category,
          "Tags: " + (.tags // [] | join(", ")),
          "",
          "Fields:",
          (.fields // [] | map("  " + .label + ": " + (.value // "[hidden]")) | join("\n"))
        '
        
        echo ""
        echo "🎯 Available actions:"
        echo "  (c) Copy password to clipboard"
        echo "  (u) Copy username to clipboard"  
        echo "  (e) Export as environment variables"
        echo "  (j) Show full JSON"
        echo "  (q) Quit"
        echo ""
        read -p "Choice: " -n 1 -r
        echo
        
        case $REPLY in
          [Cc])
            if op item get "$ITEM_TITLE" --vault="$VAULT" --fields password &>/dev/null; then
              op item get "$ITEM_TITLE" --vault="$VAULT" --fields password | pbcopy
              echo "✅ Password copied to clipboard"
            else
              echo "❌ No password field found"
            fi
            ;;
          [Uu])
            if op item get "$ITEM_TITLE" --vault="$VAULT" --fields username &>/dev/null; then
              op item get "$ITEM_TITLE" --vault="$VAULT" --fields username | pbcopy
              echo "✅ Username copied to clipboard"
            else
              echo "❌ No username field found"
            fi
            ;;
          [Ee])
            echo "# Export these environment variables:"
            echo "# Source this file or copy the exports you need"
            echo ""
            op item get "$ITEM_TITLE" --vault="$VAULT" --format=json | jq -r '
              .fields[] | select(.value != null and .value != "") | 
              "export " + (.label | gsub("[^A-Za-z0-9_]"; "_") | ascii_upcase) + "=\"" + .value + "\""
            '
            ;;
          [Jj])
            echo "📄 Full JSON:"
            op item get "$ITEM_TITLE" --vault="$VAULT" --format=json | jq .
            ;;
          *)
            echo "👋 Goodbye!"
            ;;
        esac
      '';
      
      # Export secrets as environment variables
      op-env.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        VAULT="''${1:-}"
        ITEM="''${2:-}"
        
        if [ -z "$VAULT" ] || [ -z "$ITEM" ]; then
          echo "Usage: op-env <vault> <item>"
          echo ""
          echo "Export 1Password item fields as environment variables"
          echo ""
          echo "Examples:"
          echo "  op-env \"Development\" \"API Keys\"        # Export all fields from API Keys item"
          echo "  source <(op-env \"Development\" \"API Keys\") # Source directly into shell"
          echo ""
          echo "Available vaults:"
          if op vault list &>/dev/null; then
            op vault list --format=table
          else
            echo "❌ Not authenticated. Run 'op-login' first"
          fi
          exit 1
        fi
        
        # Check authentication
        if ! op vault list &>/dev/null; then
          echo "❌ Not authenticated with 1Password"
          echo "💡 Run 'op-login' first"
          exit 1
        fi
        
        echo "# 1Password environment variables from $VAULT/$ITEM"
        echo "# Generated on $(date)"
        echo ""
        
        # Export all fields as environment variables
        op item get "$ITEM" --vault="$VAULT" --format=json | jq -r '
          .fields[] | select(.value != null and .value != "") | 
          "export " + (.label | gsub("[^A-Za-z0-9_]"; "_") | ascii_upcase) + "=\"" + .value + "\""
        '
      '';
      
      # Check 1Password status and connection
      op-status.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔐 1Password Status"
        echo "=================="
        
        # Check if CLI is available
        if ! command -v op &> /dev/null; then
          echo "❌ 1Password CLI not found"
          echo "💡 Make sure devenv is loaded: 'devenv shell'"
          exit 1
        fi
        
        echo "✅ 1Password CLI found: $(op --version)"
        echo ""
        
        # Check authentication status
        if op account list &>/dev/null; then
          echo "✅ Authenticated accounts:"
          op account list --format=table
          echo ""
          
          # Check session status
          if op vault list &>/dev/null; then
            echo "✅ Active session"
            echo ""
            echo "📁 Available vaults:"
            op vault list --format=table
            echo ""
            echo "🎯 Ready to use 1Password!"
            echo "💡 Try: op-secrets (interactive browser)"
          else
            echo "⚠️ Authentication expired"
            echo "💡 Run: op signin"
          fi
        else
          echo "❌ Not signed in"
          echo "💡 Run: op-login"
        fi
        
        echo ""
        echo "📚 Available commands:"
        echo "  op-login      - Sign in to 1Password"
        echo "  op-secrets    - Interactive secret browser"  
        echo "  op-env        - Export secrets as env vars"
        echo "  op-status     - This status check"
      '';
      
      # Get specific secret (for scripting)
      op-get.exec = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        VAULT="''${1:-}"
        ITEM="''${2:-}"  
        FIELD="''${3:-password}"
        
        if [ -z "$VAULT" ] || [ -z "$ITEM" ]; then
          echo "Usage: op-get <vault> <item> [field]"
          echo ""
          echo "Get specific field from 1Password item"
          echo ""
          echo "Examples:"
          echo "  op-get \"Dev\" \"GitHub\" password     # Get password (default)"
          echo "  op-get \"Dev\" \"GitHub\" username     # Get username"
          echo "  op-get \"Dev\" \"API Keys\" \"api_key\"  # Get custom field"
          echo ""
          echo "💡 Use quotes around names with spaces"
          exit 1
        fi
        
        # Check authentication silently
        if ! op vault list &>/dev/null; then
          echo "❌ Not authenticated with 1Password" >&2
          echo "💡 Run 'op-login' first" >&2
          exit 1
        fi
        
        # Get the field value
        op item get "$ITEM" --vault="$VAULT" --fields="$FIELD" 2>/dev/null || {
          echo "❌ Could not retrieve $FIELD from $VAULT/$ITEM" >&2
          echo "💡 Check vault, item name, and field name" >&2
          exit 1
        }
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
        echo "    1. wt-new <branch>        - Create new worktree"
        echo "    2. issue-to-pr <#>        - Complete issue workflow"
        echo "    3. mcp-start            - Start MCP servers"
        echo "    4. agent-start <#>        - Start AI agent"
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
            echo "     🚢 Shipping Workflow Guide"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "What 'shipping' means:"
            echo "    Merging your feature branch into its parent branch"
            echo "    and cleaning up (deleting branch + worktree)"
            echo ""
            echo "When to use wt-ship:"
            echo "    ✓ Solo work on small features"
            echo "    ✓ Parent branch owner approved"
            echo "    ✓ Hotfixes needing immediate merge"
            echo ""
            echo "When to use PR instead:"
            echo "    ✓ Need code review from team"
            echo "    ✓ Complex/critical features"
            echo "    ✓ Company requires PR approval"
            echo ""
            echo "Ship workflow:"
            echo "    1. cd worktrees/feat/my-feature"
            echo "    2. git add -A && git commit -m 'feat: ...'"
            echo "    3. wt-ship    # Syncs, merges, cleans up"
            echo ""
            echo "PR workflow:"
            echo "    1. git push -u origin feat/my-feature"
            echo "    2. gh pr create"
            echo "    3. After approval: wt-ship"
            ;;
          
          workflow|flow)
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "     📈 Daily Workflow Pattern"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Morning:"
            echo "    wt-sync-all                 # Get latest from all parents"
            echo "    wt-stack                 # View branch structure"
            echo ""
            echo "Starting new work:"
            echo "    issue-to-pr 123             # Auto workflow from issue"
            echo "    # OR manually:"
            echo "    wt-new feat/feature-name # Create worktree"
            echo "    cd worktrees/feat/feature-name"
            echo ""
            echo "During development:"
            echo "    git add -A && git commit # Regular commits"
            echo "    git town sync             # Sync with parent"
            echo ""
            echo "Branch states:"
            echo "    wt-park                     # Pause work (skip syncing)"
            echo "    wt-prototype             # Local-only experiments"
            echo "    wt-observe                 # Watch branch (no push)"
            echo "    wt-contribute             # Contributing to others"
            echo ""
            echo "Completing work:"
            echo "    wt-ship                     # Merge & cleanup"
            echo "    # OR"
            echo "    gh pr create             # Create PR for review"
            ;;
          
          naming|branches)
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "     🏷️  Branch Naming Convention"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Required format: <type>/<description>"
            echo ""
            echo "Types:"
            echo "    feat/      - New features"
            echo "    fix/      - Bug fixes"
            echo "    test/      - Test additions/changes"
            echo "    docs/      - Documentation only"
            echo "    chore/      - Maintenance tasks"
            echo "    hotfix/      - Urgent production fixes"
            echo "    refactor/ - Code restructuring"
            echo "    perf/      - Performance improvements"
            echo "    style/      - Code style changes"
            echo "    build/      - Build system changes"
            echo "    ci/          - CI/CD changes"
            echo "    revert/      - Revert previous changes"
            echo ""
            echo "Examples:"
            echo "    feat/user-authentication"
            echo "    fix/login-timeout-issue"
            echo "    docs/api-endpoints"
            echo "    chore/update-dependencies"
            ;;
          
          1password|op)
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "     🔐 1Password Integration Guide"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Setup & Authentication:"
            echo "    op-login              - Sign in to 1Password (browser auth)"
            echo "    1pass-login           - Alias for op-login"
            echo "    op-status             - Check authentication and session status"
            echo ""
            echo "Interactive Usage:"
            echo "    op-secrets            - Browse vaults and items interactively"
            echo "                           Uses fzf for selection"
            echo "                           Copy to clipboard, export vars, etc."
            echo ""
            echo "Scripting & Automation:"
            echo "    op-get \"vault\" \"item\" [field]"
            echo "                          - Get specific secret value"
            echo "                          - Default field is 'password'"
            echo "    op-env \"vault\" \"item\""
            echo "                          - Export all fields as env variables"
            echo "    source <(op-env \"Dev\" \"API Keys\")"
            echo "                          - Source secrets directly into shell"
            echo ""
            echo "Common Workflows:"
            echo ""
            echo "    # First-time setup"
            echo "    op-login"
            echo ""
            echo "    # Interactive browsing"
            echo "    op-secrets"
            echo ""
            echo "    # Get API key for script"
            echo "    API_KEY=\$(op-get \"Development\" \"GitHub\" \"api_key\")"
            echo ""
            echo "    # Load all development secrets"
            echo "    source <(op-env \"Development\" \"Environment Variables\")"
            echo ""
            echo "Security Features:"
            echo "    • Authenticated sessions with automatic expiry"
            echo "    • No secrets stored in shell history"
            echo "    • Integration with 1Password's security model"
            echo "    • Works with existing 1Password accounts and vaults"
            echo ""
            echo "Integration with workflows:"
            echo "    • Use in AI agent workflows for secure API access"
            echo "    • Export secrets for CI/CD pipeline testing"
            echo "    • Manage development environment secrets"
            ;;
          
          secrets|mcp-secrets)
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "     🔌 MCP Server Secrets Setup"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Required 1Password Items:"
            echo ""
            echo "📦 Vault: Development (or your chosen vault)"
            echo ""
            echo "1️⃣ Context7 MCP (Documentation fetcher):"
            echo "    • API_KEY            - Context7 API key"
            echo "    Get from: https://context7.com/dashboard"
            echo ""
            echo "2️⃣ Exa MCP (Web search):"
            echo "    • API_KEY            - Exa API key for web search"
            echo "    Get from: https://dashboard.exa.ai/api-keys"
            echo ""
            echo "3️⃣ AI API Key (Single key for all AI services):"
            echo "    • API_KEY            - Used for Anthropic, OpenAI, and Gemini"
            echo "    Get from: Your AI provider dashboard"
            echo ""
            echo "Setup Commands:"
            echo "    secrets-setup [env]  - Full setup (dev/staging/prod)"
            echo "    secrets-dev          - Quick dev environment setup"
            echo ""
            echo "Setup Workflow:"
            echo "    1. Create items in 1Password:"
            echo "       op item create --category='API Credential' \\"
            echo "         --vault='Development' \\"
            echo "         --title='Context7 MCP' \\"
            echo "         API_KEY='...'"
            echo ""
            echo "       op item create --category='API Credential' \\"
            echo "         --vault='Development' \\"
            echo "         --title='Exa MCP' \\"
            echo "         API_KEY='...'"
            echo ""
            echo "    2. Run setup:"
            echo "       secrets-setup dev"
            echo ""
            echo "    3. Source environment:"
            echo "       source .env.dev"
            echo ""
            echo "    4. Start MCP servers:"
            echo "       mcp-start"
            echo ""
            echo "Available MCP Servers:"
            echo "    • context7   - Documentation fetcher"
            echo "    • exa        - Web search and research"
            echo "    • zen        - Multi-model AI collaboration"
            echo "    • playwright - Browser automation"
            echo "    • python     - Safe Python execution sandbox"
            echo "    • sequential - Structured problem-solving"
            echo ""
            echo "Verification:"
            echo "    mcp-status           - Check which servers are running"
            echo "    op-status            - Check 1Password connection"
            echo "    echo \$EXA_API_KEY    - Verify secret is loaded"
            ;;
          
          local|integration)
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "     🔀 Local Integration Workflow"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Problem: Multiple AI agents working in parallel"
            echo "Solution: Merge locally first, test, then push"
            echo ""
            echo "Commands:"
            echo "    wt-local-merge       - Merge 1 branch to parent (local only)"
            echo "    wt-local-sync-all  - Merge ALL branches (local only)"
            echo ""
            echo "Workflow example:"
            echo "    # Start multiple agents"
            echo "    agent-start 101     # Creates feat/search"
            echo "    agent-start 102     # Creates feat/filters"
            echo "    agent-start 103     # Creates fix/pagination"
            echo ""
            echo "    # Test integration locally"
            echo "    wt-local-sync-all"
            echo "    # This merges all into main locally"
            echo ""
            echo "    # Test everything"
            echo "    npm test"
            echo ""
            echo "    # If good, publish"
            echo "    git push"
            echo ""
            echo "Key difference:"
            echo "    wt-ship           = merge + push + delete (permanent)"
            echo "    wt-local-merge = merge only (test first)"
            echo ""
            echo "Run locations:"
            echo "    wt-local-merge       → from ANY child worktree"
            echo "    wt-local-sync-all  → from ROOT project directory"
            ;;
          
          *)
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "     🏭 AI Factory Floor - Command Reference"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "📚 Worktree Management:"
            echo "    wt-new <type>/<name> [parent] - Create semantic branch"
            echo "    wt-list                           - List all worktrees"
            echo "    wt-cd                           - Interactive switcher"
            echo "    wt-clean                       - Remove merged worktrees"
            echo "    wt-stack                       - Show branch hierarchy"
            echo ""
            echo "🔄 Git Town - Remote Sync & Ship:"
            echo "    wt-sync-all         (from ROOT)   - Sync all with remote"
            echo "    wt-ship             (from child)  - Ship to remote + cleanup"
            echo "    wt-park             (from any)       - Pause syncing"
            echo "    wt-observe         (from any)       - Watch only (no push)"
            echo "    wt-contribute     (from any)       - Mark as contribution"
            echo "    wt-prototype     (from any)       - Mark as local-only"
            echo ""
            echo "🔀 Local Integration (No Remote Push):"
            echo "    wt-local-merge       (from child) - Merge to parent locally"
            echo "    wt-local-sync-all  (from ROOT)    - Merge all children locally"
            echo ""
            echo "🚀 Automated Merge & Cleanup:"
            echo "    wt-merge-branch <branch> (from ROOT) - One-command merge with cleanup"
            echo "    wt-auto-clean            (from ROOT) - Intelligent cleanup of merged branches"
            echo "    wt-ship-all              (from ROOT) - Batch ship multiple ready branches"
            echo ""
            echo "🤖 AI Agent Commands:"
            echo "    agent-start <issue#>           - Auto-create semantic branch"
            echo "    agent-here                       - Start agent in current"
            echo "    issue-to-pr <issue#>           - Complete AI workflow"
            echo ""
            echo "🔌 MCP Servers:"
            echo "    mcp-status                       - Check server status"
            echo "    mcp-start/stop                   - Manual control"
            echo "    secrets-setup [env]              - Setup MCP secrets from 1Password"
            echo "    secrets-dev                      - Quick setup for dev environment"
            echo ""
            echo "🔐 1Password Integration:"
            echo "    op-login / 1pass-login           - Sign in to 1Password"
            echo "    op-status                        - Check authentication status"
            echo "    op-secrets                       - Interactive secret browser"
            echo "    op-env <vault> <item>           - Export secrets as env vars"
            echo "    op-get <vault> <item> [field]   - Get specific secret value"
            echo "    secrets-setup [env]              - Setup all MCP server secrets"
            echo ""
            echo "🎨 Tools:"
            echo "    devflow                           - Launch visual TUI"
            echo "    gt-setup                       - Configure Git Town"
            echo ""
            echo "📖 Help Topics:"
            echo "    ? workflow                       - Daily workflow guide"
            echo "    ? shipping                       - When/how to ship branches"
            echo "    ? naming                       - Branch naming rules"
            echo "    ? local                           - Local integration workflow"
            echo "    ? 1password                       - 1Password integration & usage"
            echo "    ? secrets                        - MCP server secrets setup"
            echo ""
            echo "💡 Multi-Agent Workflow:"
            echo "    1. agent-start 101, 102, 103   - Start multiple agents"
            echo "    2. wt-local-sync-all           - Test integration locally"
            echo "    3. Fix conflicts if any           - Resolve issues"
            echo "    4. git push (from ROOT)           - Publish when ready"
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
    #    enable = true;
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
            echo "    Starting $name..."
            eval "$cmd > .mcp/logs/$name.log 2>&1 &"
            echo $! > ".mcp/pids/$name.pid"
          else
            echo "    $name already running"
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
      echo "  Git Town:       wt-sync-all, wt-ship, wt-park, wt-observe, wt-contribute, wt-prototype"
      echo "  AI Agents:   agent-start, agent-here, agent-status"
      echo "  Workflow:       issue-to-pr <issue#>"
      echo "  MCP:           mcp-start, mcp-status, mcp-stop"
      echo "  1Password:   op-login, op-status, op-secrets, op-env, op-get"
      echo "  Stack:       stack-status, stack-test"
      echo "  TUI:           devflow"
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
