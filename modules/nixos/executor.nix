{ ... }:
{
  # Executor (https://executor.sh/docs/hosted/docker), self-hosted. Web UI at
  # http://localhost:4788, MCP endpoint at http://localhost:4788/mcp. The
  # first account created becomes the owner; further users come in via
  # invite links from the Admin page.
  #
  # Bound to loopback only. To expose it on the LAN, bind 0.0.0.0, open 4788
  # on eno1, and set EXECUTOR_WEB_BASE_URL to the exact URL browsers use --
  # a mismatch rejects logins with an invalid-origin error.
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.executor = {
    image = "ghcr.io/rhyssullivan/executor-selfhost:latest";
    # :latest is only fetched when missing unless told otherwise; check for a
    # newer image on every service start.
    pull = "newer";
    ports = [ "127.0.0.1:4788:4788" ];
    # SQLite database and encryption keys. Back up by copying this directory.
    volumes = [ "/var/lib/executor:/data" ];
  };

  systemd.tmpfiles.rules = [ "d /var/lib/executor 0700 root root -" ];
}
