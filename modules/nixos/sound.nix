{ pkgs, ... }:

{
  # nix-update-doctor: 2026-11-10 services.pipewire.jack.enable is deprecated (global LD_LIBRARY_PATH impurity); JACK apps run as `pw-jack <app>` with pipewire.jack.
  environment.systemPackages = with pkgs; [
    qpwgraph
    pipewire.jack
  ];
  # Enable sound with pipewire.
  # sound.enable = true; # not ment to be used with pipwire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # jack.enable = true; # deprecated 2026-11-10, see pw-jack above
  };
}
