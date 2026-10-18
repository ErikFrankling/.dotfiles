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

  # Managed policy for every Chromium-based browser (Helium, Chromium, Chrome).
  # Helium blocks third-party cookies by default, and Microsoft 365 web apps
  # renew their 24h sign-in token in a hidden login.microsoftonline.com iframe
  # that needs those cookies, so without this Teams logs out once a day.
  # Third-party cookie blocking is deliberately off everywhere: breaking logins
  # isn't worth it. BlockThirdPartyCookies = false is mandatory, so it also
  # overrides Helium's default and any per-profile "block" setting in Chrome.
  programs.chromium = {
    enable = true;
    extraOpts.BlockThirdPartyCookies = false;
    # LastPass, always present in the agent's Chromium (and thereby Helium,
    # which reads the same policy directory). The agent's permanent profile
    # keeps it logged in; see modules/home-manager/computer-use.
    extensions = [ "hdokiejnpimakedhajhdlcegeplioahd" ];
    # Earlier, narrower attempt: allow only Microsoft's domains.
    # extraOpts.CookiesAllowedForUrls = [
    #   "[*.]microsoftonline.com"
    #   "[*.]microsoft.com"
    #   "[*.]live.com"
    #   "[*.]office.com"
    #   "[*.]sharepoint.com"
    #   "[*.]skype.com"
    # ];
  };

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
    # inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default
    # Same Helium AppImage, re-wrapped so its bwrap sandbox can see the host's
    # /etc/chromium. Helium reads managed policies from /etc/chromium/policies,
    # but the upstream FHS wrapper only exposes a fixed set of host /etc paths,
    # so programs.chromium.extraOpts below would otherwise never reach it.
    (
      let
        helium = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;
        contents = pkgs.appimageTools.extract { inherit (helium) pname version src; };
      in
      pkgs.appimageTools.wrapType2 {
        inherit (helium) pname version src;
        extraBwrapArgs = [ "--ro-bind-try /etc/chromium /etc/chromium" ];
        extraInstallCommands = ''
          install -m 444 -D ${contents}/helium.desktop -t $out/share/applications
          substituteInPlace $out/share/applications/helium.desktop \
            --replace 'Exec=AppRun' 'Exec=helium'
          cp -r ${contents}/usr/share/icons $out/share
        '';
      }
    )
    # inputs.claude-desktop.packages.${system}.claude-desktop-fhs
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

  # WARP cannot parse NixOS's systemd version ("261.3", no dash), so it never
  # programs systemd-resolved and falls back to overwriting /etc/resolv.conf
  # with its local resolver. Programs that go through resolved (nearly all of
  # them, via nss-resolve) then never ask that resolver once Mullvad claims
  # `~.` on its own link, and the Gateway-only work names stop resolving.
  # Naming the work domains here routes exactly those to WARP's resolver
  # whatever else is up.
  services.resolved.settings.Resolve = {
    DNS = "127.0.2.2 127.0.2.3";
    Domains = "~husk-security.dev ~cloudflareaccess.com";
  };

  # Pin the Zero Trust organization. Without this the client re-registers as a
  # personal "Free" account whenever the Teams session is lost, which swaps the
  # org's include-only split tunnel for the consumer exclude list -- i.e. full
  # tunnel for everything outside RFC1918. That both hides the internal
  # dashboards and swallows the home VPN endpoint (see ./openvpn.nix).
  # The file must be copied (C+), not symlinked: warp-svc opens it without
  # following symlinks and a store symlink fails with ELOOP, so the whole
  # local policy (organization pin, service_mode) is silently ignored.
  systemd.tmpfiles.rules = [
    "C+ /var/lib/cloudflare-warp/mdm.xml 0644 root root - ${pkgs.writeText "warp-mdm.xml" ''
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
  # The setuid pkexec wrapper is opt-in since 2026-06. Every nixpkgs desktop
  # module (GNOME, XFCE, ...) turns it on; Hyprland has none, so GParted and
  # other GUI admin tools failed with "pkexec must be setuid root".
  security.polkit.enablePkexecWrapper = true;

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
