#!/usr/bin/env python3
"""
Dagger pipeline for AI Factory Floor
Provides containerized environments for AI agents to run in isolation
"""

import sys
import os
from typing import Optional

# Dagger SDK
try:
    import dagger
    from dagger import dag, function, object_type
except ImportError:
    print("Error: Dagger SDK not installed")
    print("Install with: pip install dagger-io")
    sys.exit(1)


@object_type
class AIFactoryFloor:
    """Dagger module for AI Factory Floor workflows"""

    @function
    async def dev_container(
        self,
        source: dagger.Directory,
        context_dir: Optional[dagger.Directory] = None,
    ) -> dagger.Container:
        """
        Create a development container for AI agents

        Args:
            source: The worktree directory to mount
            context_dir: Optional context directory with issue information
        """
        # Start with Ubuntu base
        container = (
            dag.container()
            .from_("ubuntu:22.04")
            # Install base dependencies
            .with_exec(["apt-get", "update"])
            .with_exec(
                [
                    "apt-get",
                    "install",
                    "-y",
                    "git",
                    "curl",
                    "build-essential",
                    "nodejs",
                    "npm",
                    "python3",
                    "python3-pip",
                ]
            )
            # Install OpenCode CLI
            .with_exec(["npm", "install", "-g", "opencode-ai"])
            # Mount the source code
            .with_mounted_directory("/workspace", source)
        )

        # Mount context if provided
        if context_dir:
            container = container.with_mounted_directory("/context", context_dir)

        # Set working directory and environment
        container = (
            container.with_workdir("/workspace")
            .with_env_variable("WORKSPACE", "/workspace")
            .with_env_variable("CONTEXT_DIR", "/context")
        )

        return container

    @function
    async def run_agent(
        self,
        source: dagger.Directory,
        issue_number: str,
        model: str = "claude",
    ) -> str:
        """
        Run an AI agent in a container to work on an issue

        Args:
            source: The worktree directory
            issue_number: GitHub issue number to work on
            model: AI model to use (claude, gemini, etc.)
        """
        # Create container
        container = await self.dev_container(source)

        # Add API keys from environment
        if os.getenv("ANTHROPIC_API_KEY"):
            container = container.with_env_variable(
                "ANTHROPIC_API_KEY", os.getenv("ANTHROPIC_API_KEY")
            )

        # Run the AI agent in non-interactive mode
        result = await container.with_exec(
            [
                "opencode",
                "--non-interactive",
                f"Read issue #{issue_number} and implement the solution. "
                f"Follow the workflow in CLAUDE.md. "
                f"Commit changes with conventional commits.",
            ]
        ).stdout()

        return result

    @function
    async def test_container(
        self,
        source: dagger.Directory,
    ) -> dagger.Container:
        """
        Create a container for running tests

        Args:
            source: The worktree directory to test
        """
        container = await self.dev_container(source)

        # Detect test framework and run tests
        container = container.with_exec(
            [
                "bash",
                "-c",
                """
            if [ -f package.json ]; then
                npm install && npm test
            elif [ -f requirements.txt ]; then
                pip3 install -r requirements.txt && python3 -m pytest
            elif [ -f go.mod ]; then
                go test ./...
            else
                echo "No test framework detected"
            fi
            """,
            ]
        )

        return container

    @function
    async def build_image(
        self,
        source: dagger.Directory,
        tag: str = "ai-factory-floor:latest",
    ) -> str:
        """
        Build a Docker image for the AI agent environment

        Args:
            source: The source directory
            tag: Docker image tag
        """
        container = await self.dev_container(source)

        # Export as Docker image
        image_id = await container.export(tag)

        return f"Built image: {tag} (ID: {image_id})"


async def main():
    """Example usage of the Dagger pipeline"""

    async with dagger.Connection() as client:
        # Get the current directory
        source = client.host().directory(".")

        # Create a dev container
        container = await AIFactoryFloor().dev_container(source)

        # Run a command in the container
        result = await container.with_exec(["echo", "Hello from container!"]).stdout()
        print(result)


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
