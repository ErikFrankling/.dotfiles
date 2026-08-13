{ pkgs, lib, ... }:

{
  # Secret Service (org.freedesktop.secrets) so Electron/Chromium safeStorage
  # works. Without it the Claude Code desktop app logs
  # "safeStorage isEncryptionAvailable=false (backend=basic_text)" and cannot
  # persist its login tokens: every app restart signs you out again, and
  # remote-session worker auth breaks (worker_auth_expired).
  services.gnome.gnome-keyring.enable = true;

  # Hyprland is started from a tty login shell (start-hyprland in fish), so
  # the `login` PAM service is what must unlock the keyring with the login
  # password. A display manager would use its own PAM service instead.
  security.pam.services.login.enableGnomeKeyring = true;

  # Chromium/Electron only auto-detects the keyring on desktops it recognizes
  # (GNOME/KDE). Under Hyprland (XDG_CURRENT_DESKTOP=Hyprland) it silently
  # falls back to basic_text even with the Secret Service running, so the
  # flag must be forced. hiPrio makes this wrapper shadow the unwrapped
  # claude-desktop-fhs from desktop.nix in PATH; the .desktop entries exec a
  # bare `claude-desktop`, so GUI launches pick up the flag too.
  environment.systemPackages = [
    (lib.hiPrio (
      pkgs.symlinkJoin {
        name = "claude-desktop-fhs-libsecret";
        paths = [ pkgs.claude-desktop-fhs ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/claude-desktop \
            --add-flags "--password-store=gnome-libsecret"
        '';
      }
    ))
  ];
}
