{
  pkgs,
  lib,
  hostName,
  ...
}:

# Every machine's T3 desktop app connects to the t3code server on the PC
# (hosts/pc/home.nix), so seed that connection instead of pairing by hand.
#
# The app keeps its connections in ~/.t3/userdata/connection-catalog.json,
# encrypted with Electron safeStorage. The desktop wrapper runs with
# --password-store=basic (overlays/t3code.nix), which is Chromium's "v10"
# scheme: AES-128-CBC with a key derived from the fixed password "peanuts".
# There is no secret in it, so the file can be generated here.
#
# The server runs with T3CODE_UNSAFE_NO_AUTH, which accepts any token, so the
# token below is a placeholder. The environment id is the PC server's
# ~/.t3/userdata/environment-id.
let
  environmentId = "638dd505-c97b-41e7-b7a7-7d91b3b9fd67";
  connectionId = "bearer:${environmentId}";
  # The PC talks to itself; other machines go through the homelab proxy.
  host =
    if hostName == "pc" then
      {
        http = "http://localhost:3773/";
        ws = "ws://localhost:3773/";
      }
    else
      {
        http = "https://t3code.erikfrankling.duckdns.org/";
        ws = "wss://t3code.erikfrankling.duckdns.org/";
      };

  entry = builtins.toJSON {
    target = {
      _tag = "BearerConnectionTarget";
      inherit environmentId connectionId;
      label = "pc";
    };
    profile = {
      _tag = "BearerConnectionProfile";
      inherit environmentId connectionId;
      label = "pc";
      httpBaseUrl = host.http;
      wsBaseUrl = host.ws;
    };
    credential = {
      inherit connectionId;
      credential = {
        _tag = "BearerConnectionCredential";
        token = "no-auth";
      };
    };
  };

  emptyCatalog = builtins.toJSON {
    schemaVersion = 1;
    targets = [ ];
    profiles = [ ];
    credentials = [ ];
    remoteDpopTokens = [ ];
    disabledEnvironmentIds = [ ];
  };

  seedScript = pkgs.writeShellApplication {
    name = "t3code-seed-connection";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.openssl
    ];
    text = ''
      file="$HOME/.t3/userdata/connection-catalog.json"
      # PBKDF2-SHA1("peanuts", "saltysalt", 1 iteration, 16 bytes), IV of spaces.
      key=fd621fe5a2b402539dfa147ca9272778
      iv=20202020202020202020202020202020

      decrypt() {
        jq -er .encryptedCatalog "$file" | base64 -d | tail -c +4 \
          | openssl enc -d -aes-128-cbc -K "$key" -iv "$iv"
      }

      catalog=${lib.escapeShellArg emptyCatalog}
      if [ -e "$file" ]; then
        if ! catalog=$(decrypt 2>/dev/null) || ! jq -e . <<<"$catalog" >/dev/null 2>&1; then
          echo "t3code: cannot read $file (not basic-text encrypted?), leaving it alone" >&2
          exit 0
        fi
      fi

      # Replace any older copy of the PC entry so a changed URL takes effect;
      # keep every other connection the app has saved. The app can switch an
      # environment off (it did after the v0.1 upgrade), so turn the PC back on.
      updated=$(jq -c --argjson e ${lib.escapeShellArg entry} '
        .disabledEnvironmentIds = [(.disabledEnvironmentIds // [])[] | select(. != $e.target.environmentId)]
        |
        .targets = ([.targets[] | select(.connectionId != $e.target.connectionId)] + [$e.target])
        | .profiles = ([.profiles[] | select(.connectionId != $e.profile.connectionId)] + [$e.profile])
        | .credentials = (
            [.credentials[] | select(.connectionId != $e.credential.connectionId)]
            + [(.credentials[] | select(.connectionId == $e.credential.connectionId)) // $e.credential]
          )
      ' <<<"$catalog")

      if [ -e "$file" ] && [ "$(jq -cS . <<<"$catalog")" = "$(jq -cS . <<<"$updated")" ]; then
        exit 0
      fi

      encrypted=$(
        { printf v10; printf '%s' "$updated" | openssl enc -e -aes-128-cbc -K "$key" -iv "$iv"; } \
          | base64 -w0
      )
      mkdir -p "$(dirname "$file")"
      jq -n --arg c "$encrypted" '{version: 1, encryptedCatalog: $c}' >"$file.tmp"
      mv "$file.tmp" "$file"
      echo "t3code: saved the pc connection in $file"
    '';
  };
in
{
  home.activation.t3codeConnection = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe seedScript}
  '';
}
