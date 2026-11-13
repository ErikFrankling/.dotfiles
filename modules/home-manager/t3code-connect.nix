{ lib, pkgs, ... }:

# T3 Connect for a T3 Code server: the official relay and Cloudflare tunnel,
# so the T3 apps reach this machine from anywhere after you sign in to a T3
# account, and webhook-triggered scheduled tasks get a public URL
# (https://relay.t3.codes/v1/hooks/...). The tunnel forwards every request to
# the server, so import this only on a server that requires logins: never
# with T3CODE_UNSAFE_NO_AUTH (the pc, until the fork drops that mode).
#
# The Nix build has no T3 Connect configuration baked in ("T3 Connect is
# unavailable in builds without public configuration"). These are the values
# upstream bakes into its official releases, published in the fork's
# .env.example as "public identifiers ..., not secrets". The server reads
# them at runtime (apps/server/src/cloud/publicConfig.ts), the CLI too, so
# `t3 connect status` works in a shell.
#
# cloudflared comes from nixpkgs instead of T3's own download into
# ~/.t3/tools (packages/shared/src/relayClient.ts, T3CODE_CLOUDFLARED_PATH;
# needs 2025.6.1 or newer).
#
# Linking is a one-time sign-in to your T3 account, then a server restart:
#   t3 connect link --headless    (open the URL, enter the code)
# The link survives rebuilds; it lives in ~/.t3/userdata/secrets.
let
  environment = {
    T3CODE_RELAY_URL = "https://relay.t3.codes";
    T3CODE_CLERK_PUBLISHABLE_KEY = "pk_live_Y2xlcmsudDMuY29kZXMk";
    T3CODE_CLERK_CLI_OAUTH_CLIENT_ID = "hzxSgY2cH10sDU2r";
    T3CODE_CLOUDFLARED_PATH = lib.getExe pkgs.cloudflared;
  };
in
{
  home.sessionVariables = environment;
  systemd.user.services.t3code.Service.Environment = lib.mapAttrsToList (
    name: value: "${name}=${value}"
  ) environment;
}
