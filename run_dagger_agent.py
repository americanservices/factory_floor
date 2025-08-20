#!/usr/bin/env python3
"""
Helper script to run AI agents in Dagger containers
"""

import asyncio
import sys
import os
from pathlib import Path
import dagger
import argparse


async def run_agent_in_container(
    source_dir: str,
    context_dir: str = None,
    issue_number: str = None,
    task: str = None,
    interactive: bool = False
):
    """
    Run an AI agent in a Dagger container
    
    Args:
        source_dir: The worktree directory to mount
        context_dir: Optional context directory with issue/task information
        issue_number: GitHub issue number if working on an issue
        task: Direct task description if not using an issue
        interactive: Whether to run in interactive mode
    """
    async with dagger.Connection() as client:
        # Get the source directory
        source = client.host().directory(source_dir, exclude=[".git", "node_modules", ".venv", "__pycache__"])
        
        # Start with Ubuntu base
        container = (
            client.container()
            .from_("ubuntu:22.04")
            # Install base dependencies
            .with_exec(["apt-get", "update"])
            .with_exec(["apt-get", "install", "-y", 
                       "git", "curl", "build-essential", 
                       "nodejs", "npm", "python3", "python3-pip"])
        )
        
        # Install Claude CLI (if available in npm)
        # Note: This assumes claude-cli is available via npm, adjust as needed
        # container = container.with_exec(["npm", "install", "-g", "@anthropic-ai/claude-cli"])
        
        # Mount the source code
        container = container.with_mounted_directory("/workspace", source)
        
        # Mount context if provided
        if context_dir and os.path.exists(context_dir):
            context = client.host().directory(context_dir)
            container = container.with_mounted_directory("/context", context)
        
        # Set working directory and environment
        container = (
            container
            .with_workdir("/workspace")
            .with_env_variable("WORKSPACE", "/workspace")
        )
        
        # Add API keys from environment
        if os.getenv("ANTHROPIC_API_KEY"):
            container = container.with_env_variable(
                "ANTHROPIC_API_KEY", 
                os.getenv("ANTHROPIC_API_KEY")
            )
        
        # Prepare the command based on the mode
        if interactive:
            # For interactive mode, we'll use shell
            cmd = ["bash"]
        else:
            # Build the task message
            if issue_number and context_dir:
                task_msg = f"Read /context/issue-{issue_number}.md and implement the solution. Follow the workflow in CLAUDE.md."
            elif task:
                task_msg = task
            else:
                task_msg = "Read the context in /context/ and work on the task. Follow the workflow in CLAUDE.md."
            
            # Use claude command if available, otherwise just echo the task
            if os.getenv("ANTHROPIC_API_KEY"):
                cmd = ["bash", "-c", f"echo 'Task: {task_msg}' && echo 'Ready to work with Claude API'"]
            else:
                cmd = ["bash", "-c", f"echo 'Task: {task_msg}' && echo 'Note: ANTHROPIC_API_KEY not set'"]
        
        # Execute the command
        if interactive:
            print("🐳 Starting interactive container...")
            print("Note: This would normally start an interactive session.")
            print("To work with the agent, you would connect to this container.")
            result = await container.with_exec(["echo", "Container ready"]).stdout()
        else:
            print("🐳 Running agent in container...")
            result = await container.with_exec(cmd).stdout()
        
        print(result)
        
        # Export the working directory back to host if changes were made
        # This would sync changes back to the worktree
        await container.directory("/workspace").export(source_dir)
        
        return result


def main():
    parser = argparse.ArgumentParser(description="Run AI agent in Dagger container")
    parser.add_argument("--source", "-s", default=".", help="Source directory to mount")
    parser.add_argument("--context", "-c", help="Context directory with issue/task info")
    parser.add_argument("--issue", "-i", help="GitHub issue number")
    parser.add_argument("--task", "-t", help="Direct task description")
    parser.add_argument("--interactive", action="store_true", help="Run in interactive mode")
    
    args = parser.parse_args()
    
    # Run the async function
    asyncio.run(run_agent_in_container(
        source_dir=args.source,
        context_dir=args.context,
        issue_number=args.issue,
        task=args.task,
        interactive=args.interactive
    ))


if __name__ == "__main__":
    main()