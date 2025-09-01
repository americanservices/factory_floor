#!/usr/bin/env bash
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   🔐 1Password Secret Verification for OpenCode"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if op CLI is available
if ! command -v op &> /dev/null; then
    echo "❌ OnePassword CLI (op) not found. Please install it first."
    echo ""
    echo "Installation instructions:"
    echo "  macOS: brew install 1password-cli"
    echo "  Linux: https://1password.com/downloads/command-line/"
    echo ""
    exit 1
fi

# Check if signed in to 1Password
if ! op vault list &>/dev/null 2>&1; then
    echo "🔑 Not signed in to 1Password. Signing in..."
    if ! eval $(op signin); then
        echo "❌ Failed to sign in to 1Password."
        echo "Please sign in manually: eval \$(op signin)"
        exit 1
    fi
fi

echo "This helper verifies your 1Password secrets are accessible for OpenCode."
echo "Your secrets are stored in the 'development' vault."
echo ""

# Function to verify a secret exists in 1Password
verify_secret() {
    local key=$1
    local op_item_name=$2
    local description=$3
    local required=${4:-false}
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔑 $description"
    
    if [ "$required" = "true" ]; then
        echo "   ⚠️  REQUIRED for OpenCode/AI features"
    else
        echo "   (Optional)"
    fi
    
    # Check if secret exists in 1Password
    if op item get "$op_item_name" --vault development &>/dev/null; then
        # Check if secret has a value
        secret_value=$(op item get "$op_item_name" --vault development --field credential --reveal 2>/dev/null || echo "")
        if [ -n "$secret_value" ]; then
            echo "   ✅ Found in 1Password (${#secret_value} characters)"
            return 0
        else
            echo "   ⚠️  Found but empty in 1Password"
            return 1
        fi
    else
        echo "   ❌ Not found in 1Password vault 'development'"
        if [ "$required" = "true" ]; then
            echo "   Please add '$op_item_name' to your 1Password development vault"
        fi
        return 1
    fi
}

# Main verification flow
echo "📝 Verifying API keys in 1Password vault..."
echo ""

# Track success/failure
all_required_found=true

# Required keys for OpenCode
verify_secret "ANTHROPIC_API_KEY" "ANTHROPIC_API_KEY" "Anthropic API Key (required for OpenCode)" true || all_required_found=false

# Required keys for MCP servers
verify_secret "OPENAI_API_KEY" "OPENAI_API_KEY" "OpenAI API Key (required for some MCP servers)" true || all_required_found=false
verify_secret "EXA_API_KEY" "Exa MCP" "Exa Search API Key (required for search MCP)" true || all_required_found=false

# Optional keys
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Optional Service API Keys"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

verify_secret "CONTEXT7_API_KEY" "CONTEXT7_API_KEY" "Context7 API Key (documentation MCP server)"
verify_secret "UPSTASH_VECTOR_REST_URL" "UPSTASH_VECTOR_REST_URL" "Upstash Vector REST URL (for Context7)"
verify_secret "UPSTASH_VECTOR_REST_TOKEN" "UPSTASH_VECTOR_REST_TOKEN" "Upstash Vector REST Token (for Context7)"
verify_secret "GITHUB_TOKEN" "GITHUB_TOKEN" "GitHub Token (for GitHub MCP server)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$all_required_found" = true ]; then
    echo "✅ 1Password Secret Verification Complete!"
    echo ""
    echo "Your secrets are accessible from 1Password vault 'development'."
    echo "OpenCode will automatically use these when launching."
else
    echo "⚠️  Missing Required Secrets!"
    echo ""
    echo "Please add the missing required secrets to your 1Password 'development' vault"
    echo "before using OpenCode with MCP servers."
fi

echo ""
echo "🔐 Loading secrets into current shell environment..."
echo ""

# Load the secrets into environment variables
if [ "$all_required_found" = true ]; then
    echo "📥 Exporting environment variables..."
    
    # Export required keys
    export ANTHROPIC_API_KEY=$(op item get "ANTHROPIC_API_KEY" --vault development --field credential --reveal)
    echo "  ✅ ANTHROPIC_API_KEY exported"
    
    export OPENAI_API_KEY=$(op item get "OPENAI_API_KEY" --vault development --field credential --reveal)
    echo "  ✅ OPENAI_API_KEY exported"
    
    export EXA_API_KEY=$(op item get "Exa MCP" --vault development --field credential --reveal)
    echo "  ✅ EXA_API_KEY exported"
    
    # Export optional keys (if available)
    if op item get "CONTEXT7_API_KEY" --vault development &>/dev/null; then
        export CONTEXT7_API_KEY=$(op item get "CONTEXT7_API_KEY" --vault development --field credential --reveal)
        echo "  ✅ CONTEXT7_API_KEY exported"
    fi
    
    if op item get "UPSTASH_VECTOR_REST_URL" --vault development &>/dev/null; then
        export UPSTASH_VECTOR_REST_URL=$(op item get "UPSTASH_VECTOR_REST_URL" --vault development --field credential --reveal)
        echo "  ✅ UPSTASH_VECTOR_REST_URL exported"
    fi
    
    if op item get "UPSTASH_VECTOR_REST_TOKEN" --vault development &>/dev/null; then
        export UPSTASH_VECTOR_REST_TOKEN=$(op item get "UPSTASH_VECTOR_REST_TOKEN" --vault development --field credential --reveal)
        echo "  ✅ UPSTASH_VECTOR_REST_TOKEN exported"
    fi
    
    if op item get "GITHUB_TOKEN" --vault development &>/dev/null; then
        export GITHUB_TOKEN=$(op item get "GITHUB_TOKEN" --vault development --field credential --reveal)
        echo "  ✅ GITHUB_TOKEN exported"
    fi
    
    # Additional environment variables that may be needed
    export GEMINI_API_KEY="${GEMINI_API_KEY:-}"
    
    echo ""
    echo "✅ Secrets loaded into environment!"
    echo ""
    echo "🔍 Verification:"
    echo "  • ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:+SET}"
    echo "  • OPENAI_API_KEY: ${OPENAI_API_KEY:+SET}"
    echo "  • EXA_API_KEY: ${EXA_API_KEY:+SET}" 
    echo "  • CONTEXT7_API_KEY: ${CONTEXT7_API_KEY:+SET}"
    echo "  • UPSTASH_VECTOR_REST_URL: ${UPSTASH_VECTOR_REST_URL:+SET}"
    echo "  • UPSTASH_VECTOR_REST_TOKEN: ${UPSTASH_VECTOR_REST_TOKEN:+SET}"
    echo "  • GITHUB_TOKEN: ${GITHUB_TOKEN:+SET}"
    
else
    echo "❌ Cannot load secrets - some required secrets are missing."
    echo "Please add the missing secrets to 1Password first."
fi

echo ""
echo "📋 Usage:"
echo ""
echo "To use these secrets with OpenCode:"
echo "  source ./setup-secrets.sh   # Load secrets (run this command)"
echo "  opencode                    # Start OpenCode with secrets available"
echo ""
echo "💡 Tips:"
echo "  • Use 'source ./setup-secrets.sh' to load secrets into your current shell"
echo "  • Secrets are loaded from 1Password each time you source this script"
echo "  • OpenCode will automatically use these environment variables"
echo "  • MCP servers are configured in .opencode.json and will use these secrets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"