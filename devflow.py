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
                cwd=str(self.root_dir),
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
                
            # Add additional metadata
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
                    
                # Check for nested worktrees
                wt['children'] = []
                
            # Build parent-child relationships after all worktrees are processed
            for wt in worktrees:
                path = Path(wt['path'])
                # Look for children whose path starts with this worktree's path + /worktrees/
                for child in worktrees:
                    child_path = Path(child['path'])
                    # Check if child is nested under this worktree
                    expected_parent = path / 'worktrees' / child_path.name
                    if child_path == expected_parent or (
                        str(child_path).startswith(str(path / 'worktrees')) and 
                        child_path != path
                    ):
                        wt['children'].append(child['name'])
                                
            return worktrees
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]Error getting worktrees: {e}[/red]")
            if e.stderr:
                console.print(f"[red]Details: {e.stderr.strip()}[/red]")
            console.print("[yellow]Make sure you're in a git repository[/yellow]")
            return []
        except FileNotFoundError:
            console.print("[red]Git command not found[/red]")
            console.print("[yellow]Make sure git is installed and in your PATH[/yellow]")
            return []
        except Exception as e:
            console.print(f"[red]Unexpected error getting worktrees: {e}[/red]")
            return []
    
    def create_worktree(self, branch_name: str, parent_branch: Optional[str] = None) -> bool:
        """Create a new worktree"""
        try:
            # Build command based on environment
            if os.environ.get('DEVENV_ROOT'):
                # We're in devenv, call the script directly
                cmd = ["wt-new", branch_name]
                if parent_branch:
                    cmd.append(parent_branch)
            else:
                # Not in devenv, need to use devenv shell
                cmd_str = f"wt-new {branch_name}"
                if parent_branch:
                    cmd_str += f" {parent_branch}"
                cmd = ["devenv", "shell", "--impure", "-c", cmd_str]
                
            console.print(f"[dim]Running: {' '.join(cmd)}[/dim]")
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(self.root_dir))
            
            if result.returncode == 0:
                console.print(f"[green]✅ Created worktree: {branch_name}[/green]")
                if result.stdout:
                    console.print(f"[dim]{result.stdout.strip()}[/dim]")
                return True
            else:
                console.print(f"[red]❌ Failed to create worktree: {branch_name}[/red]")
                if result.stderr:
                    console.print(f"[red]Error: {result.stderr.strip()}[/red]")
                if result.stdout:
                    console.print(f"[dim]Output: {result.stdout.strip()}[/dim]")
                return False
        except FileNotFoundError as e:
            console.print(f"[red]Command not found: {e}[/red]")
            console.print("[yellow]Make sure you're in a devenv shell or have the required commands available[/yellow]")
            return False
        except Exception as e:
            console.print(f"[red]Unexpected error: {e}[/red]")
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
                    pid_content = pid_file.read_text().strip()
                    if not pid_content:
                        status[server_name] = "stopped"
                        continue
                        
                    pid = int(pid_content)
                    # Check if process is running using cross-platform method
                    try:
                        os.kill(pid, 0)
                        status[server_name] = "running"
                    except OSError:
                        # Process doesn't exist, clean up stale pid file
                        try:
                            pid_file.unlink()
                        except OSError:
                            pass
                        status[server_name] = "stopped"
                except (ValueError, FileNotFoundError):
                    status[server_name] = "stopped"
            else:
                status[server_name] = "not started"
                
        return status
    
    def start_servers(self) -> bool:
        """Start all MCP servers"""
        try:
            if os.environ.get('DEVENV_ROOT'):
                result = subprocess.run(["mcp-start"], capture_output=True, text=True)
            else:
                result = subprocess.run(["devenv", "shell", "--impure", "-c", "mcp-start"], 
                                      capture_output=True, text=True)
            
            if result.returncode == 0:
                console.print("[green]✅ MCP servers started successfully[/green]")
                if result.stdout:
                    console.print(f"[dim]{result.stdout.strip()}[/dim]")
                return True
            else:
                console.print("[red]❌ Failed to start MCP servers[/red]")
                if result.stderr:
                    console.print(f"[red]{result.stderr.strip()}[/red]")
                return False
        except FileNotFoundError:
            console.print("[red]mcp-start command not found[/red]")
            console.print("[yellow]Make sure you're in a devenv shell[/yellow]")
            return False
        except Exception as e:
            console.print(f"[red]Error starting MCP servers: {e}[/red]")
            return False
        
    def stop_servers(self) -> bool:
        """Stop all MCP servers"""
        try:
            if os.environ.get('DEVENV_ROOT'):
                result = subprocess.run(["mcp-stop"], capture_output=True, text=True)
            else:
                result = subprocess.run(["devenv", "shell", "--impure", "-c", "mcp-stop"], 
                                      capture_output=True, text=True)
            
            if result.returncode == 0:
                console.print("[green]✅ MCP servers stopped successfully[/green]")
                if result.stdout:
                    console.print(f"[dim]{result.stdout.strip()}[/dim]")
                return True
            else:
                console.print("[red]❌ Failed to stop MCP servers[/red]")
                if result.stderr:
                    console.print(f"[red]{result.stderr.strip()}[/red]")
                return False
        except FileNotFoundError:
            console.print("[red]mcp-stop command not found[/red]")
            console.print("[yellow]Make sure you're in a devenv shell[/yellow]")
            return False
        except Exception as e:
            console.print(f"[red]Error stopping MCP servers: {e}[/red]")
            return False


