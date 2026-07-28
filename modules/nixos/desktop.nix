{
  pkgs,
  username,
  inputs,
  ...
}:

{
  imports = [
    ./bluetooth.nix
    ./sound.nix
    ./hyprland.nix
    ./projects/matlab.nix
    ./obs.nix
    ./firefox.nix
    ./ai.nix
  ];

  nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];

  environment.systemPackages = with pkgs; [
    xdg-utils
    wlvncc
    xlsclients
    # tightvnc
    # tigervnc
    networkmanagerapplet
    gparted
    gthumb
    vlc
    xrdb
    inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default
    # inputs.claude-desktop.packages.${system}.claude-desktop-fhs
    # Claude Desktop (FHS variant — needed for MCP servers: npx/uvx/docker),
    # wrapped to force 2x scaling. Electron ignores GDK_SCALE / the Hyprland
    # monitor scale, so we force it here. The Nix launcher forwards "$@" to
    # Electron (run_electron_and_cleanup), and the .desktop Exec is a bare
    # `claude-desktop` resolved from PATH, so this wrapper applies everywhere.
    (pkgs.symlinkJoin {
      name = "claude-desktop-fhs-scaled";
      paths = [ pkgs.claude-desktop-fhs ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/claude-desktop \
          --add-flags "--force-device-scale-factor=2"
      '';
    })
  ];
  # nixpkgs.config.permittedInsecurePackages = [ "tightvnc-1.3.10" ];

  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];

  programs.kdeconnect.enable = true;
  services.gnome.at-spi2-core.enable = true;
  # virtualisation.vmware.host.enable = true;
  programs.nm-applet.enable = true;

  services.cloudflare-warp.enable = true;

  # Pin the Zero Trust organization. Without this the client re-registers as a
  # personal "Free" account whenever the Teams session is lost, which swaps the
  # org's include-only split tunnel for the consumer exclude list -- i.e. full
  # tunnel for everything outside RFC1918. That both hides the internal
  # dashboards and swallows the home VPN endpoint (see ./openvpn.nix).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/cloudflare-warp/mdm.xml - - - - ${pkgs.writeText "warp-mdm.xml" ''
      <dict>
        <key>organization</key>
        <string>small-forest-3d80</string>
        <key>auto_connect</key>
        <integer>0</integer>
      </dict>
    ''}"
  ];

  # Cloudflare's Linux client cannot install the account Gateway CA on NixOS.
  # Trust it system-wide so CLI tools can verify WARP-only HTTPS services.
  security.pki.certificateFiles = [ ../../certificates/cloudflare-gateway-ca.pem ];
  security.polkit.enable = true;

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
    dumpcap.enable = true;
    usbmon.enable = true;
  };

  users.extraUsers.${username}.extraGroups = [ "wireshark" ];
  users.users.${username}.extraGroups = [
    "wireshark"
  ];

}
