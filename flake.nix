{
  description = "Factory Floor - AI development workflow as a devenv module";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    devenv.url = "github:cachix/devenv/latest";
    dagger.url = "github:dagger/nix";
    dagger.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, ... }@inputs: {
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
  };
}
