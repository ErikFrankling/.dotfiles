{
  pkgs,
  username,
  inputs,
  config,
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
    # Claude Desktop (FHS variant — needed for MCP servers: npx/uvx/docker).
    # Deliberately unscaled: --force-device-scale-factor also doubles the
    # native Window Controls Overlay buttons that Electron paints for the
    # frameless main window, so they end up wildly out of proportion to the
    # web UI. Use the app's own zoom (Ctrl +) to size the content instead.
    pkgs.claude-desktop-fhs
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
        ${
          # On the framework, Tailscale owns DNS (tailnet override -> AdGuard),
          # so WARP must run "Secure Web Gateway without DNS filtering"
          # (tunnelonly): the include-mode split tunnel to the Husk ingress IPs
          # keeps working, but warp-svc no longer rewrites /etc/resolv.conf or
          # intercepts port 53 -- in the default warp+doh mode the two daemons
          # fight over DNS and connecting to the tailnet kills all resolution.
          # Caveat: hostname-based include entries are inert in this mode (they
          # rely on WARP snooping DNS answers), and so is Gateway's private-DNS
          # resolver policy, which never sees a query. The *.husk-security.dev
          # names are therefore resolved on the host by ./husk-dns.nix, which
          # maps them to the ingress VIPs (10.0.127.250/.251); the IP include
          # entries above are what actually routes them.
          # The pc keeps the default mode: it is off the tailnet, and its
          # Mullvad/WARP interplay is a separate question.
          pkgs.lib.optionalString (config.networking.hostName == "framework") ''
            <key>service_mode</key>
            <string>tunnelonly</string>
          ''
        }
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
