final: prev: {
  # Backport the monitor reconnect fix until nixpkgs moves beyond 0.15.0.
  # https://github.com/hyprwm/aquamarine/pull/410
  # Also guard cleared connectors during exit (aquamarine#383, still open and
  # not in 0.15.1). Compare the version so a new release is looked at again.
  aquamarine =
    if
      builtins.elem prev.aquamarine.version [
        "0.15.0"
        "0.15.1"
      ]
    then
      prev.aquamarine.overrideAttrs (old: {
        patches =
          (old.patches or [ ])
          ++ prev.lib.optional (prev.aquamarine.version == "0.15.0") ./aquamarine-disconnect.patch
          ++ [ ./aquamarine-exit.patch ];
      })
    else
      prev.aquamarine;
}
