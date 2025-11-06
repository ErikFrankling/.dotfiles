{ ... }:
{
  programs.kitty = {
    enable = true;
    # settings = {
    # };
    keybindings = {
      # Disable kitty's unicode input
      "ctrl+shift+u" = "no_op";
    };
  };
}
