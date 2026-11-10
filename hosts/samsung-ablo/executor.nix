{ ... }:
{
  # Independent work instance: no personal integrations or account database.
  # Upstream selfhost image, pinned to the version already used successfully
  # in the homelab. The UI, API and MCP share port 4400.
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.executor-work = {
    image = "ghcr.io/usefulsoftwareco/executor-selfhost:2.0.0-beta.24@sha256:39d8ce360adf86df46e953f43551dad4440d04d7246d30fc7b0d6f3f5cfed3f7";
    ports = [ "127.0.0.1:4788:4400" ];
    volumes = [ "/var/lib/executor-work:/app/data" ];
    environment = {
      BETTER_AUTH_URL = "http://localhost:4788";
      DO_NOT_TRACK = "1";
    };
    extraOptions = [
      "--memory=3g"
      "--cpus=2"
    ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/executor-work 0700 root root -" ];
}
