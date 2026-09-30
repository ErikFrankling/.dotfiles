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
