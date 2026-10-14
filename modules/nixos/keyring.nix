{
  pkgs,
  lib,
  username,
  ...
}:

let
  keyringDir = "/home/${username}/.local/share/keyrings";
  # Name of the passwordless keyring; "login" is avoided because gnome-keyring
  # treats that one as the keyring PAM unlocks with the login password.
  keyringName = "unlocked";
in
{
  # Secret Service (org.freedesktop.secrets) so Electron/Chromium safeStorage
  # works. Without it the Claude Code desktop app logs
  # "safeStorage isEncryptionAvailable=false (backend=basic_text)" and cannot
  # persist its login tokens: every app restart signs you out again, and
  # remote-session worker auth breaks (worker_auth_expired).
  services.gnome.gnome-keyring.enable = true;

  # This machine logs in through getty autologin, so PAM never sees a password
  # and can never unlock an encrypted keyring: every Secret Service request
  # then prompts for a keyring password. A keyring with no password is stored
  # as plain text and is always unlocked, so nothing ever prompts. The disk is
  # not encrypted either, so this gives up nothing.
  systemd.tmpfiles.rules = [
    "d ${keyringDir} 0700 ${username} users -"
    # `f` only creates the file when it is missing; the daemon writes the
    # stored secrets into it afterwards.
    "f ${keyringDir}/${keyringName}.keyring 0600 ${username} users - [keyring]\\ndisplay-name=${keyringName}\\nctime=0\\nmtime=0\\nlock-on-idle=false\\nlock-after=false\\n"
    # `f+` rewrites it every time: this is the keyring apps get by default.
    "f+ ${keyringDir}/default 0644 ${username} users - ${keyringName}"
  ];

  # Chromium/Electron only auto-detects the keyring on desktops it recognizes
  # (GNOME/KDE). Under Hyprland (XDG_CURRENT_DESKTOP=Hyprland) it silently
  # falls back to basic_text even with the Secret Service running, so the
  # flag must be forced. hiPrio makes this wrapper shadow the scaled
  # claude-desktop wrapper from desktop.nix in PATH, so the scale flag is
  # repeated here; the .desktop entries exec a bare `claude-desktop`, so GUI
  # launches pick up the flags too.
  environment.systemPackages = [
    (lib.hiPrio (
      pkgs.symlinkJoin {
        name = "claude-desktop-fhs-libsecret";
        paths = [ pkgs.claude-desktop-fhs ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/claude-desktop \
            --add-flags "--force-device-scale-factor=2" \
            --add-flags "--password-store=gnome-libsecret"
        '';
      }
    ))
  ];
}
