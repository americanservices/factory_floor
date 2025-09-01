#!/bin/bash
# Factory Floor Starship Setup Script
# Configures starship.rs prompt for optimal Factory Floor workflow experience

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if starship is installed
check_starship_installed() {
    if ! command -v starship >/dev/null 2>&1; then
        log_error "Starship is not installed. Please install it first:"
        echo ""
        echo "# Install via package manager"
        echo "# Arch Linux: pacman -S starship"
        echo "# Ubuntu/Debian: snap install starship"
        echo "# macOS: brew install starship"
        echo ""
        echo "# Or install via cargo:"
        echo "cargo install starship --locked"
        echo ""
        echo "# Or via install script:"
        echo "curl -sS https://starship.rs/install.sh | sh"
        exit 1
    fi
    log_success "Starship is installed"
}

# Backup existing starship config
backup_existing_config() {
    local config_dir="$HOME/.config"
    local config_file="$config_dir/starship.toml"
    
    if [ -f "$config_file" ]; then
        local backup_file="$config_file.backup-$(date +%Y%m%d-%H%M%S)"
        log_info "Backing up existing starship config to: $backup_file"
        cp "$config_file" "$backup_file"
        log_success "Backup created"
    fi
}

# Install Factory Floor starship config
install_config() {
    local config_dir="$HOME/.config"
    local config_file="$config_dir/starship.toml"
    local source_config="$(dirname "$0")/starship.toml"
    
    # Create config directory if it doesn't exist
    mkdir -p "$config_dir"
    
    # Copy the Factory Floor starship config
    if [ -f "$source_config" ]; then
        log_info "Installing Factory Floor starship configuration..."
        cp "$source_config" "$config_file"
        log_success "Starship configuration installed to: $config_file"
    else
        log_error "Source starship.toml not found at: $source_config"
        exit 1
    fi
}

# Check shell configuration
check_shell_config() {
    local shell_name=$(basename "$SHELL")
    local init_command='eval "$(starship init '"$shell_name"')"'
    local config_file=""
    
    case "$shell_name" in
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                config_file="$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                config_file="$HOME/.bash_profile"
            fi
            ;;
        zsh)
            config_file="$HOME/.zshrc"
            ;;
        fish)
            config_file="$HOME/.config/fish/config.fish"
            init_command="starship init fish | source"
            ;;
        *)
            log_warning "Unsupported shell: $shell_name"
            return
            ;;
    esac
    
    if [ -n "$config_file" ]; then
        if [ -f "$config_file" ]; then
            if grep -q "starship init" "$config_file"; then
                log_success "Starship is already configured in your shell ($config_file)"
            else
                log_warning "Starship is not configured in your shell"
                echo ""
                echo "Add this line to your $config_file:"
                echo "  $init_command"
                echo ""
                read -p "Would you like me to add it automatically? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "" >> "$config_file"
                    echo "# Initialize starship prompt" >> "$config_file"
                    echo "$init_command" >> "$config_file"
                    log_success "Starship initialization added to $config_file"
                    log_info "Please restart your shell or run: source $config_file"
                fi
            fi
        else
            log_warning "Shell config file not found: $config_file"
            echo "You'll need to manually add the starship initialization to your shell config."
        fi
    fi
}

# Create MCP status directory if needed
setup_mcp_directory() {
    local mcp_dir=".mcp"
    local pids_dir="$mcp_dir/pids"
    
    if [ ! -d "$mcp_dir" ]; then
        log_info "Creating MCP status directory structure..."
        mkdir -p "$pids_dir"
        mkdir -p "$mcp_dir/logs"
        mkdir -p "$mcp_dir/sockets"
        log_success "MCP directory structure created"
    fi
}

# Test the configuration
test_configuration() {
    log_info "Testing starship configuration..."
    
    # Test if starship can load the config without errors
    if starship config >/dev/null 2>&1; then
        log_success "Starship configuration is valid"
    else
        log_error "Starship configuration has errors. Please check the config file."
        return 1
    fi
    
    # Test individual modules
    log_info "Testing custom modules..."
    
    # Test if git is available (most modules depend on it)
    if command -v git >/dev/null 2>&1; then
        log_success "Git is available for workflow status detection"
    else
        log_warning "Git is not available. Some workflow features may not work."
    fi
    
    return 0
}

# Main installation process
main() {
    echo ""
    echo "🏭 Factory Floor Starship Setup"
    echo "=============================="
    echo ""
    
    log_info "Starting Factory Floor starship configuration setup..."
    
    # Check prerequisites
    check_starship_installed
    
    # Backup and install
    backup_existing_config
    install_config
    
    # Setup supporting directories
    setup_mcp_directory
    
    # Check shell configuration
    check_shell_config
    
    # Test the installation
    if test_configuration; then
        echo ""
        log_success "Factory Floor starship configuration installed successfully!"
        echo ""
        echo "Features enabled:"
        echo "  🏭 Factory Floor issue tracking"
        echo "  🚀 Branch type indicators (feat, fix, etc.)"
        echo "  🚢 Git Town state (ready to ship, parked, etc.)"
        echo "  📁 Worktree status indicators"
        echo "  🔌 MCP server status"
        echo "  ↑↓ Git sync status indicators"
        echo ""
        echo "To see the new prompt, restart your shell or run:"
        echo "  source ~/.bashrc   # for bash"
        echo "  source ~/.zshrc    # for zsh"
        echo ""
    else
        log_error "Configuration test failed. Please check the setup."
        exit 1
    fi
}

# Help function
show_help() {
    echo "Factory Floor Starship Setup Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -t, --test     Test current configuration only"
    echo "  -b, --backup   Create backup of existing config only"
    echo ""
    echo "This script installs a starship.rs configuration optimized for"
    echo "the Factory Floor AI development workflow."
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -t|--test)
        log_info "Testing current starship configuration..."
        test_configuration
        exit $?
        ;;
    -b|--backup)
        backup_existing_config
        exit 0
        ;;
    *)
        main
        ;;
esac