class DevFlowTUI:
    """Main TUI application"""
    
    def __init__(self):
        self.wt_manager = WorktreeManager()
        self.mcp_manager = MCPServerManager()
        self.running = True
        
    def create_worktree_tree(self) -> Tree:
        """Create a tree visualization of worktrees"""
        tree = Tree("🌳 [bold]Worktrees[/bold]")
        worktrees = self.wt_manager.get_worktrees()
        
        if not worktrees:
            tree.add("[dim]No worktrees found[/dim]")
            return tree
        
        # Build tree structure - find root worktrees (not nested under others)
        root_wts = []
        for wt in worktrees:
            path = Path(wt['path'])
            is_root = True
            
            # Check if this worktree is nested under another
            for other_wt in worktrees:
                if other_wt == wt:
                    continue
                other_path = Path(other_wt['path'])
                # Check if this path is under another worktree's directory
                if str(path).startswith(str(other_path / 'worktrees')):
                    is_root = False
                    break
            
            if is_root:
                root_wts.append(wt)
        
        for wt in root_wts:
            branch_name = wt.get('branch', 'detached')
            issue = f" #{wt['issue']}" if wt.get('issue') else ""
            current = " [cyan][current][/cyan]" if wt['is_current'] else ""
            context_indicator = " 📄" if wt.get('has_context') else ""
            
            node_text = f"{branch_name}{issue}{current}{context_indicator}"
            node = tree.add(node_text)
            
            # Add children recursively
            self._add_children_to_tree(node, wt, worktrees)
            
        return tree
    
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
        
        # Split into header and body
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body"),
            Layout(name="footer", size=3)
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
        
        # Left panel - worktree tree
        layout["body"]["left"].update(
            Panel(self.create_worktree_tree(), border_style="green")
        )
        
        # Right panel - MCP status
        layout["body"]["right"].update(
            Panel(self.create_mcp_status_table(), border_style="yellow")
        )
        
        # Footer - commands and environment info
        env_info = "devenv" if os.environ.get('DEVENV_ROOT') else "system"
        zellij_info = " | zellij" if os.environ.get('ZELLIJ') else ""
        layout["footer"].update(
            Panel(
                f"[bold]Commands:[/bold] "
                "[cyan](n)[/cyan]ew worktree | "
                "[cyan](a)[/cyan]gent start | "
                "[cyan](s)[/cyan]tart MCP | "
                "[cyan](k)[/cyan]ill MCP | "
                "[cyan](r)[/cyan]efresh | "
                "[cyan](q)[/cyan]uit | "
                f"[dim]env: {env_info}{zellij_info}[/dim]",
                border_style="dim"
            )
        )
        
        return layout
    
    def handle_input(self) -> bool:
        """Handle user input"""
        try:
            key = Prompt.ask(
                "\n[bold]Command[/bold]",
                choices=["n", "a", "s", "k", "r", "q"],
                default="r"
            )
        except KeyboardInterrupt:
            return False
        except EOFError:
            return False
        
        if key == "q":
            return False
        elif key == "n":
            branch = Prompt.ask("[bold]Branch name[/bold]")
            parent = Prompt.ask("[bold]Parent branch (optional)[/bold]", default="")
            self.wt_manager.create_worktree(branch, parent if parent else None)
        elif key == "a":
            # Start agent in worktree
            worktree = Prompt.ask("[bold]Worktree name (or 'here' for current)[/bold]")
            self._start_agent(worktree)
        elif key == "s":
            console.print("[yellow]Starting MCP servers...[/yellow]")
            self.mcp_manager.start_servers()
        elif key == "k":
            console.print("[yellow]Stopping MCP servers...[/yellow]")
            self.mcp_manager.stop_servers()
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
    
    def _start_agent(self, worktree: str) -> bool:
        """Start an agent in the specified worktree or current directory"""
        try:
            if worktree == "here":
                # Start agent in current directory
                console.print("[yellow]Starting agent in current directory...[/yellow]")
                if os.environ.get('DEVENV_ROOT'):
                    result = subprocess.run(["agent-here"], capture_output=True, text=True)
                else:
                    result = subprocess.run(["devenv", "shell", "--impure", "-c", "agent-here"], 
                                          capture_output=True, text=True)
                
                if result.returncode == 0:
                    console.print("[green]✅ Agent started successfully[/green]")
                    return True
                else:
                    console.print("[red]❌ Failed to start agent[/red]")
                    if result.stderr:
                        console.print(f"[red]{result.stderr.strip()}[/red]")
                    return False
            else:
                # Start agent in specific worktree
                worktree_path = self.wt_manager.worktree_base / worktree
                if not worktree_path.exists():
                    # Try absolute path or current dir relative
                    alt_path = Path("worktrees") / worktree
                    if alt_path.exists():
                        worktree_path = alt_path.absolute()
                    else:
                        console.print(f"[red]Worktree {worktree} not found[/red]")
                        console.print(f"[dim]Looked in: {worktree_path} and {alt_path}[/dim]")
                        return False
                
                console.print(f"[yellow]Starting agent in worktree: {worktree}...[/yellow]")
                
                # If in zellij, create new tab and run agent
                if os.environ.get('ZELLIJ'):
                    try:
                        # Create a new tab for the agent
                        result = subprocess.run([
                            "zellij", "action", "new-tab", 
                            "--name", f"agent-{worktree}", 
                            "--cwd", str(worktree_path)
                        ], capture_output=True, text=True)
                        
                        if result.returncode == 0:
                            # Run agent-here in the new tab
                            subprocess.run(["zellij", "action", "write-chars", "agent-here\n"])
                            console.print(f"[green]✅ Agent started in new Zellij tab: agent-{worktree}[/green]")
                            return True
                        else:
                            console.print("[yellow]Zellij tab creation failed, falling back to current terminal[/yellow]")
                    except FileNotFoundError:
                        console.print("[yellow]Zellij not found, running in current terminal[/yellow]")
                
                # Not in zellij or zellij failed, run in current terminal
                cmd_str = f"cd {worktree_path} && agent-here"
                if os.environ.get('DEVENV_ROOT'):
                    result = subprocess.run(["sh", "-c", cmd_str], capture_output=True, text=True)
                else:
                    result = subprocess.run(["devenv", "shell", "--impure", "-c", cmd_str], 
                                          capture_output=True, text=True)
                
                if result.returncode == 0:
                    console.print(f"[green]✅ Agent started in worktree: {worktree}[/green]")
                    if result.stdout:
                        console.print(f"[dim]{result.stdout.strip()}[/dim]")
                    return True
                else:
                    console.print(f"[red]❌ Failed to start agent in worktree: {worktree}[/red]")
                    if result.stderr:
                        console.print(f"[red]{result.stderr.strip()}[/red]")
                    return False
                    
        except FileNotFoundError as e:
            console.print(f"[red]Command not found: {e}[/red]")
            console.print("[yellow]Make sure agent-here is available in your PATH[/yellow]")
            return False
        except Exception as e:
            console.print(f"[red]Unexpected error starting agent: {e}[/red]")
            return False


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