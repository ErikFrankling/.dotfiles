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

  # sccache from main until a release has these (0.19.0, the nixpkgs one,
  # does not): SCCACHE_BASEDIRS for Rust keys (#2918), proc macros keyed by
  # their crate metadata instead of their .so bytes, and
  # SCCACHE_BASEDIRS_VERBATIM_ENV_DEPS (#3022). Without them no crate of a
  # path dependency or a worktree can hit in another checkout. A small Rust
  # build, made on the homelab builder and served from its cache.
  # Drop this override once nixpkgs has a release with #2918 and #3022.
  sccache = pkgs.sccache.overrideAttrs (old: {
    version = "0.19.0-unstable-2026-11-16";
    src = pkgs.fetchFromGitHub {
      owner = "mozilla";
      repo = "sccache";
      rev = "433cf4c5510304ccbe1d36b0d18c84b4d391fc1b";
      hash = "sha256-AgYt3sXshJhmOCNA3uV7DMemfuamGWfFRtMTXhKPtwo=";
    };
    cargoHash = "sha256-+f2Mc74MC252OwY/LmwveLZUzgK8DeJ5O+1rukUQqmI=";
    # main's aws-lc-sys wants a system aws-lc (nixpkgs' cargo hook sets
    # AWS_LC_SYS_USE_SYSTEM=1).
    buildInputs = old.buildInputs ++ [ pkgs.aws-lc ];
  });

  # The shared cache: plain files named by key, on the root disk. No size
  # cap (Erik, 2026-11-17: a cap is a hard limit he does not want); the
  # sccache-gc timer below removes what was not used for 30 days.
  sccacheDir = "$HOME/.cache/sccache";

  # Cargo's RUSTC_WRAPPER (~/.cargo/config.toml below). A wrapper is the only
  # way: sccache has no setting for "one server per cgroup" or "basedirs
  # from this compile", both of which have to be chosen per rustc call.
  #
  # - One sccache server per cgroup (systemd scope or service) and project:
  #   the socket name is a hash of /proc/self/cgroup and the basedirs, so
  #   the first rustc of a scope starts its server inside that scope (the
  #   client forks it), and no other scope ever talks to it. Client-side
  #   mode runs rustc in the client, the child of cargo, so compiles run and
  #   are accounted where cargo runs even apart from that; the server only
  #   reads and writes the cache dir. It exits after 5 idle minutes. A cargo
  #   run in its own scope (app-t3code-cargo.slice, agent-priority) gets a
  #   server of its own in that scope.
  #   Servers do not see entries another server wrote after it started, so
  #   two builds running at the same moment do not share; the next build
  #   (a new server) sees both.
  # - SCCACHE_BASEDIRS = the checkout the compile runs in (cargo's cwd for
  #   workspace crates and path dependencies, so vendored crates such as
  #   wasm-box's third_party/wasmtime) and the target dir (from --out-dir,
  #   wherever CARGO_TARGET_DIR points): the cwd, CARGO_* variables, OUT_DIR
  #   and arguments are hashed relative to them, so the same crate hits in
  #   every worktree and target dir.
  # - --remap-path-prefix for both makes rustc's output itself independent
  #   of them. Without it the metadata of a path-dependency proc macro (never
  #   cacheable, rebuilt in each checkout) names the checkout, and every
  #   crate using it, and everything after those, misses. Builds that remap
  #   paths themselves are left alone. Side effect: paths of the checkout in
  #   debug info and panics are relative to it (target files read target/).
  # - Correctness: crates that bake env!("CARGO_MANIFEST_DIR") into their
  #   output stay keyed per checkout (VERBATIM_ENV_DEPS). The key keeps the
  #   compiler, all other flags, sources, externs and env-deps.
  # - Only real compiles go through sccache (cargo passes --out-dir); probes
  #   such as `rustc -vV` run rustc directly.
  rustcCache = pkgs.writeShellApplication {
    name = "rustc-cache";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      cgroup=
      while IFS= read -r line; do
        case $line in 0::*) cgroup=''${line#0::} ;; esac
      done </proc/self/cgroup

      out=
      prev=
      for arg in "$@"; do
        case $prev in --out-dir) out=$arg ;; esac
        case $arg in --out-dir=*) out=''${arg#--out-dir=} ;; esac
        prev=$arg
      done
      [ -n "$out" ] || exec "$@"

      # <target>[/<triple>]/<profile>/deps or .../<profile>/build/<unit>
      target=
      case $out in
        */deps) target=''${out%/deps} && target=''${target%/*} ;;
        */build/*) target=''${out%/build/*} && target=''${target%/*} ;;
      esac

      # The checkout cargo runs this rustc in: set for workspace crates and
      # path dependencies, empty for registry and git crates (their cwd is
      # their own source dir), so their keys do not depend on the checkout.
      root=
      dir=$PWD
      while [ -n "$dir" ] && [ "$dir" != / ]; do
        if [ -e "$dir/.git" ]; then root=$dir && break; fi
        dir=''${dir%/*}
      done

      basedirs=$root
      remap=()
      if [ -n "$root" ]; then remap+=("--remap-path-prefix=$root/="); fi
      if [ -n "$target" ]; then
        basedirs=''${basedirs:+$basedirs:}$target
        remap+=("--remap-path-prefix=$target/=target/")
      fi
      case " $* " in *" --remap-path-prefix"*) remap=() ;; esac

      run=''${XDG_RUNTIME_DIR:-/run/user/$UID}/sccache
      [ -d "$run" ] || mkdir -m 700 "$run" 2>/dev/null || true
      key=$(printf '%s\n%s\n' "$cgroup" "$basedirs" | sha256sum)

      export SCCACHE_SERVER_UDS=$run/''${key:0:20}.sock
      export SCCACHE_BASEDIRS=$basedirs
      export SCCACHE_BASEDIRS_VERBATIM_ENV_DEPS=CARGO_MANIFEST_DIR,CARGO_MANIFEST_PATH
      export SCCACHE_DIR=${sccacheDir}
      # Never evicts in practice; sccache-gc cleans by age.
      export SCCACHE_CACHE_SIZE=1T
      export SCCACHE_CLIENT_SIDE=1
      export SCCACHE_IDLE_TIMEOUT=300
      # CARGO_INCREMENTAL=1 builds work; their incremental crates go uncached.
      export SCCACHE_ALLOW_INCREMENTAL=1
      # Each of these would turn client-side mode off, point at another
      # server or skip the cache.
      unset SCCACHE_SERVER_PORT SCCACHE_ERROR_LOG SCCACHE_LOG SCCACHE_NO_DAEMON \
        SCCACHE_RECACHE SCCACHE_CONF SCCACHE_NO_CACHE

      exec ${sccache}/bin/sccache "$@" "''${remap[@]}"
    '';
  };

  # Deletes cache entries neither read nor written for 30 days, and nothing
  # else: only files whose path is exactly sccache's entry layout
  # (<k0>/<k1>/<64-hex key>, preprocessor/<k0>/<k1>/<k2>/<key>) under the
  # cache dir, plus sccache's own temp files a crashed write left behind.
  # A hit reads the file, which moves its atime (relatime: at most once a
  # day); a server that still lists a deleted entry recompiles instead.
  sccacheGc = pkgs.writeShellApplication {
    name = "sccache-gc";
    runtimeInputs = [
      pkgs.findutils
      pkgs.coreutils
    ];
    text = ''
      dir=${sccacheDir}
      [ -f "$dir/CACHEDIR.TAG" ] || { echo "$dir is not an sccache dir"; exit 0; }
      before=$(du -sb "$dir" | cut -f1)
      find "$dir" -xdev -regextype posix-extended -type f \
        -regex "$dir/([0-9a-f]/[0-9a-f]|preprocessor/[0-9a-f]/[0-9a-f]/[0-9a-f])/[0-9a-f]{64}" \
        -atime +30 -mtime +30 -delete
      find "$dir" -xdev -maxdepth 1 -type f -name '.sccachetmp*' -mtime +1 -delete
      after=$(du -sb "$dir" | cut -f1)
      echo "sccache cache: $((before / 1048576)) MiB -> $((after / 1048576)) MiB"
    '';
  };
in
{
  # Shared Rust compilation cache, for every cargo build of Erik's (each
  # project, worktree, agent and his own shells). Off 2026-11-11 to
  # 2026-11-17 (one per-user server ran every agent's rustc inside one
  # thread's scope, and 1% of Rust compiles hit); see rustcCache above for
  # how both are solved now.
  #
  # Measured 2026-11-17 on wasm-box (cargo build -p wbox, dev): a fresh
  # worktree at another path with its own CARGO_TARGET_DIR got 213 hits of
  # 215 cacheable compiles (registry crates 100%, the vendored wasmtime fork
  # and the other path crates 23 of 25). What is left is not cacheable by
  # sccache: build scripts, proc macros, bins and tests, and workspace
  # crates in an incremental profile.
  #
  # Workspace crates stay incremental in dev (cargo's default): editing and
  # rebuilding one crate is what agents do most, and incremental does that
  # faster than any cache; release profiles are not incremental, so their
  # workspace crates are cached too. No shared CARGO_TARGET_DIR per project:
  # cargo locks a target dir for the whole build, so parallel agents would
  # queue behind each other, and the cache already shares crates.
  home.packages = [
    sccache
    sccacheGc
  ];

  programs.cargo = {
    enable = true;
    # Only manage ~/.cargo/config.toml. Toolchains come from per-project Nix
    # dev shells, so installing a global cargo here would shadow them.
    package = null;
    # An exported RUSTC_WRAPPER or a project's own build.rustc-wrapper
    # still wins over this (RUSTC_WRAPPER= cargo ... turns it off).
    settings.build.rustc-wrapper = "${rustcCache}/bin/rustc-cache";
  };

  systemd.user.services.sccache-gc = {
    Unit.Description = "Delete sccache entries not used in 30 days";
    Service = {
      Type = "oneshot";
      ExecStart = "${sccacheGc}/bin/sccache-gc";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.sccache-gc = {
    Unit.Description = "Daily sccache age-based cleanup";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
    Install.WantedBy = [ "timers.target" ];
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
