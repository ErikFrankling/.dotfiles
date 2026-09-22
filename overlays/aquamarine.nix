final: prev: {
  # Backport the monitor reconnect fix until nixpkgs moves beyond 0.15.0.
  # https://github.com/hyprwm/aquamarine/pull/410
  # Also guard cleared connectors during exit (aquamarine#383).
  aquamarine =
    if prev.aquamarine.version == "0.15.0" then
      prev.aquamarine.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./aquamarine-disconnect.patch
          ./aquamarine-exit.patch
        ];
      })
    else
      prev.aquamarine;
}
