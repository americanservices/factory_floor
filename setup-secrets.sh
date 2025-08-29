#!/usr/bin/env bash
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   🔐 SecretSpec Configuration Helper for OnePassword"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if secretspec is available
if ! command -v secretspec &> /dev/null; then
    echo "❌ SecretSpec not found. Please run 'devenv shell' first."
    exit 1
fi

# Default to OnePassword development vault
PROVIDER="${SECRETSPEC_PROVIDER:-onepassword://development}"

# Check if using OnePassword and if op CLI is available
if [[ "$PROVIDER" == onepassword://* ]]; then
    if ! command -v op &> /dev/null; then
        echo "❌ OnePassword CLI (op) not found. Please install it first."
        echo "Contact your admin for help."
        exit 1
    fi
    
    # Check if signed in to 1Password
    if ! op vault list &>/dev/null 2>&1; then
        echo "🔑 Not signed in to 1Password. Signing in..."
        eval $(op signin)
    fi
    
    echo "This helper will guide you through setting up your API keys in OnePassword."
    echo "Your secrets will be stored in the 'development' vault."
else
    echo "This helper will guide you through setting up your API keys."
    echo "Using provider: $PROVIDER"
fi
echo ""

# Function to set a secret
set_secret() {
    local key=$1
    local description=$2
    local required=${3:-false}
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔑 $description"
    
    if [ "$required" = "true" ]; then
        echo "   ⚠️  REQUIRED for OpenCode/AI features"
    else
        echo "   (Optional - press Enter to skip)"
    fi
    
    # Check if secret already exists
    if secretspec get "$key" --provider "$PROVIDER" &> /dev/null 2>&1; then
        echo "   ✅ Already configured"
        read -p "   Update existing value? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # Prompt for value
    read -s -p "   Enter value: " value
    echo
    
    if [ -z "$value" ]; then
        if [ "$required" = "true" ]; then
            echo "   ❌ Skipped (required for full functionality)"
        else
            echo "   ⏭️  Skipped"
        fi
        return
    fi
    
    # Set the secret with the configured provider
    if echo "$value" | secretspec set "$key" --provider "$PROVIDER" --stdin; then
        echo "   ✅ Saved to ${PROVIDER%%://*}"
    else
        echo "   ❌ Failed to save"
    fi
}

# Main setup flow
echo "📝 Setting up API keys for AI services..."
echo ""

# Required keys
set_secret "OPENAI_API_KEY" "OpenAI API Key (GPT-4, required for OpenCode)" true
set_secret "EXA_API_KEY" "Exa Search API Key (for advanced search MCP)" true

# Optional keys
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Optional Service API Keys"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

set_secret "CONTEXT7_API_KEY" "Context7 API Key (documentation MCP server)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SecretSpec configuration complete!"
echo ""
if [[ "$PROVIDER" == onepassword://* ]]; then
    echo "Your secrets are stored securely in:"
    echo "  • OnePassword vault: ${PROVIDER#onepassword://}"
    echo "  • Access them at: https://my.1password.com/"
else
    echo "Your secrets are stored securely in:"
    echo "  • macOS: Keychain Access"
    echo "  • Linux: Secret Service (GNOME Keyring/KWallet)"
    echo "  • Windows: Windows Credential Manager"
fi
echo ""
echo "To verify your configuration:"
echo "  secretspec check         # Check all required secrets are set"
echo "  secretspec get KEY       # Get a specific secret (won't print value)"
echo ""
echo "To use in development:"
echo "  devenv shell             # Secrets auto-injected as env vars"
echo ""
echo "💡 Tips:"
echo "  • Current profile: ${SECRETSPEC_PROFILE:-development}"
echo "  • Current provider: $PROVIDER"
echo "  • Switch profiles: export SECRETSPEC_PROFILE=production"
echo "  • Change provider: export SECRETSPEC_PROVIDER=keyring"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
