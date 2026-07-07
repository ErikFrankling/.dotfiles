{ pkgs, ... }:
let
  zellijKittyShell = pkgs.writeShellScriptBin "zellij-kitty-shell" ''
    exec ${pkgs.zellij}/bin/zellij
  '';
in
{
  xdg.configFile."kitty/plain.conf".text = ''
    include kitty.conf
    shell .
  '';

  home.packages = [
    zellijKittyShell
    (pkgs.writeShellScriptBin "kitty-plain" ''
      exec ${pkgs.kitty}/bin/kitty --config "$HOME/.config/kitty/plain.conf" "$@"
    '')
  ];

  programs.kitty = {
    enable = true;
    settings = {
      auto_reload_config = -1;
      shell = "${zellijKittyShell}/bin/zellij-kitty-shell";
    };
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
