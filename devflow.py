#!/usr/bin/env python3
"""
DevFlow TUI - AI Factory Floor Workflow Manager
A terminal UI for managing git worktrees, AI agents, and development workflows.
"""

import subprocess
import json
import os
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Tuple
import sys

# Rich for terminal UI
try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.layout import Layout
    from rich.live import Live
    from rich.text import Text
    from rich.tree import Tree
    from rich import print as rprint
    from rich.prompt import Prompt, Confirm
except ImportError:
    print("Error: rich library not installed")
    print("Install with: pip install rich")
    sys.exit(1)

console = Console()


class WorktreeManager:
    """Manages git worktrees and their relationships"""
    
    def __init__(self):
        self.root_dir = Path.cwd()
        self.worktree_base = self.root_dir / "worktrees"
        self.context_dir = ".context"
        
    def get_worktrees(self) -> List[Dict]:
        """Get all worktrees with their metadata"""
        try:
            result = subprocess.run(
                ["git", "worktree", "list", "--porcelain"],
                capture_output=True,
                text=True,
                check=True
            )
            
            worktrees = []
            current_wt = {}
            
            for line in result.stdout.strip().split('\n'):
                if line.startswith('worktree '):
                    if current_wt:
                        worktrees.append(current_wt)
                    current_wt = {'path': line.split(' ', 1)[1]}
                elif line.startswith('HEAD '):
                    current_wt['head'] = line.split(' ', 1)[1]
                elif line.startswith('branch '):
                    current_wt['branch'] = line.split(' ', 1)[1].replace('refs/heads/', '')
                elif line.startswith('detached'):
                    current_wt['detached'] = True
                elif line == '':
                    if current_wt:
                        worktrees.append(current_wt)
                        current_wt = {}
            
            if current_wt:
                worktrees.append(current_wt)
                
            # Add additional metadata - first pass
            for wt in worktrees:
                path = Path(wt['path'])
                wt['name'] = path.name if path != self.root_dir else 'main'
                wt['is_current'] = path == Path.cwd()
                
                # Check for context
                context_path = path / self.context_dir
                if context_path.exists():
                    wt['has_context'] = True
                    # Try to find issue number
                    for f in context_path.glob('issue-*.md'):
                        wt['issue'] = f.stem.replace('issue-', '')
                        break
                else:
                    wt['has_context'] = False
                    
            # Second pass - build parent-child relationships
            for wt in worktrees:
                path = Path(wt['path'])
                wt['children'] = []
                for child in worktrees:
                    child_path = Path(child['path'])
                    # Check if child is a direct subdirectory of this worktree
                    if child_path.parent == path:
                        wt['children'].append(child['name'])
                                
            return worktrees
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]Error getting worktrees: {e}[/red]")
            return []
    
    def create_worktree(self, branch_name: str, parent_branch: Optional[str] = None) -> bool:
        """Create a new worktree"""
        try:
            cmd = ["devenv", "shell", "--impure", "-c", f"wt-new {branch_name}"]
            if parent_branch:
                cmd[-1] += f" {parent_branch}"
                
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                console.print(f"[green]✅ Created worktree: {branch_name}[/green]")
                return True
            else:
                console.print(f"[red]Failed to create worktree: {result.stderr}[/red]")
                return False
        except Exception as e:
            console.print(f"[red]Error: {e}[/red]")
            return False


class MCPServerManager:
    """Manages MCP (Model Context Protocol) servers"""
    
    def __init__(self):
        self.mcp_dir = Path(".mcp")
        self.servers = {
            "context7": "Context7 (Documentation)",
            "playwright": "Playwright (Browser)",
            "python": "Python Sandbox",
            "sequential": "Sequential Thinking",
            "zen": "Zen Multi-Model"
        }
        
    def get_status(self) -> Dict[str, str]:
        """Get status of all MCP servers"""
        status = {}
        pid_dir = self.mcp_dir / "pids"
        
        if not pid_dir.exists():
            return {name: "not configured" for name in self.servers}
            
        for server_name in self.servers:
            pid_file = pid_dir / f"{server_name}.pid"
            if pid_file.exists():
                try:
                    pid = int(pid_file.read_text().strip())
                    # Check if process is running
                    os.kill(pid, 0)
                    status[server_name] = "running"
                except (OSError, ValueError):
                    status[server_name] = "stopped"
            else:
                status[server_name] = "not started"
                
        return status
    
    def start_servers(self):
        """Start all MCP servers"""
        subprocess.run(["devenv", "shell", "--impure", "-c", "mcp-start"])
        
    def stop_servers(self):
        """Stop all MCP servers"""
        subprocess.run(["devenv", "shell", "--impure", "-c", "mcp-stop"])


