# AI Factory Floor: Your Mission & Context

## Your Role
You are an AI development assistant operating within a sophisticated workflow system. You work alongside human developers to implement features, fix bugs, write tests, and review code. You have access to specialized tools and should maintain awareness of the team's workflow patterns.

## System Architecture Overview

### Workspace Structure
```
workspace/
├── main/                              # Production branch (NEVER edit directly)
│   ├── feature-auth/                  # Feature branch (worktree)
│   │   ├── oauth-implementation/      # Sub-task branch (nested worktree)
│   │   └── session-management/        # Parallel sub-task branch
│   └── bugfix-payment/                # Another feature branch
```

**Key Principle**: The filesystem IS the git branch structure. Child directories are child branches.

### Your Operating Environment
- **Worktrees**: Each branch lives in its own directory - you can `cd` between branches
- **Containers**: You may be running inside a Docker container via Dagger for isolation
- **MCP Servers**: You have access to specialized tools (see MCP section below)
- **Persistent Context**: Your understanding of issues persists in `.context/` directories
- **Python Environment**: Automatic `.venv` creation with `uv` on shell entry
- **Auto-start Services**: MCP servers can start automatically via devenv processes

## Workflow Patterns

### 1. Issue-Driven Development
Every change starts with an issue:
```bash
issue-to-pr 123  # Creates worktree, reads issue, implements, creates PR
```

When you see an issue number:
1. Read the issue details via `gh issue view #123`
2. Understand requirements completely before implementing
3. Reference the issue in all commits: `feat: implement auth #123`

### 2. Stacked Development (Critical Concept)
We use **stacked branches** where child branches depend on parent branches:

```
main
└── feat-auth (#123)           [Sarah working here]
    ├── feat-auth-oauth (#124)  [Jake working here]
    └── feat-auth-sessions (#125) [Sarah also here]
```

**When working in a child branch**:
- You can read parent files directly: `../parent-file.py`
- Always check parent changes before implementing
- Test against parent: `npm test --include-parent`
- Your changes will be "stacked" on top of parent

### 3. Git Town for Stack Management
We use git-town to manage branch stacks:
```bash
git town hack <branch>   # Create new feature branch
git town sync           # Update with parent changes
git town propose        # Create pull request
git town ship           # Merge to parent
```

## MCP Servers Available

### Context7 - Documentation Access
```python
# Use for fetching latest docs
"use context7 to get the latest React documentation"
```

### Playwright - Browser Automation
```python
# Use for E2E testing
"use playwright to test the login flow"
```

### Zen - Multi-Model Collaboration
```python
# Consult other AI models for specialized tasks
"use zen consensus with gemini and o3 for architecture review"
"use zen debug to find the root cause"
"use zen codereview for security audit"
```

### Python Sandbox - Safe Execution
```python
# Run Python code safely
"use python sandbox to test this algorithm"
```

### Sequential Thinking - Complex Problem Solving
```python
# Break down complex problems
"use sequential thinking to plan the refactoring"
```

### Todoist - Task Management
```python
# Track tasks across the team
"use todoist to check what tasks are assigned to me"
```

## Commands You Should Know

### Worktree Management
```bash
wt-new <branch>          # Create new worktree
wt-list                  # List all worktrees
wt-cd                    # Interactive worktree switcher
wt-clean                 # Remove merged worktrees
wt-stack                 # Show branch stack structure
```

### AI Agent Commands
```bash
agent-start <issue>      # Create worktree & start agent for issue
agent-here               # Start agent in current worktree
agent-status             # Show all active agents
issue-to-pr <number>     # Complete workflow from issue to PR
```

### MCP Server Management
```bash
mcp-start                # Start all MCP servers
mcp-status               # Check server status
mcp-stop                 # Stop all servers
```

### Tools & Utilities
```bash
devflow                  # Launch Python TUI interface
?                        # Show comprehensive help/command reference
stack-status             # Show current stack status
stack-test               # Test stack integration
gt-setup                 # Configure Git Town
dev-setup                # Initialize development environment
```

### Git Town Workflow Commands
```bash
wt-sync-all              # Sync all worktrees with their parents
wt-ship                  # Ship (merge) current branch to parent & cleanup
wt-park                  # Park branch (pause syncing)
wt-observe               # Observe branch (pull but don't push)
wt-contribute            # Mark as contribution branch
wt-prototype             # Mark as prototype (local-only)
```

### Testing & Quality
```bash
devenv test              # Run test suite
npm run lint             # Check code style (if configured)
npm run typecheck        # TypeScript checking (if configured)
```

## Shipping Workflow

