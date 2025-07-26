{ pkgs, ... }:

{
  hardware.keyboard.qmk.enable = true;

  environment.systemPackages = with pkgs; [
    via
    qmk
    vial
    # qmk-udev-rules # the only relevant
    # qmk_hid
  ];

  services.udev.packages = with pkgs; [
    # qmk
    qmk-udev-rules # the only relevant
    # qmk_hid
    # via
    # vial
  ];
}