class DevFlowTUI:
    """Main TUI application"""
    
    def __init__(self):
        self.wt_manager = WorktreeManager()
        self.mcp_manager = MCPServerManager()
        self.running = True
        
    def create_enhanced_worktree_tree(self) -> Tree:
        """Create an enhanced tree visualization with status indicators"""
        tree = Tree("")
        worktrees = self.wt_manager.get_worktrees()
        
        # Build tree structure - show all top-level worktrees
        root_wts = []
        for wt in worktrees:
            wt_path = Path(wt['path'])
            # Include main directory
            if wt_path == self.wt_manager.root_dir:
                root_wts.append(wt)
            # Include direct children of worktrees/ directory
            elif wt_path.parent == self.wt_manager.root_dir / 'worktrees':
                root_wts.append(wt)
        
        for wt in root_wts:
            branch_name = wt.get('branch', 'detached')
            
            # Add status indicators
            status_icon = "🟢" if wt['is_current'] else "⚪"
            
            # Check for uncommitted changes
            try:
                wt_path = Path(wt['path'])
                result = subprocess.run(
                    ['git', '-C', str(wt_path), 'status', '--porcelain'],
                    capture_output=True, text=True
                )
                if result.stdout:
                    status_icon = "🟡"  # Has uncommitted changes
            except:
                pass
            
            # Format branch type
            branch_type = ""
            if '/' in branch_name:
                type_prefix = branch_name.split('/')[0]
                type_colors = {
                    'feat': 'green',
                    'fix': 'red',
                    'docs': 'blue',
                    'test': 'yellow',
                    'chore': 'dim'
                }
                color = type_colors.get(type_prefix, 'white')
                branch_type = f"[{color}]{type_prefix}[/{color}]/"
                branch_name = branch_name[len(type_prefix)+1:]
            
            issue = f" [dim]#{wt['issue']}[/dim]" if wt.get('issue') else ""
            current = " [bold cyan]← you are here[/bold cyan]" if wt['is_current'] else ""
            
            node_text = f"{status_icon} {branch_type}{branch_name}{issue}{current}"
            node = tree.add(node_text)
            
            # Add children recursively
            self._add_children_to_tree(node, wt, worktrees)
            
        return tree
    
    def create_worktree_tree(self) -> Tree:
        """Legacy method for compatibility"""
        return self.create_enhanced_worktree_tree()
    
    def _add_children_to_tree(self, parent_node, parent_wt, all_worktrees):
        """Recursively add children to tree"""
        for child_name in parent_wt.get('children', []):
            child_wt = next((wt for wt in all_worktrees if wt['name'] == child_name), None)
            if child_wt:
                branch_name = child_wt.get('branch', 'detached')
                issue = f" #{child_wt['issue']}" if child_wt.get('issue') else ""
                current = " [cyan][current][/cyan]" if child_wt['is_current'] else ""
                
                node_text = f"{branch_name}{issue}{current}"
                child_node = parent_node.add(node_text)
                
                # Recurse for nested children
                self._add_children_to_tree(child_node, child_wt, all_worktrees)
    
    def create_mcp_status_table(self) -> Table:
        """Create a table showing MCP server status"""
        table = Table(title="🔌 MCP Server Status", show_header=True)
        table.add_column("Server", style="cyan")
        table.add_column("Status", style="green")
        
        status = self.mcp_manager.get_status()
        for server_name, desc in self.mcp_manager.servers.items():
            server_status = status.get(server_name, "unknown")
            status_style = "green" if server_status == "running" else "red" if server_status == "stopped" else "yellow"
            table.add_row(desc, f"[{status_style}]{server_status}[/{status_style}]")
            
        return table
    
    def create_layout(self) -> Layout:
        """Create the main layout"""
        layout = Layout()
        
        # Split into header, body, and footer
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body"),
            Layout(name="workflow", size=8),
            Layout(name="footer", size=4)
        )
        
        # Header
        layout["header"].update(
            Panel(
                "[bold blue]🏭 AI Factory Floor - DevFlow Manager[/bold blue]\n"
                "[dim]Manage worktrees, AI agents, and development workflows[/dim]",
                border_style="blue"
            )
        )
        
        # Body - split into left and right
        layout["body"].split_row(
            Layout(name="left"),
            Layout(name="right")
        )
        
        # Left panel - worktree tree with status
        layout["body"]["left"].update(
            Panel(self.create_enhanced_worktree_tree(), border_style="green", title="🌳 Worktrees")
        )
        
        # Right panel - MCP status
        layout["body"]["right"].update(
            Panel(self.create_mcp_status_table(), border_style="yellow")
        )
        
        # Workflow guide panel
        layout["workflow"].update(
            Panel(
                self.create_workflow_guide(),
                border_style="cyan",
                title="📈 Workflow Guide"
            )
        )
        
        # Footer - enhanced commands
        layout["footer"].update(
            Panel(
                "[bold]🚀 Quick Actions:[/bold]\n"
                "[cyan](1)[/cyan] Start work on issue → [cyan](2)[/cyan] Sync all branches → "
                "[cyan](3)[/cyan] Ship current branch\n"
                "[cyan](n)[/cyan]ew branch | [cyan](s)[/cyan]ync all | [cyan](S)[/cyan]hip | "
                "[cyan](p)[/cyan]ark | [cyan](a)[/cyan]gent | [cyan](h)[/cyan]elp | [cyan](q)[/cyan]uit",
                border_style="bright_blue"
            )
        )
        
        return layout
    
    def create_workflow_guide(self) -> str:
        """Create workflow guide text"""
        current_branch = subprocess.run(
            ['git', 'branch', '--show-current'],
            capture_output=True, text=True
        ).stdout.strip()
        
        if not current_branch or current_branch in ['main', 'master']:
            return (
                "[bold]Ready to start work![/bold]\n\n"
                "1️⃣  [cyan]Press '1'[/cyan] to start work on an issue (creates semantic branch)\n"
                "2️⃣  [cyan]Press 'n'[/cyan] to create a new feature branch manually\n"
                "3️⃣  [cyan]Press 's'[/cyan] to sync all branches with latest changes"
            )
        else:
            # Check if branch has uncommitted changes
            status = subprocess.run(
                ['git', 'status', '--porcelain'],
                capture_output=True, text=True
            ).stdout
            
            if status:
                return (
                    f"[yellow]⚠️  Uncommitted changes in {current_branch}[/yellow]\n\n"
                    "Next steps:\n"
                    "• Commit your changes: [cyan]git add -A && git commit[/cyan]\n"
                    "• Then sync: [cyan]Press 's'[/cyan] or run [cyan]git town sync[/cyan]\n"
                    "• Ready to ship? [cyan]Press 'S'[/cyan] to merge & cleanup"
                )
            else:
                return (
                    f"[green]✓ Working on: {current_branch}[/green]\n\n"
                    "Actions available:\n"
                    "• [cyan]Press 's'[/cyan] - Sync with parent branch\n"
                    "• [cyan]Press 'S'[/cyan] - Ship (merge to parent & cleanup)\n"
                    "• [cyan]Press 'p'[/cyan] - Park (pause this branch)\n"
                    "• [cyan]Press 'a'[/cyan] - Start AI agent here"
                )
    
    def handle_input(self) -> bool:
        """Handle user input with enhanced workflow options"""
        key = Prompt.ask(
            "\n[bold]Action[/bold]",
            choices=["1", "2", "3", "n", "s", "S", "p", "a", "h", "q", "r"],
            default="r"
        )
        
        if key == "q":
            return False
        elif key == "1":
            # Start work on issue
            issue = Prompt.ask("[bold]Issue number[/bold]")
            console.print(f"[green]Starting work on issue #{issue}...[/green]")
            subprocess.run(["devenv", "shell", "-c", f"agent-start {issue}"])
        elif key == "2" or key == "s":
            # Sync all branches
            console.print("[yellow]Syncing all branches with their parents...[/yellow]")
            subprocess.run(["devenv", "shell", "-c", "wt-sync-all"])
        elif key == "3" or key == "S":
            # Ship current branch
            console.print("[yellow]Shipping current branch...[/yellow]")
            subprocess.run(["devenv", "shell", "-c", "wt-ship"])
        elif key == "n":
            # New branch with semantic naming hint
            console.print("[dim]Format: <type>/<description>[/dim]")
            console.print("[dim]Types: feat, fix, docs, test, chore, hotfix[/dim]")
            branch = Prompt.ask("[bold]Branch name[/bold]")
            parent = Prompt.ask("[bold]Parent branch (optional)[/bold]", default="")
            self.wt_manager.create_worktree(branch, parent if parent else None)
        elif key == "p":
            # Park current branch
            console.print("[yellow]Parking current branch...[/yellow]")
            subprocess.run(["devenv", "shell", "-c", "wt-park"])
        elif key == "a":
            # Start agent
            choice = Prompt.ask(
                "[bold]Start agent[/bold]",
                choices=["here", "issue"],
                default="here"
            )
            if choice == "here":
                subprocess.run(["devenv", "shell", "-c", "agent-here"])
            else:
                issue = Prompt.ask("[bold]Issue number[/bold]")
                subprocess.run(["devenv", "shell", "-c", f"agent-start {issue}"])
        elif key == "h":
            # Show help
            subprocess.run(["devenv", "shell", "-c", "?"])
            Prompt.ask("\n[dim]Press Enter to continue[/dim]")
        elif key == "r":
            console.print("[dim]Refreshing...[/dim]")
            
        return True
    
    def run(self):
        """Run the TUI"""
        console.clear()
        
        while self.running:
            layout = self.create_layout()
            console.print(layout)
            
            if not self.handle_input():
                self.running = False
                
            console.clear()
        
        console.print("[green]Goodbye! 👋[/green]")


def main():
    """Main entry point"""
    app = DevFlowTUI()
    
    try:
        app.run()
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted by user[/yellow]")
    except Exception as e:
        console.print(f"\n[red]Error: {e}[/red]")
        raise


if __name__ == "__main__":
    main()