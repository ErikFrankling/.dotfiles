# Fingerprint reader, unlocking hyprlock (and 1Password/polkit through PAM).
# samsung-ablo: Goodix 27c6:6984. Framework: its Goodix reader (goodixmoc).
# Both are supported by libfprint. Enroll a finger once with `fprintd-enroll`.
{ username, ... }:
{
  services.fprintd.enable = true;

  # hyprlock talks to fprintd itself; with pam_fprintd in its PAM stack too,
  # it would wait for the finger before taking the password.
  security.pam.services.hyprlock.fprintAuth = false;

  # LXQt 2.4's authentication agent crashed in Session::completed after a
  # 1Password fingerprint request (2026-11-10). Use the upstream GNOME
  # agent, managed by Home Manager, instead of the unsupervised LXQt agent.
  home-manager.users.${username} = {
    services.polkit-gnome.enable = true;
    systemd.user.services.polkit-gnome.Service.Restart = "on-failure";

    programs.hyprlock.settings.auth = {
      "fingerprint:enabled" = true;
      "fingerprint:ready_message" = "Touch the fingerprint reader or enter your password";
      "fingerprint:present_message" = "Reading fingerprint…";
    };
  };
}
