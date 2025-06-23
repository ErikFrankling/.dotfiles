{ pkgs, ... }:

{
  # Package set
  environment.systemPackages = with pkgs; [ lxqt.lxqt-policykit ];

  environment.sessionVariables = {
    XCURSOR_SIZE = "32";
    GDK_SCALE = "2";
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
    graphics.enable = true; # only in nixos-unstable
    # Most wayland compositors need this
    # nvidia.modesetting.enable = true;
  };

  # XDG portal
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
}
