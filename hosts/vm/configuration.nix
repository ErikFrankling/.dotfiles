{
  config,
  pkgs,
  inputs,
  hostName,
  username,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos
    inputs.home-manager.nixosModules.default
  ];

  networking.hostName = "nix-vm"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  # boot.loader.grub.device = "/dev/nvme0n1";
  boot.loader.grub.useOSProber = true;

  # Configure keymap in X11
  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "";
      layout = "se";
    };
  };

  # Configure console keymap
  console.keyMap = "sv-latin1";

  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = { inherit inputs hostName username; };
    users = {
      "${username}" = import ./home.nix;
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    #  wget
  ];
}
