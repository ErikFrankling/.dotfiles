{
  model ? "audio-flamingo-next",
}:
let
  pkgs = import ./pkgs.nix;
  models = builtins.fromJSON (builtins.readFile ./frontier-models.json);
in
pkgs.linkFarm "stt-frontier-${model}" (
  map (file: {
    inherit (file) name;
    path = pkgs.fetchurl { inherit (file) url sha256; };
  }) models.${model}.files
)
