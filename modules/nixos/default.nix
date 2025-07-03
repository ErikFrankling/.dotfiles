{
  config,
  pkgs,
  inputs,
  username,
  ...
}:

{
  imports = [
    ./main-user.nix
    ./fonts.nix
    ./zig.nix
    # ./yubikey-gpg.nix
    ./qmk.nix
    ./secrets.nix
    # ./nm.nix
    # ./projects/dtek.nix
    ./syncthing.nix
  ];

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    extraOptions = ''
      min-free = ${toString (1024 * 1024 * 1024 * 10)} # will run GC if less than 10GB is free
    '';

    optimise.automatic = true;
    optimise.dates = [ "05:00" ]; # Optional; allows customizing optimisation schedule

    registry = {
      nixpkgs.to = {
        type = "path";
        path = pkgs.path;
        # narHash = pkgs.narHash;
        narHash = builtins.readFile (
          pkgs.runCommandLocal "get-nixpkgs-hash" {
            nativeBuildInputs = [ pkgs.nix ];
          } "nix-hash --type sha256 --sri ${pkgs.path} > $out"
        );
      };
    };
  };

  # Enable networking
  networking.networkmanager.enable = true;
  # networking.networkmanager.wifi.backend = "iwd";

  programs.wireshark.enable = true;

  # users.extraUsers.${username}.extraGroups = [ "wireshark" ];

  nixpkgs.config.allowBroken = true;
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wireshark
    wl-clipboard
    wl-clipboard-x11
    # networkmanager-openvpn
    # networkmanagerapplet
  ];
  main-user.enable = true;
  main-user.userName = "${username}";

  programs.fish.enable = true;

  # nix.settings.max-jobs = 1;
  # nix.settings.cores = 1;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Set your time zone.
  time.timeZone = "Europe/Stockholm";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "sv_SE.UTF-8";
    LC_IDENTIFICATION = "sv_SE.UTF-8";
    LC_MEASUREMENT = "sv_SE.UTF-8";
    LC_MONETARY = "sv_SE.UTF-8";
    LC_NAME = "sv_SE.UTF-8";
    LC_NUMERIC = "sv_SE.UTF-8";
    LC_PAPER = "sv_SE.UTF-8";
    LC_TELEPHONE = "sv_SE.UTF-8";
    LC_TIME = "sv_SE.UTF-8";
  };

  security.sudo.wheelNeedsPassword = false;

  # Enable automatic login for the user.
  services.getty.autologinUser = "${username}";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:
  # system.autoUpgrade.enable = true;
  # system.autoUpgrade.allowReboot = true;

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 22 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
