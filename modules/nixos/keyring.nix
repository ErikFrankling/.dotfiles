{ ... }:

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
}
