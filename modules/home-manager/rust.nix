{ pkgs, ... }:

let
  # Cargo never deletes old build output, so target/ dirs only grow: every
  # branch, worktree and toolchain leaves its own copy of each crate behind.
  # husk_platform's shared target dir reached 138G, 99% of it months old.
  cargoSweep = pkgs.writeShellApplication {
    name = "cargo-sweep-projects";
    # cargo is only on this unit's PATH (cargo-sweep runs `cargo metadata` to
    # find each project's target dir). Toolchains still come from dev shells.
    runtimeInputs = [
      pkgs.cargo
      pkgs.cargo-sweep
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      export CARGO_NET_OFFLINE=true

      # cargo-sweep only needs `cargo metadata` to report the target dir, so
      # any manifest does when CARGO_TARGET_DIR points at the dir to sweep.
      dummy=$(mktemp -d)
      trap 'rm -rf "$dummy"' EXIT
      printf '[package]\nname = "sweep"\nversion = "0.0.0"\n' >"$dummy/Cargo.toml"
      mkdir "$dummy/src" && touch "$dummy/src/lib.rs"

      # Every Cargo target dir under these roots, wherever CARGO_TARGET_DIR
      # put it (husk keeps several outside the projects, in hidden dirs).
      # Cargo writes .rustc_info.json at the top of each one. find exits 1 on
      # the dirs it may not read (llama-cpp's models), which is fine.
      {
        find "$HOME/projects" "$HOME/work" /mnt/data -xdev \
          \( -name node_modules -o -name .git \) -prune -o \
          -type f -name .rustc_info.json -printf '%h\0' 2>/dev/null || true
      } |
        while IFS= read -r -d "" target; do
          # Artifacts not used in 14 days. cargo-sweep goes by atime, which
          # relatime still updates once a day; it breaks on a noatime mount.
          CARGO_TARGET_DIR="$target" cargo sweep --time 14 "$dummy" || true

          # cargo-sweep skips incremental/. A crate's incremental dir gets a
          # new session on every build that uses it, so mtime marks the stale
          # ones.
          find "$target" -mindepth 2 -maxdepth 3 -type d -name incremental -print0 |
            while IFS= read -r -d "" dir; do
              find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
            done
        done
    '';
  };
in
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

  systemd.user.services.cargo-sweep = {
    Unit.Description = "Delete Cargo build artifacts not used in 14 days";
    Service = {
      Type = "oneshot";
      ExecStart = "${cargoSweep}/bin/cargo-sweep-projects";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.cargo-sweep = {
    Unit.Description = "Daily Cargo build artifact sweep";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
