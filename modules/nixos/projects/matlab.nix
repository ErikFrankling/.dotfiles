{
  config,
  pkgs,
  options,
  lib,
  inputs,
  ...
}:
{
  nixpkgs.overlays = [
    # (
    #   final: prev: {
    #     # Your own overlays...
    #   }
    # )
    inputs.nix-matlab.overlay
  ];

  environment.systemPackages = with pkgs; [ matlab ];
}

# Follow these instructions to install matlab has to be done imperatively on every machine:
# https://gitlab.com/doronbehar/nix-matlab
#
# Run matlab for the first time ligin in the terminal with:
# matlab -nodisplay
#
# If MATLAB fails with:
#   libmwfoundation_crash_handling.so: cannot enable executable stack
# then MathWorks shipped/cached libraries with executable-stack metadata.
# This is not a license issue. Fix the mutable MATLAB/ServiceHost install with:
#   nix shell nixpkgs#prelink -c execstack -c \
#     /home/erikf/matlab/bin/glnxa64/libmwfoundation_crash_handling.so \
#     /home/erikf/.MathWorks/ServiceHost/-mw_shared_installs/*/bin/glnxa64/libmwfoundation_crash_handling.so \
#     /home/erikf/matlab/bin/glnxa64/libgmp.so.3.4.1 \
#     /home/erikf/matlab/bin/glnxa64/libmwblas.so \
#     /home/erikf/matlab/bin/glnxa64/libmwlapack.so \
#     /home/erikf/matlab/bin/glnxa64/mwfatalexit_crash_handler
#
# MATLAB is an XWayland app on Hyprland. With monitor scale = 2, compositor
# scaling makes it blocky/pixelated. Keep Hyprland's global XWayland unscale
# option enabled in modules/home-manager/hyprland/default.nix:
#   xwayland.force_zero_scaling = true;
#
# Run in MATLAB to scale the UI on Hyprland/XWayland with force_zero_scaling:
# >> s = settings;
# >> s.webwindowscale.DisplayScaleFactor.PersonalValue = 2.0
#
# Old/legacy scale setting kept for reference:
# >> s = settings;s.matlab.desktop.DisplayScaleFactor
# >> s.matlab.desktop.DisplayScaleFactor.PersonalValue = 2.0
