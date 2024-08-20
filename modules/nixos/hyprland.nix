{ pkgs, ... }:

{
  environment.sessionVariables = {
    XCURSOR_SIZE = "15";
    # If your cursor becomes invisible
    # WLR_NO_HARDWARE_CURSORS = "1";
    # Hint electron apps to use wayland
    NIXOS_OZONE_WL = "1";
  };

  # Enabling hyprlnd on NixOS
  programs.hyprland = {
    enable = true;
    # nvidiaPatches = true;
    xwayland.enable = true;
  };

  hardware = {
    graphics.enable = true;
    # Most wayland compositors need this
    # nvidia.modesetting.enable = true;
  };

  # XDG portal
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
}
