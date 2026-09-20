# Build Erik's source fork; auth, protocol and dictation changes live there.
# Keep the historical bundle patch file for reference, but do not apply it.
{
  inputs,
  otherPkgs,
  codexPackage ? null,
  claudePackage ? null,
}:
final: prev:
let
  system = prev.stdenv.hostPlatform.system;
  t3codeBase = otherPkgs.pkgsMaster.t3code;
in
{
  t3code = t3codeBase.override {
    t3code-unwrapped = t3codeBase.passthru.unwrapped.overrideAttrs (_: {
      src = inputs.t3code-src;
      # The fork retains v0.0.40's dependency lock; source changes do not require
      # another dependency download or a separately maintained package recipe.
      pnpmDeps = t3codeBase.passthru.unwrapped.pnpmDeps;
    });
    t3code-resource-monitor = t3codeBase.passthru.resourceMonitor;

    # Agent CLIs come from llm-agents everywhere else in this config; hand T3
    # the same binaries instead of the nixpkgs ones it would otherwise use.
    codex = if codexPackage != null then codexPackage else inputs.llm-agents.packages.${system}.codex;
    claude-code =
      if claudePackage != null then claudePackage else inputs.llm-agents.packages.${system}.claude-code;
    enableClaude = true;
  };
}
