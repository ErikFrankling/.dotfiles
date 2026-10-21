# Phone notifications for agents and scripts: the `notify-erik` CLI posts to
# Erik's private Discord server "Agents" (the app on his phone pushes it) and
# mirrors to the self-hosted ntfy (homelab repo, docs/notifications.md). The
# `notify` skill (modules/home-manager/notify) tells agents when to use it.
# Agents with Executor can also call `tools.notify.send`, which follows the
# same limits.
{ pkgs, username, ... }:

let
  notify-erik = pkgs.writeShellApplication {
    name = "notify-erik";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gawk
      gnugrep
      inetutils # hostname
      jq
      util-linux # flock
    ];
    text = builtins.readFile ./notify-erik.sh;
  };
in
{
  # Write-only on topic `erik`; shared by every host, so it lives outside the
  # per-host sops files.
  sops.secrets.ntfy-agents-token = {
    sopsFile = ../../../secrets/notify.yaml;
    owner = username;
  };
  # Delivery today: a webhook into #notifications of Erik's private Discord
  # server "Agents", and his user id for @mentions.
  sops.secrets.discord-webhook-url = {
    sopsFile = ../../../secrets/notify.yaml;
    owner = username;
  };
  sops.secrets.discord-user-id = {
    sopsFile = ../../../secrets/notify.yaml;
    owner = username;
  };
  # Erik's own ntfy login, for setting up the phone app.
  sops.secrets.ntfy-erik-password = {
    sopsFile = ../../../secrets/notify.yaml;
    owner = username;
  };

  environment.systemPackages = [ notify-erik ];
}