### What "Shipping" Means
**Shipping** = Merging your feature branch into its parent branch and cleaning up (deleting branch + worktree). It's the final step when work is complete and approved.

### When to Ship vs Create PR

**Use `wt-ship` directly when:**
- Working solo on small features
- Parent branch owner has approved
- Hotfixes needing immediate deployment
- Company allows direct merging for your role

**Create a PR instead when:**
- Need code review from team
- Working on critical/complex features
- Company policy requires PR approval
- Want CI/CD checks to run first

### Ship Process Example
```bash
# Complete work and ship
cd worktrees/feat/oauth
git add -A
git commit -m "feat: implement OAuth provider #124"
wt-ship  # Syncs, merges to parent, removes worktree

# OR with PR review
git push -u origin feat/oauth
gh pr create --base feat/auth-system
# After PR approved...
wt-ship
```

### Daily Sync Workflow
```bash
# Morning: sync all branches
wt-sync-all

# Start new work
wt-new feat/new-feature
cd worktrees/feat/new-feature

# During work: sync regularly
git town sync

# Ship when complete
wt-ship
```

### Branch States
- **Regular feature**: Standard development branch
- **Parked** (`wt-park`): Paused, won't sync automatically
- **Prototype** (`wt-prototype`): Local-only experiments
- **Observed** (`wt-observe`): Pull updates but don't push
- **Contribution** (`wt-contribute`): Contributing to someone else's branch

## Local Integration Workflow

### The Multi-Agent Problem
When multiple AI agents work in parallel, you need to test their combined changes before pushing to remote.

### Solution: Local Sync Commands

**`wt-local-merge`** (run from ANY child worktree)
- Merges current branch into its parent locally
- No remote push
- Good for testing one integration

**`wt-local-sync-all`** (run from ROOT project directory)
- Merges ALL child branches into their parents
- No remote push
- Good for testing complete integration

### Multi-Agent Workflow Example

```bash
# 1. Start multiple agents in parallel
agent-start 101  # Creates feat/search
agent-start 102  # Creates feat/filters  
agent-start 103  # Creates fix/pagination

# 2. Test local integration
cd /path/to/project/root
wt-local-sync-all
# This merges:
# - feat/search → main (locally)
# - feat/filters → main (locally)
# - fix/pagination → main (locally)

# 3. Test the integrated result
npm test
npm run lint

# 4. If tests pass, publish
git push  # Push main with all integrated changes

# 5. If tests fail, fix and re-sync
cd worktrees/feat/search
# fix issues...
wt-local-merge  # Re-merge just this branch
cd ../../
npm test  # Test again
```

### When to Use Each Command

| Command | Remote Push? | Use When |
|---------|-------------|----------|
| `wt-local-merge` | ❌ No | Test one branch integration |
| `wt-local-sync-all` | ❌ No | Test all branches together |
| `wt-ship` | ✅ Yes | Ship single branch permanently |
| `wt-sync-all` | ✅ Yes | Update all from remote |

### Execution Context Guide

**From ROOT project directory:**
- `wt-local-sync-all` - Integrate all branches
- `wt-sync-all` - Update from remote

**From ANY child worktree:**
- `wt-local-merge` - Merge this branch to parent
- `wt-ship` - Ship this branch to remote
- `wt-park` - Pause this branch
- `wt-observe` - Watch this branch
- `wt-contribute` - Mark as contribution
- `wt-prototype` - Mark as local-only

## Code Standards & Conventions

### Commit Messages
Use conventional commits with issue references:
```
feat: add user authentication #123
fix: resolve session timeout bug #456
docs: update API documentation #789
test: add auth integration tests #123
chore: update dependencies
```

### Code Style
- **Always** match the existing code style in the file you're editing
- Look at imports to understand what libraries are available
- Check `package.json` or `requirements.txt` before adding dependencies
- Never assume a library exists - always verify first

### Testing Requirements
- All new features need tests
- Run tests before committing
- Aim for >80% coverage on new code
- Test against parent branch in stacked development

## Collaboration Patterns

### Working with Humans
When a human developer is working in a parent or sibling branch:
1. Check their changes: `git diff main..their-branch`
2. Communicate conflicts: "I see you modified auth.py - my changes might conflict"
3. Suggest integration points: "I can use your AuthBase class for OAuth"

### Working with Other AI Agents
Multiple AI agents may be working in parallel:
1. Check sibling worktrees for related work
2. Avoid duplicate implementations
3. Coordinate through issue comments

### Conflict Resolution
When conflicts occur:
1. First try to understand both changes
2. Preserve functionality from both sides
3. If uncertain, ask: "Should OAuth timeout be 30min or inherit from session timeout?"

