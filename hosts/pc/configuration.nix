{
  config,
  pkgs,
  inputs,
  hostName,
  username,
  otherPkgs,
  ...
}:

{
  services.local-stt.enable = true;

  # Removed 2026-11-11: the pc no longer has remote access to the work laptop
  # (hosts/samsung-ablo/configuration.nix turns sshd off).
  # The PC stays outside the tailnet for Mullvad. Reuse the Samsung SSH
  # host's Proxmox jump route; only this PC can reach the forwarded port.
  # T3 still requires a real pairing credential (stored by its desktop UI).
  # services.autossh.sessions = [
  #   {
  #     name = "samsung-t3code";
  #     user = username;
  #     extraArguments = "-N -T -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=10 -L 127.0.0.1:3774:127.0.0.1:3773 samsung-ablo";
  #   }
  # ];

  # The work laptop's T3 Code server for the T3 app here (Erik, 2026-11-13).
  # No SSH into the laptop: the tunnel ends on proxmox, which reaches the
  # laptop's T3 port on the home tailnet (node samsung-ablo-home, served by
  # hosts/samsung-ablo/tailnets.nix). The app connects to
  # http://localhost:3774 and needs a pairing credential from the laptop.
  services.autossh.sessions = [
    {
      name = "samsung-t3code";
      user = username;
      extraArguments = "-N -T -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=10 -L 127.0.0.1:3774:100.117.112.105:3773 proxmox";
    }
  ];

  # The work laptop's T3 Code server, linked into this one (2026-11-13). The
  # laptop serves it on its home-tailnet node samsung-ablo-home
  # (hosts/samsung-ablo/tailnets.nix). The pc is not a tailnet node, so it
  # reaches that node through proxmox, the tailnet's LAN router, and knows
  # its MagicDNS name from here. Tailnet addresses are fixed per node.
  networking.hosts."100.117.112.105" = [
    "samsung-ablo-home.tail017bd6.ts.net"
    "samsung-ablo-home"
  ];
  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "route-samsung-ablo-home" ''
        if [ "$2" = up ] || [ "$2" = dhcp4-change ]; then
          ${pkgs.iproute2}/bin/ip route replace 100.117.112.105/32 via 192.168.50.10 || true
        fi
      '';
    }
  ];

  # Logs and metrics to the homelab (modules/nixos/observability).
  observability = {
    enable = true;
    probes = {
      time-agent = "http://127.0.0.1:5600/health";
      t3code = "http://127.0.0.1:3773/";
    };
  };

  # Daily: pull main and switch to the system the homelab built.
  autoUpdate.enable = true;

  # Agents and Nix builds stay behind the desktop; uncached builds go to the
  # homelab builder with Erik's key (the one authorized there).
  agentPriority = {
    enable = true;
    remoteBuilder.sshKey = "/home/${username}/.ssh/id_ed25519";
  };

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos
    # ../../modules/nixos/openvpn.nix # archived: home VPN is Tailscale now
    # ../../modules/nixos/tailscale.nix -- deliberately NOT imported: this box
    # lives inside the 192.168.50.0/24 subnet the tailnet already routes to,
    # so membership adds nothing and conflicts with Mullvad's lockdown. Other
    # tailnet devices reach it through the subnet router.
    # ../../modules/nixos/laptop.nix
    ../../modules/nixos/mullvad.nix
    ../../modules/nixos/dev-preview.nix
    ../../modules/nixos/local-stt.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/1password.nix
    # Was disabled for a while: under getty autologin PAM never unlocked the
    # keyring, so every Secret Service request prompted for a password nobody
    # knew. The module now seeds a passwordless, always-unlocked keyring.
    ../../modules/nixos/keyring.nix
    ../../modules/nixos/game.nix
    # ../../modules/nixos/ollama.nix
    inputs.home-manager.nixosModules.default
    ../../modules/nixos/secure-boot.nix
    ../../modules/nixos/neptune.nix
    ../../modules/nixos/llama-swap.nix
    ../../modules/nixos/agent-priority
    # ../../modules/nixos/kokoro-tts.nix # read-aloud small voice on the PC CPU; now on the homelab GTX 1060 (saves PC RAM)
    # ../../modules/nixos/executor.nix # local container; Executor runs on the homelab k3s instead
    # inputs.private.nixosModules.default # extra llama-swap models, no longer used (see flake.nix)
    ../../modules/nixos/auto-update.nix
    # The real GPU % for the shell; profile_peak below makes amdgpu's own read 100.
    ../../modules/nixos/gpu-busy
    # ../../modules/nixos/llama-cpp.nix
    # ../../modules/nixos/ai-server.nix
    # ../../modules/nixos/vm-host.nix
    # ../../modules/nixos/vm-host-simple.nix
    # ./windows-vm.nix
  ];

  # programs.ladybird.enable = true;

  # fix for gpu not using max memmory clock speeds
  hardware.enableRedistributableFirmware = true;
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="drm", DRIVERS=="amdgpu", KERNEL=="card1", ATTR{device/power_dpm_force_performance_level}="profile_peak"
  '';

  services.openssh = {
    settings.PasswordAuthentication = true;
  };

  virtualisation.docker.enable = true;
  users.extraUsers."${username}".extraGroups = [ "docker" ];
  virtualisation.vmware.host.enable = true;
  # patchelf 0.19.2 writes vmnet-natd, the one non-PIE binary it has to grow, with
  # a program header table its load segment no longer covers ("the PHDR segment is
  # not covered by a LOAD segment"), so it segfaults in ld.so before main and
  # vmware-networks fails on every start, and `rebuild` with it (status 4). Patch
  # this package with the older patchelf; only this package changes.
  # nix-update-doctor: 2026-11-02 https://github.com/NixOS/patchelf/releases/tag/0.19.3
  # drop this when nixpkgs' patchelf is 0.19.3 or newer.
  virtualisation.vmware.host.package = pkgs.vmware-workstation.overrideAttrs (old: {
    nativeBuildInputs = [ otherPkgs.pkgsStable.patchelf ] ++ old.nativeBuildInputs;
  });
  # aggregateModules now reads a <module>.ko.cer for every module, and vmmon and
  # vmnet install without Kbuild's modules_install so they have none, which fails
  # the build ("cat: misc/vmmon.ko.cer"). They are unsigned, so there is no
  # certificate to add: an empty file is what is true. Only this package changes;
  # the kernel and its other modules stay cached.
  # nix-update-doctor: 2026-11-02 https://github.com/NixOS/nixpkgs/issues/575192
  # (fix: https://github.com/NixOS/nixpkgs/pull/578004); drop this when it lands.
  boot.kernelPackages = pkgs.linuxPackages.extend (
    _: super: {
      vmware = super.vmware.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          for module in $out/lib/modules/*/misc/*.ko*; do
            touch "''${module%%.ko*}.ko.cer"
          done
        '';
      });
    }
  );

  # boot.kernelParams = [ "acpi_backlight=none" ];
  # boot.kernelParams = [ "amdgpu.backlight=0" "acpi_backlight=none" ];

  # nixpkgs.config.permittedInsecurePackages = [
  #   "electron-33.4.11"
  # ];

  # boot.kernelPackages = pkgs.linuxPackages_6_12;

  # boot.kernelPackages =
  #   let
  #     version = "6.12.31";
  #     kernel = pkgs.linuxKernel.kernels.linux_6_12.override {
  #       argsOverride = {
  #         inherit version;
  #         src = pkgs.fetchurl {
  #           url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
  #           hash = "sha256-sExbPl324KpenNHv5Sf6yZ+d05pDuX8Tsi+MqT5SS6c="; # to be filled in
  #         };
  #         modDirVersion = null; # https://github.com/NixOS/nixpkgs/blob/007e91615b8127deb57ba0b08e12542abaea1c3f/pkgs/os-specific/linux/kernel/generic.nix#L44
  #       };
  #     };
  #   in
  #   pkgs.linuxKernel.packagesFor kernel;

  # fix for amdgpu kernel bug https://gitlab.freedesktop.org/drm/amd/-/issues/3388
  boot.kernelParams = [
    "amdgpu.dcdebugmask=0x10"
    "amdgpu.runpm=0" # fix for amdgpu gpu not using max memmory clock speeds
  ];

  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.syncthing-cert = { };
  sops.secrets.syncthing-key = { };
  # Bearer token for the company brain (homelab), read by brain-skill-sync.
  sops.secrets.brain-token.owner = username;
  # Bearer token for the Time MCP server (homelab time-v2 /mcp), handed to
  # Claude sessions started in the personal agent's folder
  # (modules/home-manager/executor-harness.nix, hosts/pc/home.nix).
  sops.secrets.time-mcp-token.owner = username;
  # Onyx, the search over everything (homelab apps/onyx.yaml): the search-sync
  # timer's token (modules/home-manager/search-sync.nix) and the read:search
  # token for the personal agent's MCP (executor-harness.nix). The admin
  # password for https://search.erikfrankling.duckdns.org is onyx-admin-password
  # (user erik.frankling@frankling.se); nothing reads it.
  sops.secrets.search-sync-token.owner = username;
  sops.secrets.search-mcp-token.owner = username;
  sops.secrets.kth-password = {
    owner = username;
  };
  # Canvas API token for agents (agent-canvas-token, computer-use/logins.nix).
  sops.secrets.canvas-token.owner = username;
  # Ingest token of the school calendar (homelab apps/school.yaml), read by
  # the school-sync unit (modules/home-manager/school-sync).
  sops.secrets.school-ingest-token.owner = username;
  # OpenCode Go API key (modules/home-manager/ai.nix merges it into opencode auth.json).
  sops.secrets.opencode-go-key.owner = username;
  # FCM service account of the Firebase project "t3code-erik-push": the T3
  # server sends native push to Erik's T3 app with it (hosts/pc/home.nix,
  # modules/nixos/notify). The app's google-services.json is in the same file.
  sops.secrets.t3code-fcm-service-account = {
    sopsFile = ../../secrets/notify.yaml;
    owner = username;
  };

  networking.hostName = "${hostName}"; # Define your hostname.
  # eno1 and wlp11s0 sit on the same 192.168.50.0/24. Linux answers ARP for any
  # local address on any interface, so the homelab VM resolved the wired
  # 192.168.50.232 to the Wi-Fi MAC; its traffic arrived on wlp11s0 and the
  # eno1-only firewall rules (dev preview :3999, T3 :3773) dropped it
  # (2026-11-11: phone/x-graph and t3code checks timed out). Answer ARP only
  # for the address on the interface that received the request.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
  };
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/562a2388-4fb0-4775-ad5e-d0624308f232";
    fsType = "ext4";
  };

  systemd.tmpfiles.rules = [
    "d /mnt/data 0750 ${username} users -"
  ];

  time.hardwareClockInLocalTime = true;

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "";
      layout = "us";
    };
  };

  # Configure console keymap
  # console.keyMap = "sv-latin1";

  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = {
      inherit
        inputs
        hostName
        username
        otherPkgs
        ;
    };
    users = {
      "${username}" = import ./home.nix;
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    # 6789 # retired Husk localhost web UI — reachable on the LAN for dev review
  ];

  # T3 Code web UI and wayvnc — reachable only through the physical LAN
  # interface (tailnet devices come in through the subnet router, so they
  # arrive here too). wayvnc runs without auth on purpose; this interface
  # scoping is the guard. 5900 = both monitors, 5901/5902 = single monitors
  # (see hosts/pc/home.nix).
  networking.firewall.interfaces.eno1.allowedTCPPorts = [
    3773
    5900
    5901
    5902
  ];
  # Computer-use MCP bridge (agent-computer-use-http, :4790) for Executor on
  # the homelab. It has no auth of its own and drives this desktop, so only
  # the k3s VM (192.168.50.100) may connect -- never the whole LAN.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -i eno1 -p tcp --dport 4790 -s 192.168.50.100 -j nixos-fw-accept
  '';
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    #  wget
  ];
}
