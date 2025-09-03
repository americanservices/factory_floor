{
  description = "Factory Floor - AI development workflow as a devenv module";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    devenv.url = "github:cachix/devenv/latest";
    dagger.url = "github:dagger/nix";
    dagger.inputs.nixpkgs.follows = "nixpkgs";

    # Fork of opencode with OpenPipe fix and flake apps
    opencode-fork.url = "github:americanservices/opencode-openpipe-fork?ref=fix/openpipe-reasoning";
  };

  outputs = { self, opencode-fork, ... }@inputs: {
    # Export your devenv.nix as a reusable module
    devenvModules = {
      default = ./devenv.nix;
      factory-floor = ./devenv.nix;
    };

    # Also provide templates for easy setup
    templates = {
      default = {
        path = ./template;
        description = "Factory Floor development environment";
      };
    };

    # Expose the opencode-dev app from our fork for common systems
    apps = {
      aarch64-darwin.opencode-dev = opencode-fork.apps.aarch64-darwin.opencode-dev;
      x86_64-darwin.opencode-dev  = opencode-fork.apps.x86_64-darwin.opencode-dev;
      aarch64-linux.opencode-dev  = opencode-fork.apps.aarch64-linux.opencode-dev;
      x86_64-linux.opencode-dev   = opencode-fork.apps.x86_64-linux.opencode-dev;
    };
  };
}