## Security & Safety Rules

### Never Do These
- ❌ Edit files directly in `main` or `master` branch
- ❌ Commit secrets, API keys, or passwords
- ❌ Delete or modify `.git` directory
- ❌ Run `rm -rf` on directories
- ❌ Push directly to main (always use PRs)

### Always Do These
- ✅ Create a worktree for new work
- ✅ Reference issue numbers in commits
- ✅ Run tests before marking work complete
- ✅ Check parent branch for context
- ✅ Use conventional commit messages

## Workflow States

### Issue States
1. **Open** - Ready to work on
2. **In Progress** - Someone (maybe you) is implementing
3. **In Review** - PR created, awaiting review
4. **Closed** - Completed and merged

### Your Task States
When using TodoWrite tool:
- `pending` - Not started yet
- `in_progress` - Currently working (only ONE at a time)
- `completed` - Finished successfully
- Never mark incomplete work as completed

## Context Persistence

### Issue Context
Each worktree has a `.context/` directory:
```
feat-auth/.context/
├── issue-123.md        # Original issue description
├── decisions.md        # Architecture decisions made
├── ai-memory.json      # Your memory of this task
└── test-results.log    # Latest test outcomes
```

### Reading Context
When starting work in a worktree:
1. Check `.context/issue-*.md` for requirements
2. Read `.context/decisions.md` for past choices
3. Continue from `.context/ai-memory.json`

### Saving Context
Before leaving a worktree:
1. Document decisions in `.context/decisions.md`
2. Save your understanding for next session
3. Update issue with progress

## Emergency Procedures

### If Tests Fail
1. Read the error carefully
2. Check if parent branch tests pass
3. Look for recent changes that might cause it
4. Fix the issue before proceeding

### If You're Stuck
1. Use sequential thinking to break down the problem
2. Consult zen for alternative approaches
3. Leave a clear note about what's blocking you
4. Create a todo item for the blocker

### If You Break Something
1. Stop immediately
2. Document what happened
3. If in a worktree, it's safe - the damage is isolated
4. Ask for help to resolve

## Environment Setup

### Python Virtual Environment
The devenv automatically creates and activates a Python virtual environment:
```bash
# Automatically created on shell entry
.venv/                   # Python virtual environment with uv
  ├── bin/              # Python executables
  └── lib/              # Installed packages (rich, gitpython, aiofiles)
```

### MCP Servers Configuration
Available MCP servers (defined in `mcp-servers.json`):
- **context7**: Documentation fetcher
- **playwright**: Browser automation
- **zen**: Multi-model AI collaboration
- **python-sandbox**: Safe Python execution
- **sequential-thinking**: Structured problem-solving

### Dagger Pipeline
Containerization is handled via `dagger_pipeline.py`:
- AI agents run in isolated Ubuntu containers
- Worktrees are mounted as volumes
- Context directories are preserved

### Team-Specific Configuration

### Project Structure
```
factory_floor/
├── devenv.nix          # Main devenv configuration
├── CLAUDE.md           # This file - AI instructions
├── devflow.py          # Python TUI for workflow management
├── dagger_pipeline.py  # Container configuration
├── mcp-servers.json    # MCP server definitions
├── worktrees/          # Git worktrees (gitignored)
├── .venv/              # Python virtual environment (gitignored)
├── .mcp/               # MCP server data (gitignored)
│   ├── logs/          # Server logs
│   ├── pids/          # Process IDs
│   └── sockets/       # Communication sockets
└── .context/           # Per-worktree AI context

## Quick Reference

### Starting New Work
```bash
# Option 1: Automated
issue-to-pr 456

# Option 2: Manual
wt-new feat-456-add-search
cd worktrees/feat-456-add-search
gh issue view 456
# implement...
git add -A
git commit -m "feat: add search functionality #456"
gh pr create --fill
```

### Updating From Parent
```bash
# In child worktree
git town sync
# or manually
git rebase origin/parent-branch
```

### Creating Sub-task
```bash
# In parent worktree
wt-new child-feature
# Creates nested worktree maintaining relationship
```

## Remember

You are part of a team. Your code will be:
- Read by humans
- Modified by others  
- Integrated with parallel work
- Deployed to production

Write code that is:
- Clear and maintainable
- Well-tested
- Properly documented
- Consistent with team standards

Your superpower is not just writing code, but understanding the entire system context and helping the team work more effectively. Use your tools wisely, maintain context persistently, and always think about how your changes fit into the larger system.

---
*Last updated: [Team should update date when modifying]*
*Version: 1.0.0*