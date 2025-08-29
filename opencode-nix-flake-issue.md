# Replace current installation process with Nix flake

## Summary

The current OpenCode installation process relies on multiple installation methods including a curl-based install script, npm/package managers, and OS-specific package managers. This creates maintenance overhead and inconsistent experiences across platforms. We should replace this with a modern Nix flake that provides reproducible, declarative installations across all platforms.

## Current Installation Issues

### Multiple Installation Methods
The current installation process supports:
- `curl -fsSL https://opencode.ai/install | bash` (YOLO method)
- `npm i -g opencode-ai@latest` (and bun/pnpm/yarn variants)
- `brew install sst/tap/opencode` (macOS/Linux)
- `paru -S opencode-bin` (Arch Linux)

This creates:
- **Maintenance overhead**: Multiple installation paths to maintain and test
- **Inconsistent environments**: Different dependency versions across installation methods
- **Security concerns**: Curl-to-bash installation is inherently risky
- **Platform fragmentation**: Different behaviors on different systems

### Current Complexity
The install script handles multiple directory priorities:
1. `$OPENCODE_INSTALL_DIR` - Custom installation directory
2. `$XDG_BIN_DIR` - XDG Base Directory Specification compliant path
3. `$HOME/bin` - Standard user binary directory
4. `$HOME/.opencode/bin` - Default fallback

## Proposed Solution: Nix Flake

### Benefits of Nix Flake Approach

1. **Reproducibility**: Exact same build and runtime environment across all platforms
2. **Declarative**: All dependencies and build steps defined in code
3. **Security**: Cryptographic hashing of all inputs, no curl-to-bash needed
4. **Development Experience**: `nix develop` provides instant dev environment
5. **Zero Installation**: Can run directly with `nix run github:sst/opencode`
6. **Binary Caching**: Pre-built binaries available from cache.nixos.org
7. **Rollbacks**: Easy to rollback to previous versions
8. **Cross-platform**: Same flake works on Linux, macOS, and NixOS

### Implementation Plan

#### Phase 1: Create Basic Flake
- [ ] Add `flake.nix` to repository root
- [ ] Define development environment with Bun and Go 1.24.x
- [ ] Set up build derivation for OpenCode binary
- [ ] Test across Linux and macOS

#### Phase 2: Advanced Flake Features
- [ ] Add multiple outputs (binary, development environment, documentation)
- [ ] Create NixOS module for system-wide installation
- [ ] Add Home Manager module for user-specific installation
- [ ] Set up GitHub Actions to build and cache flake outputs

#### Phase 3: Documentation and Migration
- [ ] Update README.md with Nix installation instructions
- [ ] Create migration guide from existing installation methods
- [ ] Deprecate curl-based installer (with sunset timeline)
- [ ] Update documentation site with Nix-specific content

### Example Flake Structure

```nix
{
  description = "OpenCode - AI coding agent for the terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        opencode = pkgs.buildGoModule rec {
          pname = "opencode";
          version = "0.1.0"; # Auto-detect from git or package.json
          
          src = ./.;
          
          nativeBuildInputs = [ pkgs.bun ];
          
          # Build process matching current `bun install && bun dev`
          buildPhase = ''
            bun install --frozen-lockfile
            bun run build
          '';
          
          # ... rest of build configuration
        };
      in
      {
        packages.default = opencode;
        packages.opencode = opencode;
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bun
            go_1_24
            nodejs
            git
          ];
          
          shellHook = ''
            echo "OpenCode development environment"
            echo "Run 'bun install && bun dev' to start development"
          '';
        };
        
        apps.default = {
          type = "app";
          program = "${opencode}/bin/opencode";
        };
      });
}
```

### User Experience Improvements

#### Current Installation
```bash
# Risky curl-to-bash
curl -fsSL https://opencode.ai/install | bash

# Or multiple package manager options
npm i -g opencode-ai@latest
brew install sst/tap/opencode
```

#### With Nix Flake
```bash
# Zero installation - try it immediately
nix run github:sst/opencode

# Install to user profile
nix profile install github:sst/opencode

# For NixOS users - add to configuration.nix
environment.systemPackages = [ inputs.opencode.packages.${system}.default ];

# For Home Manager users - add to home.nix
home.packages = [ inputs.opencode.packages.${system}.default ];

# Development environment
nix develop github:sst/opencode
```

## Migration Strategy

### Backward Compatibility
- Keep existing installation methods during transition period (6-12 months)
- Add deprecation warnings to curl installer
- Provide clear migration documentation

### Testing
- CI/CD integration to test flake builds
- Cross-platform testing (Linux, macOS, NixOS)
- Performance benchmarking against current installation methods

### Community Benefits
- Easier for contributors to set up development environment
- Consistent builds reduce "works on my machine" issues
- Better reproducibility for bug reports
- Integration with Nix ecosystem (NixOS, Home Manager, etc.)

## Implementation Considerations

### Technical Requirements
- Go 1.24.x compatibility in Nix packages
- Bun integration for TypeScript/JavaScript components
- Binary caching configuration for faster installs
- Proper handling of version detection and updates

### Documentation Updates
- Update README.md installation section
- Create dedicated Nix documentation page
- Add troubleshooting guide for Nix-specific issues
- Migration guide from existing installations

## Success Metrics

- [ ] Flake builds successfully on Linux and macOS
- [ ] Installation time comparable to or better than current methods
- [ ] Development environment setup time < 30 seconds with cache
- [ ] Zero security vulnerabilities in installation process
- [ ] Positive community feedback on installation experience
- [ ] Reduced installation-related support requests

## Related Issues

This addresses the installation complexity mentioned in the README and provides a more secure, reproducible alternative to the current curl-based installation method.

## Additional Context

This aligns with the growing adoption of Nix in the development community and provides a superior developer experience for projects with complex dependency requirements like OpenCode (Go + Bun + Node.js ecosystem).

The user preference for Nix profiles mentioned in their development environment makes this a natural fit for their workflow and could serve as a model for other users adopting Nix-based development environments.
