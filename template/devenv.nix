{ pkgs, lib, config, inputs, ... }:

{
  # Factory Floor is imported via devenv.yaml
  # All the wt-*, agent-*, mcp-*, op-* commands come from there
  
  # Add any project-specific configuration here:
  
  # Example: Enable additional languages for this project
  # languages = {
  #   rust.enable = true;
  #   python.enable = true;
  # };
  
  # Example: Add project-specific packages
  # packages = with pkgs; [
  #   postgresql
  #   redis
  # ];
  
  # Example: Add project-specific scripts
  # scripts = {
  #   my-custom-command.exec = ''
  #     echo "This is specific to this project"
  #   '';
  # };
}
