{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellScriptBin "kitty-plain" ''
      exec env ZELLIJ=1 ${pkgs.kitty}/bin/kitty "$@"
    '')
  ];

  programs.kitty = {
    enable = true;
    # settings = {
    # };
    keybindings = {
      # Disable kitty's unicode input
      "ctrl+shift+u" = "no_op";
    };
  };

  xdg.desktopEntries.kitty-plain = {
    name = "Kitty Plain";
    genericName = "Terminal Emulator";
    comment = "Launch Kitty without auto-starting zellij";
    exec = "kitty-plain";
    icon = "kitty";
    terminal = false;
    categories = [
      "System"
      "TerminalEmulator"
    ];
    startupNotify = true;
  };
}
