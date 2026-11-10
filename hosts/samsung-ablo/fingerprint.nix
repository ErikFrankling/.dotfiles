# Fingerprint reader: Goodix 27c6:6984, supported by libfprint (goodixmoc).
# Enroll a finger once with `fprintd-enroll`. Unlocks hyprlock.
{ username, ... }:
{
  services.fprintd.enable = true;

  # hyprlock talks to fprintd itself; with pam_fprintd in its PAM stack too,
  # it would wait for the finger before taking the password.
  security.pam.services.hyprlock.fprintAuth = false;
  home-manager.users.${username}.programs.hyprlock.settings.auth = {
    "fingerprint:enabled" = true;
    "fingerprint:ready_message" = "Touch the fingerprint reader or enter your password";
    "fingerprint:present_message" = "Reading fingerprint…";
  };
}
