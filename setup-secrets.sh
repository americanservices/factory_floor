#!/usr/bin/env bash
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   🔐 SecretSpec Configuration Helper"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if secretspec is available
if ! command -v secretspec &> /dev/null; then
    echo "❌ SecretSpec not found. Please run 'devenv shell' first."
    exit 1
fi

echo "This helper will guide you through setting up your API keys securely."
echo "Your secrets will be stored in your system's keyring (macOS Keychain)."
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
    if secretspec get "$key" &> /dev/null; then
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
    
    # Set the secret
    if secretspec set "$key" "$value"; then
        echo "   ✅ Saved to keyring"
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
echo "Your secrets are stored securely in:"
echo "  • macOS: Keychain Access"
echo "  • Linux: Secret Service (GNOME Keyring/KWallet)"
echo "  • Windows: Windows Credential Manager"
echo ""
echo "To verify your configuration:"
echo "  secretspec list          # List all configured secrets"
echo "  secretspec validate      # Check all secrets are accessible"
echo ""
echo "To use in development:"
echo "  devenv shell             # Secrets auto-injected as env vars"
echo ""
echo "💡 Tips:"
echo "  • Secrets are profile-specific (default/development/production)"
echo "  • Switch profiles: export SECRETSPEC_PROFILE=production"
echo "  • CI uses different provider: SECRETSPEC_PROVIDER=env"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
