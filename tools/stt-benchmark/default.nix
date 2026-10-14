{
  model ? "granite-bf16",
}:
let
  pkgs = import ./pkgs.nix;
  models = builtins.fromJSON (builtins.readFile ./models.json);
  selected = models.${model};
in
pkgs.linkFarm "stt-benchmark-${model}" (
  [
    {
      name = "model.gguf";
      path = pkgs.fetchurl selected.model;
    }
  ]
  ++ pkgs.lib.optional (selected ? projector) {
    name = "mmproj.gguf";
    path = pkgs.fetchurl selected.projector;
  }
)
