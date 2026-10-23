{
  config,
  pkgs,
  inputs,
  username,
  lib,
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
    ./ca-distrust.nix # roots distrusted before nixpkgs catches up (emSign G3)
    # ./nm.nix
    # ./projects/dtek.nix
    ./syncthing.nix
    ./ibus.nix
    ./krb5.nix
    ./nh.nix
    ./windows-vm
    ./notify # notify-erik: push notifications to Erik's phone
    ./observability # logs and metrics to the homelab (Alloy); enabled per host
  ];

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 1024;
    # zram-first tuning (ArchWiki "zram", Pop!_OS defaults). A high swappiness
    # makes the kernel compress idle anonymous memory into zram instead of
    # evicting file pages; with swappiness 10 it evicted program code and
    # re-read it from disk until the desktop froze with RAM and zram full and
    # no OOM kill (pc, 2026-10-23 01:35). page-cluster 0: zram has no seek
    # cost, so no readahead. A larger watermark gap wakes kswapd earlier.
    "vm.swappiness" = 150;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };

  # Compressed swap in RAM, used first: much faster than disk swap.
  zramSwap = {
    enable = true;
    # zstd compresses this machine's memory about 2.7x, so a full 75 % device
    # costs about 28 % of RAM. Disk swap (priority below 5) only takes over
    # when it is full.
    memoryPercent = 75;
    priority = 5;
  };

  # When memory really runs out, kill the right process instead of letting the
  # desktop thrash: below 5 % available RAM with under 60 % of swap free. The
  # victim is the highest oom_score, which already favours agents (adj 800)
  # and browser content processes (133-300) over the desktop (0); --prefer
  # and --avoid sharpen that. Notifications go to the desktop.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 60;
    enableNotifications = true;
    extraArgs = [
      "--prefer"
      "^(Isolated Web Co|Web Content|WebExtensions|\\.?claude.*|\\.?codex.*|\\.?opencode.*|node-MainThread|MainThread|tsc|tsgo|java|nix|qemu-system.*|bun|cc1plus|rustc|ffmpeg|stress-ng.*)$"
      "--avoid"
      "^(\\.?Hyprland.*|Xwayland|\\.?kitty.*|pipewire.*|wireplumber|systemd.*|dbus-.*|sshd|greetd|login|swayidle|hypridle|\\.?firefox-wrapp.*|t3code.*|\\.?t3-.*|nix-daemon|determinate-nix.*|lag-guard|warp-svc)$"
    ];
  };

  programs.nix-ld.enable = true;
  # Added to nix-ld's base set. These are what the chrome-headless-shell T3
  # Code downloads to ~/.t3/tools needs (html_preview / preview_* tools);
  # `t3 browser setup` would apt-get them, which does nothing on NixOS.
  programs.nix-ld.libraries = with pkgs; [
    glib
    nspr
    nss
    at-spi2-core # libatk, libatk-bridge, libatspi
    dbus
    expat
    libgbm
    libxkbcommon
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    udev
    alsa-lib
  ];

  # virtualisation.podman = {
  #   enable = true;
  #   dockerCompat = true;
  # };

  # Fish enables this by default. It make rebuilds slow
  documentation = {
    man.cache.enable = false;
    # dev.enable = true;
    # man.generateCaches = true;
    # nixos.includeAllModules = true;
  };

  # Determinate's NixOS module moves the generated nix.conf to
  # /etc/nix/nix.custom.conf (determinate 3.23), so defining that file here
  # collides ("duplicate entry nix/nix.custom.conf"). eval-cores lives in
  # nix.extraOptions below instead.
  # environment.etc."nix/nix.custom.conf".text = ''
  #   eval-cores = 0
  # '';
  environment.etc."dict.conf".text = "server dict.org";

  nix = {
    # nh clean is better
    # gc = {
    #   automatic = true;
    #   dates = "weekly";
    #   options = "--delete-older-than 10d";
    # };

    extraOptions = ''
      min-free = ${toString (1024 * 1024 * 1024 * 10)} # will run GC if less than 10GB is free
      eval-cores = 0
    '';

    optimise.automatic = true;
    optimise.dates = [ "05:00" ]; # Optional; allows customizing optimisation schedule

    settings = {
      auto-optimise-store = false;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      download-buffer-size = 524288000;
      substituters = [
        "https://install.determinate.systems"
        "https://cache.numtide.com" # prebuilt llm-agents.nix binaries (codex, etc.) — avoids compiling
        "https://nix-community.cachix.org" # community-built packages
      ];
      trusted-public-keys = [
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    # registry = {
    #   nixpkgs.to = {
    #     type = "path";
    #     path = pkgs.path;
    #     # narHash = pkgs.narHash;
    #     narHash = builtins.readFile (
    #       pkgs.runCommandLocal "get-nixpkgs-hash" {
    #         nativeBuildInputs = [ pkgs.nix ];
    #       } "nix-hash --type sha256 --sri ${pkgs.path} > $out"
    #     );
    #   };
    # };
  };

  # Enable networking
  networking.networkmanager.enable = true;
  # networking.networkmanager.wifi.backend = "iwd";

  # One owner for /etc/resolv.conf. NetworkManager, tailscaled, cloudflare-warp
  # and mullvad all write DNS config, and without a manager they overwrite the
  # file and each other. Daemons that speak D-Bus (tailscaled) then program
  # resolved instead of touching the file at all. Enabled for every host rather
  # than only the Tailscale ones, since the race does not need Tailscale.
  services.resolved = {
    enable = true;
    # cloudflare-warp proves its DNS path by resolving `connectivity-check.warp-svc`
    # before the tunnel is up. resolved refuses those names by default, so the
    # probe fails, warp never reaches Connected, and it cannot install the
    # resolver that would have answered. Without this the client is stuck at
    # "Connectivity check failed due to DNS Lookup Failed" forever.
    settings.Resolve.ResolveUnicastSingleLabel = true;
  };

  nixpkgs.config.allowBroken = true;
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wl-clipboard
    wl-clipboard-x11
    # networkmanager-openvpn
    # networkmanagerapplet
    distrobox
    dict
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
    # LC_MONETARY = "sv_SE.UTF-8";
    LC_NAME = "sv_SE.UTF-8";
    LC_NUMERIC = "sv_SE.UTF-8";
    LC_PAPER = "sv_SE.UTF-8";
    LC_TELEPHONE = "sv_SE.UTF-8";
    # LC_TIME = "sv_SE.UTF-8";
    LC_TIME = "en_GB.UTF-8";
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
    settings.PasswordAuthentication = lib.mkDefault false;
  };

  # Mosh server on every host, so `mosh <host>` works between the machines.
  # Also opens UDP 60000-61000 in the firewall; the client comes from
  # home-manager (modules/home-manager/default.nix).
  programs.mosh.enable = true;

  programs.ssh = {
    extraConfig = "
      Host student-shell
        HostName student-shell.sys.kth.se
        User erikfran
        PreferredAuthentications gssapi-with-mic
        GSSAPIAuthentication yes
        GSSAPIDelegateCredentials yes
        # GSSAPIKeyExchange yes
      Host pc
        Hostname 192.168.50.232
        User erikf
        KexAlgorithms curve25519-sha256
      # Through the Proxmox host, which is on the tailnet: the laptop's LAN
      # address changes with DHCP and it is off the LAN when away, but its
      # tailnet address is fixed and reachable from proxmox either way. The
      # pc cannot route to it directly (not a tailnet node, and WARP owns
      # 100.96.0.0/12). The alias keeps the pinned host key valid.
      Host framework
        Hostname 100.107.78.44
        ProxyJump proxmox
        HostKeyAlias framework
        ConnectTimeout 15
        User erikf
      Host octopi
        Hostname 192.168.50.162
        User pi
      Host proxmox
        Hostname 192.168.50.10
        User root
      Host naiaclaw
        Hostname 192.168.50.100
        User ubuntu
    ";
    # Pinned so unattended sessions (the morning systems check) can connect
    # in BatchMode without a first-contact prompt.
    knownHosts.framework.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZdbNRoE0KoFkRepeyTaxn/H0C84wlU/0zKguASTub5";
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
