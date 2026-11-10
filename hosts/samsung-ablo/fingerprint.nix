# Fingerprint reader: Goodix 27c6:6984, supported by libfprint (goodixmoc).
# Enroll a finger once with `fprintd-enroll`. Unlocks hyprlock.
{ username, ... }:
{
  services.fprintd.enable = true;

  # hyprlock talks to fprintd itself; with pam_fprintd in its PAM stack too,
  # it would wait for the finger before taking the password.
  security.pam.services.hyprlock.fprintAuth = false;

  # LXQt 2.4's authentication agent crashed in Session::completed after a
  # 1Password fingerprint request (2026-11-10). Use the upstream GNOME
  # agent, managed by Home Manager, instead of the unsupervised LXQt agent.
  home-manager.users.${username}.services.polkit-gnome.enable = true;
  home-manager.users.${username}.systemd.user.services.polkit-gnome.Service.Restart = "on-failure";

  home-manager.users.${username}.programs.hyprlock.settings.auth = {
    "fingerprint:enabled" = true;
    "fingerprint:ready_message" = "Touch the fingerprint reader or enter your password";
    "fingerprint:present_message" = "Reading fingerprint…";
  };
}
