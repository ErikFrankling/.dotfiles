{ pkgs, config, ... }:

{
  # home.packages = with pkgs; [
  #   fzf
  # ];

  programs.fzf.enable = true;
  # programs.fzf.tmux.enableShellIntegration = true;

  programs.zoxide.enable = true;
  programs.zoxide.enableFishIntegration = true;
}
