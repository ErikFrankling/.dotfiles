{ pkgs, config, ... }:

{
  # home.packages = with pkgs; [
  #   fzf
  # ];

  programs.zellij = {
    enable = true;
    enableFishIntegration = true;

    # exitShellOnExit = true;
    # themes = true;

    # Configuration written to
    # {file}$XDG_CONFIG_HOME/zellij/config.kdl.
    #
    # See <https://zellij.dev/documentation> for the full
    # list of options.
    # settings = builtins.readFile ./config.kdl;
  };
}
