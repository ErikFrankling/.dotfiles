{ pkgs, inputs, ... }:

{
  # Package set
  environment.systemPackages = with pkgs; [ lxqt.lxqt-policykit ];

  environment.sessionVariables = {
  };

  # Enabling hyprlnd on NixOS
  programs.hyprland = {
    enable = true;
    # nvidiaPatches = true;
    xwayland.enable = true;
    # set the flake package
    # package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # # make sure to also set the portal package, so that they are in sync
    # portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  hardware = {
    graphics =
      let
        # pkgs-unstable = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      in
      {
        enable = true; # only in nixos-unstable
        # package = pkgs-unstable.mesa;

        # if you also want 32-bit support (e.g for Steam)
        enable32Bit = true;
        # package32 = pkgs-unstable.pkgsi686Linux.mesa;
      };
    # Most wayland compositors need this
    # nvidia.modesetting.enable = true;
  };

  # XDG portal
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
}
