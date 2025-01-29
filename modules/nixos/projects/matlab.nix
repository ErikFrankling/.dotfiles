{ config, pkgs, options, lib, inputs, ... }:
{
  nixpkgs.overlays = [
    # (
    #   final: prev: {
    #     # Your own overlays...
    #   }
    # )
    inputs.nix-matlab.overlay
  ];

  environment.systemPackages = with pkgs;
    [
      matlab
    ];
}

# Follow these instructions to install matlab has to be done imperatively on every machine:
# https://gitlab.com/doronbehar/nix-matlab
#
# run in matlab to scale the UI:
# >> s = settings;s.matlab.desktop.DisplayScaleFactor
# >> s.matlab.desktop.DisplayScaleFactor.PersonalValue = 2.0
