{ ... }:

{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
  ];


  hyprland = {
    monitors = [
      {
        name = "eDP-1";
        width = 2880;
        height = 1920;
        scale = "2";
        refreshRate = 120;
      }
    ];
    mouse = {
      sensitivity = "1.0";
      scroll_factor = "1.0";
    };
  };
}
