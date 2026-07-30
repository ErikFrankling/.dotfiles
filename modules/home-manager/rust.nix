{ pkgs, ... }:

{
  # Shared Rust compilation cache.
  #
  # sccache caches individual compilation units by content hash, so a crate
  # built in one project or git worktree is reused everywhere else. This is
  # preferred over a shared CARGO_TARGET_DIR: Cargo takes a lock on the target
  # directory, so a single shared one serialises concurrent builds across
  # projects, and `cargo clean` in one wipes them all.
  home.packages = [ pkgs.sccache ];

  programs.cargo = {
    enable = true;

    # Only manage ~/.cargo/config.toml. Toolchains come from per-project Nix
    # dev shells, so installing a global cargo here would shadow them.
    package = null;

    settings.build.rustc-wrapper = "${pkgs.sccache}/bin/sccache";
  };

  home.sessionVariables = {
    # sccache hashes absolute paths, so the same crate in two worktrees would
    # otherwise miss. Stripping these prefixes is what makes worktrees share a
    # cache. Absolute paths only; colon-separated.
    SCCACHE_BASEDIRS = "/home/erikf/projects";

    # The default is 10G, which a few Rust workspaces evict straight through.
    SCCACHE_CACHE_SIZE = "50G";
  };
}
