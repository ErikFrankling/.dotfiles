# T3 Code, patched.
#
# nixpkgs tracks upstream releases and builds both the `t3` server CLI and the
# desktop app, so this only adds what this machine needs on top:
#
#   * the JSON-RPC 2.0 envelopes codex refuses to work without
#   * an opt-in unauthenticated mode, gated on T3CODE_UNSAFE_NO_AUTH=1
#
# Both live in t3code-patches.js and fail the build by name if upstream moves
# the code they anchor to.
#
# `t3code-unwrapped` and the resource-monitor sidecar are private defaults of
# the wrapper rather than package-set attributes, so they are reached through
# passthru: patch the first, pass the second through untouched so it is not
# rebuilt for a change that cannot affect it.
{ inputs }:
final: prev:
let
  system = prev.stdenv.hostPlatform.system;
in
{
  t3code = prev.t3code.override {
    t3code-unwrapped = prev.t3code.passthru.unwrapped.overrideAttrs (oldAttrs: {
      postFixup = (oldAttrs.postFixup or "") + ''
        export T3CODE_BUNDLE="$out/libexec/t3code/apps/server/dist/bin.mjs"
        ${prev.nodejs}/bin/node ${./t3code-patches.js}
      '';
    });
    t3code-resource-monitor = prev.t3code.passthru.resourceMonitor;

    # Agent CLIs come from llm-agents everywhere else in this config; hand T3
    # the same binaries instead of the nixpkgs ones it would otherwise use.
    codex = inputs.llm-agents.packages.${system}.codex;
    claude-code = inputs.llm-agents.packages.${system}.claude-code;
    enableClaude = true;
  };
}
